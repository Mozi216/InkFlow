import SwiftUI
import ReplayKit

struct BroadcastConnectionView: View {
    private let extensionID = BroadcastPicker.extensionID

    var body: some View {
        HStack(spacing: 14) {
            if let extensionID {
                BroadcastPicker(extensionID: extensionID)
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                    .accessibilityLabel("打开系统音频连接面板")
            } else {
                Image(systemName: "exclamationmark.circle").font(.title2)
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(extensionID == nil ? "音频扩展未安装" : "打开系统音频连接面板").font(.subheadline.weight(.medium))
                Text(extensionID == nil
                     ? "请重新安装包含音频扩展的完整安装包。"
                     : "点白色圆形按钮，选择 InkFlow 并确认「开始直播」，再切到网易云播放。麦克风保持关闭。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    let extensionID: String

    static var extensionID: String? {
        if let folder = Bundle.main.builtInPlugInsURL,
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
           let url = files.first(where: { $0.lastPathComponent == "InkFlowBroadcast.appex" }) {
            return Bundle(url: url)?.bundleIdentifier
        }
        return nil
    }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        // ReplayKit lays out its button at creation. A zero frame can leave it untappable.
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        picker.preferredExtension = extensionID
        picker.showsMicrophoneButton = false
        picker.overrideUserInterfaceStyle = .light
        picker.tintColor = .black
        picker.backgroundColor = .clear
        return picker
    }
    func updateUIView(_ view: RPSystemBroadcastPickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RPSystemBroadcastPickerView,
                     context: Context) -> CGSize? {
        CGSize(width: 52, height: 52)
    }
}
