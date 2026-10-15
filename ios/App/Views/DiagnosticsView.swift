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
                    Text("此版本是原生验证工程。岛内连续填充、动画刷新和后台同步尚待真机验收；App 内预览不能替代这项测试。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("采集") {
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
