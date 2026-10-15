import Foundation

protocol AudioCaptureDriver: AnyObject {
    var onState: (@MainActor (String, Bool) -> Void)? { get set }
    var onEnd: (@MainActor () async -> Void)? { get set }
    @MainActor func start()
    @MainActor func stop() async
}

@MainActor final class SystemAudioCapture {
    let recognition = AudioRecognition()
    private var driver: AudioCaptureDriver?
    var onState: (@MainActor (String, Bool) -> Void)? {
        didSet { driver?.onState = onState }
    }
    var onEnd: (@MainActor () async -> Void)? {
        didSet { driver?.onEnd = onEnd }
    }

    var unavailableReason: String? {
        #if targetEnvironment(simulator)
        return "系统音频采集需要 iOS 27 真机；模拟器可测试歌词预览。"
        #else
        if #available(iOS 27.0, *) { return nil }
        return "当前系统可测试歌词效果与灵动岛；自动识别网易云音频需要 iOS 27。"
        #endif
    }

    init() {
        #if !targetEnvironment(simulator)
        if #available(iOS 27.0, *) {
            driver = ScreenAudioCapture(recognition: recognition)
        }
        #endif
    }

    func start() {
        guard let driver else {
            onState?(unavailableReason ?? "系统音频采集不可用", false)
            Task { await onEnd?() }
            return
        }
        driver.start()
    }

    func stop() async {
        if let driver { await driver.stop() }
        else {
            onState?("未连接", false)
            await onEnd?()
        }
    }
}
