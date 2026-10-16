import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var session: LyricSession
    @State private var report: URL?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("灵动岛验证") {
                    Button("结束实时活动") { Task { await session.endIsland() } }
                    Text("预览与灵动岛使用同一份歌词、布局和填充。系统实际调度及流畅度仍需真机验证。")
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
