import InkFlowCore
import Foundation
import OSLog

@MainActor final class BroadcastLyrics {
    var onFailure: ((String) -> Void)?
    private let recognition: AudioRecognition
    private let catalog = NetEaseClient()
    private var publisher: LocalBroadcastPublisher?
    private let logger = Logger(subsystem: "com.inkflow.mobile", category: "BroadcastLyrics")
    private var connection: LocalBroadcastSession?
    private var lastState: LyricActivity.ContentState?
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
        do { connection = try LocalBroadcastStore.readSession() }
        catch {
            onFailure?("没有已准备的本机连接。请先在 InkFlow 点开始同步。")
            return
        }
        guard let connection else { return }
        let publisher = LocalBroadcastPublisher(sessionID: connection.id)
        publisher.onFailure = { [weak self] reason in self?.onFailure?(reason) }
        self.publisher = publisher
        started = true
        logger.info("Local audio recognition started; no APNs or relay server")
        recognition.onProgress = { [weak self] seconds in
            Task { @MainActor in self?.publisher?.progress(seconds) }
        }
        recognition.onMatch = { [weak self] observation in
            Task { @MainActor in self?.matched(observation) }
        }
        recognition.onLevel = { [weak self] level, uptime in
            Task { @MainActor in self?.received(level: level, at: uptime) }
        }
        recognition.onStatus = { [weak self] message in
            Task { @MainActor in
                guard let self, self.started, self.document == nil else { return }
                self.showMessage(message)
            }
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
        recognition.stop()
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
        if var state = lastState {
            state.position = state.time(at: Date())
            state.anchorDate = Date()
            state.playing = false
            state.connectionActive = false
            state.complete = true
            lastState = state
        }
        await publisher?.finish(lastState)
        publisher = nil
        connection = nil
    }

    func checkConnection() {
        guard started, let connection else { return }
        guard let saved = try? LocalBroadcastStore.readSession(), saved.id == connection.id else {
            started = false
            onFailure?("歌词连接已结束")
            Task { await stop() }
            return
        }
        let changed = saved.appearance != connection.appearance
        self.connection = saved
        if document != nil { refresh(force: changed) }
        else if ProcessInfo.processInfo.systemUptime - lastPublish >= 3 {
            showMessage(lastState?.message ?? "等待音乐音频；请在网易云播放")
        }
    }

    private func received(level: Double, at uptime: Double) {
        guard started else { return }
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
        let key = String(observation.song.id)
        if key == songKey {
            if document != nil {
                clock.followAudio(position: observation.position, observedAt: observation.uptime,
                                  lastSound: lastSound, now: ProcessInfo.processInfo.systemUptime)
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
                let song = observation.song
                let lyrics = try await catalog.lyrics(for: song)
                guard !Task.isCancelled, generation == requestGeneration else { return }
                document = lyrics
                clock.duration = song.duration
                clock.followAudio(position: observation.position, observedAt: observation.uptime,
                                  lastSound: lastSound, now: ProcessInfo.processInfo.systemUptime)
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
        guard let connection, let document else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let appearance = connection.appearance
        let position = clock.value(at: now) + appearance.calibration
        guard let selection = document.selection(at: position) else { return }
        let phrase = CompactLyrics.phrase(selection.line, at: position)
        let changed = selection.line.id != lastLineID || phrase.id != lastPhraseID || selection.waiting != lastWaiting
        let clockChanged = lastState.map {
            $0.playing != clock.running || abs($0.time(at: Date()) - position) > 0.3 || $0.appearance != appearance
        } ?? true
        guard changed || (force && clockChanged) || now - lastPublish >= 0.5 else { return }
        dates.update(clock, at: now, date: Date(), calibration: appearance.calibration)
        revision += 1
        var next = selection.next
        next?.words = []
        var state = LyricActivity.ContentState(line: selection.line, next: next, appearance: appearance,
            anchorDate: Date(), position: position, playing: clock.running, waiting: selection.waiting,
            repeated: document.lines.filter { $0.text == selection.line.text }.count > 1,
            revision: revision, source: .broadcast, playbackStart: dates.start, artwork: artwork,
            message: document.precision == .word ? "逐字同步" : "逐行同步 · 填充为估计", connectionActive: true)
        state.relaySession = connection.id
        lastPublish = now
        lastLineID = selection.line.id
        lastPhraseID = phrase.id
        lastWaiting = selection.waiting
        lastState = state
        publisher?.submit(state)
    }

    private func showMessage(_ message: String) {
        guard let connection else { return }
        var state = LyricActivity.ContentState.waiting(appearance: connection.appearance)
        state.source = .broadcast
        state.message = message
        state.connectionActive = started
        state.relaySession = connection.id
        revision += 1
        state.revision = revision
        lastState = state
        lastPublish = ProcessInfo.processInfo.systemUptime
        publisher?.submit(state)
    }
}
