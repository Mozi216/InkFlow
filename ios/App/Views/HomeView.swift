import SwiftUI
import InkFlowCore

struct HomeView: View {
    @ObservedObject var session: LyricSession
    @State private var showingDiagnostics = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.title).font(.system(size: 34, weight: .semibold, design: .rounded))
                        HStack(spacing: 8) {
                            Circle().fill(.white.opacity(session.capturing ? 1 : 0.3)).frame(width: 5, height: 5)
                            Text(session.status).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    artwork
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                if session.capturing { await session.stopCapture() }
                                else { await session.beginCapture() }
                            }
                        } label: {
                            Label(session.capturing ? "停止连接" : "连接网易云", systemImage: session.capturing ? "stop.fill" : "waveform")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        .disabled(session.connecting || session.captureUnavailableReason != nil)
                        Text(session.captureUnavailableReason ?? "选择整个屏幕以识别播放音频。画面立即丢弃，不保存录音。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !session.candidates.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(session.candidates) { song in
                                Button { Task { await session.select(song) } } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(song.title)
                                        Text(song.artist).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                }
                                Divider()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("文字演出").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(LyricStyle.allCases) { style in
                                Button { session.appearance.style = style } label: {
                                    HStack {
                                        Text(style.title).font(.subheadline.weight(.medium))
                                        Spacer()
                                        if session.appearance.style == style { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                                    }.padding(16)
                                        .background(.white.opacity(session.appearance.style == style ? 0.16 : 0.055), in: RoundedRectangle(cornerRadius: 18))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    controls
                    HStack {
                        Button("预览效果") { Task { await session.startPreview() } }
                        Spacer()
                        Button("灵动岛测试") { Task { await session.startIsland() } }.disabled(session.state == nil)
                    }.font(.subheadline)
                }.padding(24)
            }
            .background(Color(white: 0.035))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingDiagnostics = true } label: { Image(systemName: "ellipsis") }
                }
            }
            .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(session: session) }
        }
    }

    private var artwork: some View {
        VStack(spacing: 0) {
            if let state = session.state {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !state.playing)) { context in
                    LyricArtwork(state: state, time: state.time(at: context.date), systemTimedFill: false)
                        .id(state.line.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)),
                                                removal: .opacity.combined(with: .offset(y: -12))))
                        .animation(.easeOut(duration: 0.44), value: state.line.id)
                }.frame(height: 180)
            } else {
                Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).frame(height: 180)
            }
            if session.preview {
                HStack {
                    Button { session.togglePreviewPlayback() } label: {
                        Image(systemName: session.state?.playing == true ? "pause.fill" : "play.fill")
                    }
                    Slider(value: Binding(get: { session.state?.position ?? 0 }, set: session.seekPreview), in: 0...40)
                }.padding(.horizontal, 20).padding(.bottom, 16)
            }
        }.background(.black, in: RoundedRectangle(cornerRadius: 32))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("歌词行数", selection: $session.appearance.rows) {
                Text("一行").tag(1); Text("两行").tag(2)
            }.pickerStyle(.segmented)
            HStack(spacing: 14) {
                ForEach(["white", "cream", "rose", "sage"], id: \.self) { theme in
                    Button { session.appearance.theme = theme } label: {
                        Circle().fill(themeColor(theme)).frame(width: 28, height: 28)
                            .padding(5)
                            .overlay(Circle().strokeBorder(.white.opacity(session.appearance.theme == theme ? 0.8 : 0), lineWidth: 1))
                    }.accessibilityLabel(theme)
                }
                Spacer()
            }
            slider("辉光", value: $session.appearance.glow, range: 0...2)
            slider("字重", value: $session.appearance.weight, range: 0.3...0.8)
            slider("大小", value: $session.appearance.scale, range: 0.65...1.2)
            VStack(alignment: .leading) {
                HStack {
                    Text("同步校准")
                    Spacer()
                    Text("\(Int(session.appearance.calibration * 1000)) ms").monospacedDigit().foregroundStyle(.secondary)
                }.font(.subheadline)
                Slider(value: $session.appearance.calibration, in: -3...3, step: 0.05)
            }
        }.padding(20).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 24) { Text(title).font(.subheadline); Slider(value: value, in: range) }
    }
    private func themeColor(_ theme: String) -> Color {
        switch theme {
        case "cream": return Color(red: 1, green: 0.91, blue: 0.75)
        case "rose": return Color(red: 1, green: 0.82, blue: 0.85)
        case "sage": return Color(red: 0.84, green: 0.93, blue: 0.85)
        default: return .white
        }
    }
}
