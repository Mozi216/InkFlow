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
                    Text("已验证真实灵动岛显示。20 秒演示使用短时后台任务，系统可以提前结束；持续换句与网易云同步尚未通过真机验收。")
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
