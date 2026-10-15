import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var session: LyricSession
    @State private var report: URL?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("灵动岛验证") {
                    Toggle("系统定时填充遮罩", isOn: $session.appearance.timedMask)
                    Button("结束实时活动") { Task { await session.endIsland() } }
                    Text("20 秒演示已在真机换句，但构建 3 的平滑度未通过。构建 4 调整填充与动画，并加入 iOS 26 音频连接；持续同步仍需真机验收。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("采集") {
                    LabeledContent("构建版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知")
                    LabeledContent("音频 RMS", value: String(format: "%.6f", session.level))
                    LabeledContent("状态", value: session.status)
                }
                Section {
                    Button("生成诊断记录") {
                        do { report = try session.diagnostics.export() } catch { self.error = error.localizedDescription }
                    }
                    if let report { ShareLink("导出记录", item: report) }
                    if let error { Text(error) }
                }
            }.navigationTitle("诊断")
        }
    }
}
