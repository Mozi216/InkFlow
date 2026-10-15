import SwiftUI
import ReplayKit

struct BroadcastConnectionView: View {
    var body: some View {
        HStack(spacing: 14) {
            BroadcastPicker().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("开始系统音频连接").font(.subheadline.weight(.medium))
                Text("点左侧按钮，在系统面板确认开始直播。麦克风保持关闭。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        // Read the embedded bundle ID, since personal signing may rewrite it.
        if let folder = Bundle.main.builtInPlugInsURL,
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
           let url = files.first(where: { $0.lastPathComponent == "InkFlowBroadcast.appex" }) {
            picker.preferredExtension = Bundle(url: url)?.bundleIdentifier
        }
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {}
}
