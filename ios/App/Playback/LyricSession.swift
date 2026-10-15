import SwiftUI
import ActivityKit
import InkFlowCore

@MainActor final class LyricSession: ObservableObject {
    @Published var appearance: Appearance {
        didSet {
            if let data = try? JSONEncoder().encode(appearance) { UserDefaults.standard.set(data, forKey: "appearance") }
            refresh()
        }
    }
    @Published private(set) var title = "InkFlow"
    @Published private(set) var status = "效果预览"
    @Published private(set) var capturing = false
    @Published private(set) var connecting = false
    @Published private(set) var preview = true
    @Published private(set) var state: LyricActivity.ContentState?
    @Published private(set) var candidates: [NetEaseSong] = []
    @Published private(set) var level = 0.0
    @Published private(set) var startingIslandPreview = false
    let diagnostics = Diagnostics()
    private let capture = SystemAudioCapture()
    private let catalog = NetEaseClient()
    private var document = PreviewLyrics.document
    private var clock = PlaybackClock()
    private var activity: Activity<LyricActivity>?
    private var publication: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?
    private var tick: Task<Void, Never>?
    private var audioDeadline: Task<Void, Never>?
    private var lastSound = 0.0
    private var match: SongMatch?
    private var matchKey = ""
    private var revision = 0
    private var generation = 0
    private var trackID: Int64?
    private var quiet = false
    private var lastPublicationLog = 0.0
    private var lastPublishedLineStart: Double?

    var captureUnavailableReason: String? { capture.unavailableReason }

    init() {
        var saved = UserDefaults.standard.data(forKey: "appearance")
            .flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) } ?? Appearance()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--preview-style"), index + 1 < arguments.count,
           let style = LyricStyle(rawValue: arguments[index + 1]) { saved.style = style }
        #endif
        saved.normalize()
        appearance = saved
        clock.duration = PreviewLyrics.duration
        clock.align(position: 0, at: ProcessInfo.processInfo.systemUptime, running: true)
        #if DEBUG
        if let index = arguments.firstIndex(of: "--preview-time"), index + 1 < arguments.count,
           let position = Double(arguments[index + 1]) {
            clock.align(position: position, at: ProcessInfo.processInfo.systemUptime,
                        running: !arguments.contains("--preview-paused"))
        }
        #endif
        capture.onState = { [weak self] message, active in
            guard let self else { return }
            capturing = active
            if active { connecting = false }
            status = message
            diagnostics.record("capture", ["active": String(active), "message": message])
            if !active && !preview { clock.stop(at: ProcessInfo.processInfo.systemUptime); refresh() }
        }
        capture.onEnd = { [weak self] in
            guard let self else { return }
            connecting = false
            generation += 1
            resolveTask?.cancel()
            audioDeadline?.cancel()
            tick?.cancel()
            candidates = []
            await endIsland()
        }
        capture.recognition.onMatch = { [weak self] match in
            Task { @MainActor in self?.received(match) }
        }
        capture.recognition.onLevel = { [weak self] level, uptime in
            Task { @MainActor in self?.received(level: level, uptime: uptime) }
        }
        capture.recognition.onError = { [weak self] error in
            Task { @MainActor in self?.diagnostics.record("recognition-error", ["message": error]) }
        }
        refresh()
    }

    func beginCapture() async {
        guard !capturing, !connecting else { return }
        if let reason = capture.unavailableReason {
            status = reason
            diagnostics.record("capture-unavailable", ["reason": reason])
            return
        }
        connecting = true
        generation += 1
        resolveTask?.cancel()
        tick?.cancel()
        audioDeadline?.cancel()
        await retireIsland()
        preview = false
        state = .waiting(appearance: appearance)
        match = nil
        matchKey = ""
        trackID = nil
        candidates = []
        clock.stop(at: ProcessInfo.processInfo.systemUptime)
        lastSound = ProcessInfo.processInfo.systemUptime
        quiet = false
        // 先在前台创建活动，切到网易云后只更新它，不在后台重新申请。
        await startIsland()
        capture.start()
    }

    func stopCapture() async {
        await capture.stop()
    }

    func startPreview() async {
        await stopCapture()
        preview = true
        document = PreviewLyrics.document
        title = "InkFlow"
        status = "效果预览"
        clock.duration = PreviewLyrics.duration
        clock.align(position: 0, at: ProcessInfo.processInfo.systemUptime, running: true)
        diagnostics.record("preview-start")
        refresh()
    }

    func startIslandPreview() async {
        guard !startingIslandPreview else { return }
        startingIslandPreview = true
        defer { startingIslandPreview = false }
        await startPreview()
        await startIsland()
    }

    func togglePreviewPlayback() {
        guard preview else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let finished = clock.hasFinished(at: now)
        clock.align(position: finished ? 0 : clock.value(at: now), at: now, running: finished || !clock.running)
        status = clock.running ? "效果预览" : "预览已暂停"
        refresh()
    }

    func seekPreview(_ position: Double) {
        guard preview else { return }
        clock.align(position: position, at: ProcessInfo.processInfo.systemUptime, running: clock.running)
        status = clock.running ? "效果预览" : "预览已暂停"
        refresh()
    }

    func startIsland() async {
        guard let state else { return }
        if let current = activity, current.activityState != .active && current.activityState != .stale {
            activity = nil
        }
        if activity == nil {
            activity = Activity<LyricActivity>.activities.first {
                $0.activityState == .active || $0.activityState == .stale
            }
        }
        if activity != nil { publish(state); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "请在系统设置中允许实时活动"; return
        }
        do {
            activity = try Activity.request(attributes: LyricActivity(song: "InkFlow"),
                content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
            diagnostics.record("island-start", ["source": preview ? "preview" : "capture"])
        } catch { status = error.localizedDescription; diagnostics.record("island-error", ["message": status]) }
    }

    private func retireIsland() async {
        publication?.cancel()
        await publication?.value
        publication = nil
        // Include activities from an earlier app launch, not just the in-memory reference.
        var existing = Activity<LyricActivity>.activities
        if let activity, !existing.contains(where: { $0.id == activity.id }) { existing.append(activity) }
        activity = nil
        for current in existing { await current.end(nil, dismissalPolicy: .immediate) }
        lastPublishedLineStart = nil
    }

    func endIsland() async {
        await retireIsland()
    }

    func sceneChanged(_ phase: ScenePhase) {
        diagnostics.record("scene", ["phase": String(describing: phase),
            "source": preview ? "preview" : "capture",
            "position": String(clock.value(at: ProcessInfo.processInfo.systemUptime))])
        if phase == .active { refresh() }
        do { _ = try diagnostics.export() }
        catch { diagnostics.record("diagnostics-write-error", ["message": error.localizedDescription]) }
    }

    private func received(_ observation: SongMatch) {
        guard capturing, !preview else { return }
        match = observation
        quiet = false
        let key = observation.title + "|" + observation.artist
        diagnostics.record("match", ["position": String(observation.position), "song": observation.title])
        if key == matchKey, trackID != nil {
            clock.align(position: observation.position, at: observation.uptime, running: true)
            status = document.precision == .word ? "逐字同步" : "逐行同步 · 填充为估计"
            refresh()
            return
        }
        guard key != matchKey else { return }
        matchKey = key
        trackID = nil
        let waiting = LyricActivity.ContentState.waiting(appearance: appearance)
        state = waiting
        publish(waiting)
        tick?.cancel()
        resolveTask?.cancel()
        let requestGeneration = generation
        status = "正在获取歌词"
        resolveTask = Task {
            do {
                let songs = try await catalog.search(title: observation.title, artist: observation.artist)
                guard !Task.isCancelled, generation == requestGeneration, matchKey == key else { return }
                if let song = NetEaseClient.bestMatch(songs, title: observation.title, artist: observation.artist) {
                    await select(song)
                } else {
                    candidates = songs
                    status = "请选择歌曲版本"
                }
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                matchKey = ""
                status = error.localizedDescription
            }
        }
    }

    func select(_ song: NetEaseSong) async {
        guard let observed = match else { return }
        let requestGeneration = generation
        let requestKey = matchKey
        do {
            let lyrics = try await catalog.lyrics(for: song)
            guard !Task.isCancelled, generation == requestGeneration, requestKey == matchKey else { return }
            document = lyrics
            candidates = []
            trackID = song.id
            title = song.title
            let latest = match ?? observed
            clock.duration = song.duration
            clock.align(position: latest.position, at: latest.uptime, running: !quiet)
            status = lyrics.lines.isEmpty ? "这首歌没有歌词" : (lyrics.precision == .word ? "逐字同步" : "逐行同步 · 填充为估计")
            diagnostics.record("lyrics", ["id": String(song.id), "lines": String(lyrics.lines.count), "precision": lyrics.precision.rawValue])
            refresh()
        } catch {
            guard generation == requestGeneration, requestKey == matchKey else { return }
            matchKey = ""
            status = error.localizedDescription
        }
    }

    private func received(level: Double, uptime: Double) {
        guard capturing, !preview else { return }
        self.level = level
        if level > 0.00001 { lastSound = uptime }
        // 音频中断并不能证明网易云暂停。失去声音后先冻结，等指纹重新确认位置。
        if uptime - lastSound > 1.2, !quiet {
            quiet = true
            clock.stop(at: lastSound)
            status = "音频静默，等待重新校时"
            diagnostics.record("clock-unconfirmed", ["reason": "silent-audio"])
            refresh()
        }
        audioDeadline?.cancel()
        audioDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            guard let self, capturing else { return }
            quiet = true
            clock.stop(at: uptime)
            status = "等待音频恢复"
            diagnostics.record("clock-unconfirmed", ["reason": "missing-buffers"])
            refresh()
        }
    }

    func refresh() {
        tick?.cancel()
        guard preview || trackID != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let complete = preview && clock.hasFinished(at: now)
        if complete {
            if clock.running { diagnostics.record("preview-complete") }
            clock.stop(at: now)
            status = "预览已结束 · 点播放重新开始"
        }
        let position = clock.value(at: now) + appearance.calibration
        guard let selection = document.selection(at: position) else { state = nil; return }
        revision += 1
        var nextLine = selection.next
        nextLine?.words = []
        let content = LyricActivity.ContentState(line: selection.line, next: nextLine,
            appearance: appearance, anchorDate: Date(), position: position, playing: clock.running,
            waiting: selection.waiting, repeated: document.lines.filter { $0.text == selection.line.text }.count > 1,
            revision: revision, source: preview ? .preview : .capture, complete: complete)
        state = content
        publish(content)
        guard clock.running else { return }
        let times = document.lines.flatMap { [$0.start, $0.end] + $0.words.flatMap { [$0.start, $0.end] } }
        let next = times.filter { $0 > position + 0.01 }.min() ?? position + 0.75
        let delay = clamped(next - position, 0.15, 0.75)
        tick = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.refresh()
        }
    }

    private func publish(_ content: LyricActivity.ContentState) {
        guard let activity else { return }
        do {
            let bytes = try JSONEncoder().encode(content).count + JSONEncoder().encode(activity.attributes).count
            guard bytes < 4_000 else {
                diagnostics.record("island-payload-rejected", ["bytes": String(bytes)])
                status = "这句歌词超过实时活动容量，需要分段适配"
                return
            }
        } catch { diagnostics.record("island-encoding-error"); return }
        publication?.cancel()
        publication = Task {
            guard !Task.isCancelled else { return }
            await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
            guard !Task.isCancelled else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if content.line.start != lastPublishedLineStart || now - lastPublicationLog >= 5 {
                lastPublishedLineStart = content.line.start
                lastPublicationLog = now
                diagnostics.record("island-update-submitted", ["position": String(content.position),
                    "lineStart": String(content.line.start), "revision": String(content.revision)])
            }
        }
    }
}
