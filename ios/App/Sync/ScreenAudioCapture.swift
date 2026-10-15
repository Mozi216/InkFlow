import Foundation

#if !targetEnvironment(simulator)
import ScreenCaptureKit
import CoreMedia

@available(iOS 27.0, *)
final class ScreenAudioCapture: NSObject, AudioCaptureDriver, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    let recognition: AudioRecognition
    var onState: (@MainActor (String, Bool) -> Void)?
    var onEnd: (@MainActor () async -> Void)?
    @MainActor private var activeStream: SCStream?
    @MainActor private var generation = 0
    @MainActor private var choosing = false

    init(recognition: AudioRecognition) {
        self.recognition = recognition
        super.init()
    }

    @MainActor func start() {
        guard activeStream == nil, !choosing else { return }
        generation += 1
        choosing = true
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
        onState?("请选择整个屏幕，然后在网易云播放", false)
    }

    @MainActor func stop() async {
        generation += 1
        choosing = false
        let stream = activeStream
        activeStream = nil
        recognition.stop()
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        try? await stream?.stopCapture()
        onState?("未连接", false)
        await onEnd?()
    }

    @MainActor private func begin(_ filter: SCContentFilter) async {
        guard choosing else { return }
        choosing = false
        let requestGeneration = generation
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // 保留系统要求的视频输出，只接收低分辨率画面并立即丢弃。
        config.width = 32
        config.height = 32
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: recognition.queue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: recognition.queue)
            recognition.reset()
            try await stream.startCapture()
            guard requestGeneration == generation else { try? await stream.stopCapture(); return }
            activeStream = stream
            onState?("正在识别音乐", true)
        } catch {
            recognition.stop()
            SCContentSharingPicker.shared.remove(self)
            SCContentSharingPicker.shared.isActive = false
            onState?(error.localizedDescription, false)
            await onEnd?()
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await begin(filter) }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            guard activeStream == nil else { return }
            await stop()
        }
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in await stop(); onState?(error.localizedDescription, false) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        if outputType == .audio { recognition.consume(sampleBuffer) }
    }
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            guard stream === activeStream else { return }
            await stop()
            onState?(error.localizedDescription, false)
        }
    }
}
#endif
