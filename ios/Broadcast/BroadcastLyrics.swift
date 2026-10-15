import ActivityKit
import InkFlowCore
import Foundation
import OSLog

@MainActor final class BroadcastLyrics {
    var onFailure: ((String) -> Void)?
    private let recognition: AudioRecognition
    private let catalog = NetEaseClient()
    private let publisher = LiveActivityPublisher()
    private let logger = Logger(subsystem: "com.inkflow.mobile", category: "BroadcastLyrics")
    private var activity: Activity<LyricActivity>?
    private var clock = PlaybackClock()
    private var dates = PlaybackDates()
    private var document: LyricDocument?
    private var artwork: Data?
    private var resolve: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var revision = 0
    private var generation = 0
    private var songKey = ""
    private var lastSound = 0.0
    private var lastPublish = 0.0
    private var lastLineID: String?
    private var lastPhraseID: String?
    private var lastWaiting = false
    private var started = false

    init(recognition: AudioRecognition) { self.recognition = recognition }

    func start() {
        let activities = Activity<LyricActivity>.activities
        logger.info("Available activities: \(activities.count)")
        guard let activity = activities.first(where: {
            $0.content.state.source == .broadcast && ($0.activityState == .active || $0.activityState == .stale)
        }) else {
            onFailure?("系统音频扩展未能访问歌词实时活动。请返回 InkFlow 重新连接；若仍出现此提示，本机连接方式尚不可用。")
            return
        }
        self.activity = activity
        started = true
        recognition.onMatch = { [weak self] observation in
            Task { @MainActor in self?.matched(observation) }
        }
        recognition.onLevel = { [weak self] level, uptime in
            Task { @MainActor in self?.received(level: level, at: uptime) }
        }
        recognition.onError = { [weak self] message in
            Task { @MainActor in
                self?.logger.error("Recognition: \(message, privacy: .public)")
                if self?.document == nil { self?.showMessage("识别暂不可用：" + String(message.prefix(80))) }
            }
        }
        recognition.reset()
        showMessage("连接已开始，等待网易云播放")
        armSilenceDeadline()
    }

    func pause() {
        silence?.cancel()
        clock.stop(at: ProcessInfo.processInfo.systemUptime)
        refresh(force: true)
    }

    func resume() {
        recognition.reset()
        armSilenceDeadline()
        if document == nil { showMessage("等待重新识别音乐") }
    }

    func stop() async {
        started = false
        generation += 1
        recognition.stop()
        resolve?.cancel()
        silence?.cancel()
        await publisher.cancel()
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }

    func checkConnection() {
        guard started, let activity else { return }
        guard activity.activityState == .active || activity.activityState == .stale else {
            started = false
            onFailure?("歌词连接已结束")
            Task { await stop() }
            return
        }
        if document == nil {
            var state = activity.content.state
            state.anchorDate = Date()
            publisher.submit(state, to: activity)
        } else if !clock.running {
            refresh(force: true)
        }
    }

    private func received(level: Double, at uptime: Double) {
        guard started, let activity else { return }
        guard activity.activityState == .active || activity.activityState == .stale else {
            started = false
            onFailure?("歌词连接已结束")
            Task { await stop() }
            return
        }
        if level > 0.00001 { lastSound = uptime }
        if clock.running && uptime - lastSound > 1.5 {
            clock.stop(at: lastSound)
            refresh(force: true)
        } else { refresh() }
        armSilenceDeadline()
    }

    private func armSilenceDeadline() {
        silence?.cancel()
        silence = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, started else { return }
            if clock.running { clock.stop(at: lastSound); refresh(force: true) }
            else if document == nil { showMessage("等待音乐音频；请在网易云播放") }
        }
    }

    private func matched(_ observation: SongMatch) {
        guard started else { return }
        let key = observation.title + "|" + observation.artist
        if key == songKey {
            if document != nil {
                clock.align(position: observation.position, at: observation.uptime, running: true)
                refresh(force: true)
            }
            return
        }
        generation += 1
        let requestGeneration = generation
        songKey = key
        resolve?.cancel()
        document = nil
        artwork = nil
        showMessage("已识别音乐，正在获取歌词")
        resolve = Task {
            do {
                let songs = try await catalog.search(title: observation.title, artist: observation.artist)
                guard !Task.isCancelled, generation == requestGeneration else { return }
                guard let song = NetEaseClient.bestMatch(songs, title: observation.title, artist: observation.artist) else {
                    songKey = ""
                    showMessage("未找到唯一匹配版本，等待再次识别")
                    return
                }
                let lyrics = try await catalog.lyrics(for: song)
                guard !Task.isCancelled, generation == requestGeneration else { return }
                document = lyrics
                clock.duration = song.duration
                clock.align(position: observation.position, at: observation.uptime, running: true)
                if lyrics.lines.isEmpty { showMessage("这首歌暂时没有歌词") }
                else { refresh(force: true) }
                let image = await catalog.artwork(for: song)
                guard !Task.isCancelled, generation == requestGeneration else { return }
                artwork = image
                refresh(force: true)
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                songKey = ""
                showMessage(error.localizedDescription)
            }
        }
    }

    private func refresh(force: Bool = false) {
        guard let activity, let document else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let appearance = activity.content.state.appearance
        let position = clock.value(at: now) + appearance.calibration
        guard let selection = document.selection(at: position) else { return }
        let phrase = CompactLyrics.phrase(selection.line, at: position)
        let changed = selection.line.id != lastLineID || phrase.id != lastPhraseID || selection.waiting != lastWaiting
        guard force || changed || (clock.running && now - lastPublish >= 1) else { return }
        dates.update(clock, at: now, date: Date(), calibration: appearance.calibration)
        revision += 1
        var next = selection.next
        next?.words = []
        let state = LyricActivity.ContentState(line: selection.line, next: next, appearance: appearance,
            anchorDate: Date(), position: position, playing: clock.running, waiting: selection.waiting,
            repeated: document.lines.filter { $0.text == selection.line.text }.count > 1,
            revision: revision, source: .broadcast, playbackStart: dates.start, artwork: artwork,
            message: document.precision == .word ? "逐字同步" : "逐行同步 · 填充为估计")
        lastPublish = now
        lastLineID = selection.line.id
        lastPhraseID = phrase.id
        lastWaiting = selection.waiting
        if !publisher.submit(state, to: activity) { showMessage("这句歌词过长，暂时无法在岛内显示") }
    }

    private func showMessage(_ message: String) {
        guard let activity else { return }
        var state = LyricActivity.ContentState.waiting(appearance: activity.content.state.appearance)
        state.source = .broadcast
        state.message = message
        revision += 1
        state.revision = revision
        publisher.submit(state, to: activity)
    }
}
