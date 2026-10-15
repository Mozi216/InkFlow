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
    @Published private(set) var previewDuration = PreviewLyrics.duration
    @Published private(set) var broadcastPrepared = false
    let diagnostics = Diagnostics()
    private let capture = SystemAudioCapture()
    private let catalog = NetEaseClient()
    private var document = PreviewLyrics.document
    private var clock = PlaybackClock()
    private var activity: Activity<LyricActivity>?
    private var activityObservation: Task<Void, Never>?
    private let publisher = LiveActivityPublisher()
    private var playbackDates = PlaybackDates()
    private var artworkData: Data?
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
    private let previewBackgroundTask = PreviewBackgroundTask()
    private var shortIslandPreview = false
    private var previewExpired = false

    var usesBroadcast: Bool {
        if #available(iOS 27.0, *) { return false }
        return true
    }

    var captureUnavailableReason: String? {
        #if targetEnvironment(simulator)
        return "系统音频连接需要真机；模拟器可测试歌词预览。"
        #else
        return usesBroadcast ? nil : capture.unavailableReason
        #endif
    }

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
        if let existing = Activity<LyricActivity>.activities.first(where: { $0.content.state.source == .broadcast }) {
            activity = existing
            broadcastPrepared = true
            preview = false
            tick?.cancel()
            state = existing.content.state
            status = state?.message ?? "系统音频连接"
            observeBroadcast(existing)
        }
    }

    func beginCapture() async {
        guard !capturing, !connecting else { return }
        if let reason = captureUnavailableReason {
            status = reason
            diagnostics.record("capture-unavailable", ["reason": reason])
            return
        }
        if usesBroadcast {
            connecting = true
            await prepareBroadcast()
            connecting = false
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
        broadcastPrepared = false
        await capture.stop()
        state = nil
    }

    private func prepareBroadcast() async {
        await stopCapture()
        tick?.cancel()
        preview = false
        broadcastPrepared = true
        var content = LyricActivity.ContentState.waiting(appearance: appearance)
        content.source = .broadcast
        content.message = "请在 InkFlow 中确认系统音频连接"
        state = content
        status = "点击下方系统按钮开始连接"
        await startIsland()
        if activity == nil { broadcastPrepared = false }
    }

    func startPreview() async {
        await stopCapture()
        preview = true
        shortIslandPreview = false
        previewExpired = false
        previewDuration = PreviewLyrics.duration
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
        shortIslandPreview = true
        previewDuration = PreviewLyrics.islandDuration
        document = PreviewLyrics.islandDocument
        clock.duration = previewDuration
        clock.align(position: 0, at: ProcessInfo.processInfo.systemUptime, running: true)
        status = "20 秒灵动岛演示"
        refresh()
        keepPreviewRunningBriefly()
        await startIsland()
        if activity == nil { previewBackgroundTask.end() }
    }

    func togglePreviewPlayback() {
        guard preview else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let finished = clock.hasFinished(at: now) || previewExpired
        previewExpired = false
        clock.align(position: finished ? 0 : clock.value(at: now), at: now, running: finished || !clock.running)
        if shortIslandPreview && clock.running && activity != nil { keepPreviewRunningBriefly() }
        else { previewBackgroundTask.end() }
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
        if let activity {
            publish(state)
            if broadcastPrepared { observeBroadcast(activity) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "请在系统设置中允许实时活动"; return
        }
        do {
            activity = try Activity.request(attributes: LyricActivity(song: "InkFlow"),
                content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
            if broadcastPrepared, let activity { observeBroadcast(activity) }
            diagnostics.record("island-start", ["source": preview ? "preview" : "capture"])
        } catch { status = error.localizedDescription; diagnostics.record("island-error", ["message": status]) }
    }

    private func retireIsland() async {
        previewBackgroundTask.end()
        activityObservation?.cancel()
        activityObservation = nil
        await publisher.cancel()
        // Include activities from an earlier app launch, not just the in-memory reference.
        var existing = Activity<LyricActivity>.activities
        if let activity, !existing.contains(where: { $0.id == activity.id }) { existing.append(activity) }
        activity = nil
        for current in existing { await current.end(nil, dismissalPolicy: .immediate) }
        lastPublishedLineStart = nil
    }

    func endIsland() async {
        broadcastPrepared = false
        await retireIsland()
    }

    private func observeBroadcast(_ activity: Activity<LyricActivity>) {
        activityObservation?.cancel()
        activityObservation = Task { [weak self] in
            for await update in activity.contentUpdates {
                guard !Task.isCancelled, let self, broadcastPrepared else { return }
                state = update.state
                status = update.state.message ?? "系统音频连接"
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastPublicationLog >= 5 {
                    lastPublicationLog = now
                    diagnostics.record("broadcast-update-received", ["position": String(update.state.position),
                        "playing": String(update.state.playing), "status": status])
                }
            }
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        diagnostics.record("scene", ["phase": String(describing: phase),
            "source": preview ? "preview" : "capture",
            "position": String(clock.value(at: ProcessInfo.processInfo.systemUptime))])
        if phase == .active {
            if broadcastPrepared, let activity {
                state = activity.content.state
                status = state?.message ?? "系统音频连接"
            } else { refresh() }
        }
        do { _ = try diagnostics.export() }
        catch { diagnostics.record("diagnostics-write-error", ["message": error.localizedDescription]) }
    }

    private func keepPreviewRunningBriefly() {
        // This assertion finishes a bounded preview. It is never used for NetEase sync.
        let granted = previewBackgroundTask.begin { [weak self] in
            guard let self else { return }
            previewExpired = true
            diagnostics.record("preview-background-expired")
            refresh()
        }
        diagnostics.record("preview-background-request", ["granted": String(granted)])
        if !granted {
            previewExpired = true
            refresh()
        }
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
            artworkData = nil
            candidates = []
            trackID = song.id
            title = song.title
            let latest = match ?? observed
            clock.duration = song.duration
            clock.align(position: latest.position, at: latest.uptime, running: !quiet)
            status = lyrics.lines.isEmpty ? "这首歌没有歌词" : (lyrics.precision == .word ? "逐字同步" : "逐行同步 · 填充为估计")
            diagnostics.record("lyrics", ["id": String(song.id), "lines": String(lyrics.lines.count), "precision": lyrics.precision.rawValue])
            refresh()
            let artwork = await catalog.artwork(for: song)
            guard generation == requestGeneration, trackID == song.id else { return }
            artworkData = artwork
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
        if broadcastPrepared {
            if let activity {
                var content = activity.content.state
                if content.appearance != appearance {
                    let now = Date()
                    content.position = content.time(at: now)
                    content.anchorDate = now
                    content.appearance = appearance
                    content.revision += 1
                    state = content
                    publish(content)
                }
            }
            return
        }
        guard preview || trackID != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let complete = preview && (clock.hasFinished(at: now) || previewExpired)
        if complete {
            if clock.running { diagnostics.record("preview-complete") }
            clock.stop(at: now)
            status = previewExpired ? "系统提前结束了短时预览" : "预览已结束 · 点播放重新开始"
        }
        let position = clock.value(at: now) + appearance.calibration
        playbackDates.update(clock, at: now, date: Date(), calibration: appearance.calibration)
        guard let selection = document.selection(at: position) else { state = nil; return }
        revision += 1
        var nextLine = selection.next
        nextLine?.words = []
        let content = LyricActivity.ContentState(line: selection.line, next: nextLine,
            appearance: appearance, anchorDate: Date(), position: position, playing: clock.running,
            waiting: selection.waiting, repeated: document.lines.filter { $0.text == selection.line.text }.count > 1,
            revision: revision, source: preview ? .preview : .capture, complete: complete,
            playbackStart: playbackDates.start, artwork: preview ? nil : artworkData)
        state = content
        publish(content)
        guard clock.running else { return }
        let pages = NativeTypesetting.plan(content).pages.compactMap { $0.first?.token.start }
        let phrases = CompactLyrics.phrases(selection.line).map(\.start)
        let times = document.lines.flatMap { [$0.start, $0.vocalEnd] } + pages + phrases + [clock.duration]
        let next = times.filter { $0 > position + 0.01 }.min() ?? position + 0.75
        let delay = clamped(next - position, 0.02, 1)
        tick = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.refresh()
        }
    }

    private func publish(_ content: LyricActivity.ContentState) {
        guard let activity else {
            if content.complete == true { previewBackgroundTask.end() }
            return
        }
        let accepted = publisher.submit(content, to: activity) { [weak self] content, elapsed in
            guard let self else { return }
            if content.complete == true || !content.playing { previewBackgroundTask.end() }
            let now = ProcessInfo.processInfo.systemUptime
            if content.line.start != lastPublishedLineStart || now - lastPublicationLog >= 5 {
                lastPublishedLineStart = content.line.start
                lastPublicationLog = now
                diagnostics.record("island-update-submitted", ["position": String(content.position),
                    "lineStart": String(content.line.start), "revision": String(content.revision),
                    "updateMs": String(Int(elapsed * 1000)), "theme": content.appearance.theme])
            }
        }
        if !accepted { status = "这句歌词超过实时活动容量，需要分段适配" }
    }
}
