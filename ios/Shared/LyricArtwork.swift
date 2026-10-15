import SwiftUI
import InkFlowCore

struct LyricArtwork: View {
    let state: LyricActivity.ContentState
    let time: Double
    let systemTimedFill: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    private var ink: Color { LyricPalette.ink(state.appearance.theme) }

    var body: some View {
        let plan = NativeTypesetting.plan(state)
        let reduce = reducedMotion || dimmed
        let poses = StageMotion.poses(plan, at: time, waiting: state.waiting, reduced: reduce)
        let ambient = StageMotion.ambient(plan.style, at: time, reduced: reduce)
        GeometryReader { geometry in
            let factor = min(geometry.size.width / plan.width, geometry.size.height / plan.height)
            ZStack {
                ZStack(alignment: .topLeading) {
                    decorations(plan: plan, poses: poses, depth: ambient.depth)
                    ForEach(poses) { pose in
                        token(pose, style: plan.style)
                            .animation(nil, value: state.revision)
                            .scaleEffect(pose.scale)
                            .rotationEffect(.degrees(pose.rotation))
                            .opacity(systemTimedFill ? (state.waiting ? 0.7 : 1) : pose.opacity)
                            .blur(radius: pose.blur)
                            .position(x: pose.x, y: pose.y)
                            .animation(systemTimedFill && !reduce ? .linear(duration: 0.95) : nil,
                                       value: state.revision)
                            .zIndex(pose.hero ? 4 : 2)
                    }
                }
                .frame(width: plan.width, height: plan.height)
                .scaleEffect(ambient.scale)
                .rotationEffect(.degrees(ambient.rotation))
                .offset(x: ambient.x, y: ambient.y)
                .animation(systemTimedFill && !reduce ? .linear(duration: 0.95) : nil,
                           value: state.revision)
                if state.appearance.rows == 2, plan.style != .columns, let next = state.next {
                    Text(next.text)
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(ink.opacity(0.35))
                        .contentTransition(.identity)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .frame(width: plan.width - 100, height: 48)
                        .position(x: plan.width / 2, y: min(plan.height - 36, (poses.map { $0.y + $0.token.font * 0.75 }.max() ?? 100) + 38))
                        .id(next.id)
                        .transition(.opacity.combined(with: .offset(y: 16)))
                }
            }
            .frame(width: plan.width, height: plan.height)
            .scaleEffect(factor, anchor: .topLeading)
            .frame(width: plan.width * factor, height: plan.height * factor, alignment: .topLeading)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.line.text)
    }

    private func token(_ pose: TokenPose, style: LyricStyle) -> some View {
        let word = pose.token
        let paper = style == .collage && word.index % 3 == 0
        let font = Font(NativeTypesetting.font(size: word.font, weight: state.appearance.weight, style: style))
        let glyph = Text(word.token.text).font(font).fixedSize().contentTransition(.identity)
        let color: Color = paper ? .black : ink
        return ZStack {
            if paper {
                Rectangle().fill(ink.opacity(0.94))
                    .frame(width: word.width + word.font * 0.15, height: word.font * 1.22)
            }
            glyph.foregroundStyle(color.opacity(paper ? 0.34 : 0.2))
            // Keep the glow and filled glyph in the same mask pass.
            glyph.foregroundStyle(color)
                .shadow(color: paper ? .clear : ink.opacity(0.65 * min(1, state.appearance.glow)), radius: 8 * state.appearance.glow)
                .shadow(color: paper ? .clear : ink.opacity(0.28), radius: 20 * state.appearance.glow)
                .mask(alignment: .leading) {
                    WordFillMask(token: word, state: state, fraction: pose.fill,
                                 timed: systemTimedFill && state.appearance.timedMask && !dimmed)
                }
        }
        .frame(width: word.width, height: word.font * 1.5)
    }

    @ViewBuilder private func decorations(plan: StagePlan, poses: [TokenPose], depth: Double) -> some View {
        let left = poses.map { $0.x - $0.token.width / 2 }.min() ?? 60
        let right = poses.map { $0.x + $0.token.width / 2 }.max() ?? 680
        let top = poses.map { $0.y - $0.token.font * 0.7 }.min() ?? 50
        let bottom = poses.map { $0.y + $0.token.font * 0.7 }.max() ?? 130
        if plan.style == .cinema {
            ForEach(0..<2) { layer in
                Text(state.line.text)
                    .font(.system(size: plan.font * (layer == 0 ? 1.35 : 1.15), weight: .bold))
                    .foregroundStyle(ink.opacity(layer == 0 ? 0.11 : 0.055))
                    .contentTransition(.identity)
                    .fixedSize().blur(radius: layer == 0 ? 0.6 : 1.2)
                    .rotationEffect(.degrees(layer == 0 ? -4 : 2))
                    .scaleEffect(layer == 0 ? 1.04 + depth * 0.035 : 1)
                    .position(x: plan.width / 2 + depth * (layer == 0 ? -18 : 14), y: (top + bottom) / 2 + Double(layer + 1) * 8)
            }
            Rectangle().fill(ink.opacity(0.32))
                .frame(width: min(140, right - left) * (0.7 + depth * 0.2), height: 1.5)
                .rotationEffect(.degrees(-4)).position(x: left + 50, y: bottom + 2)
        } else if plan.style == .columns {
            Path { path in
                path.move(to: CGPoint(x: left - 10, y: top + 30))
                path.addLine(to: CGPoint(x: left - 10, y: top))
                path.addLine(to: CGPoint(x: left + 4, y: top))
                path.move(to: CGPoint(x: right + 10, y: bottom - 30))
                path.addLine(to: CGPoint(x: right + 10, y: bottom))
                path.addLine(to: CGPoint(x: right - 4, y: bottom))
            }.stroke(ink.opacity(0.24), lineWidth: 1)
            Circle().fill(ink.opacity(0.4)).frame(width: 3, height: 3)
                .position(x: left - 10, y: top + 40 + depth * 12)
        } else if plan.style == .collage {
            Rectangle().fill(ink.opacity(0.32))
                .frame(width: min(75, right - left) * (0.75 + depth * 0.2), height: 2)
                .rotationEffect(.degrees(-5)).position(x: left + 35, y: bottom - 4)
        }
    }
}

struct WordFillMask: View {
    let token: PlacedToken
    let state: LyricActivity.ContentState
    let fraction: Double
    let timed: Bool

    var body: some View {
        if timed && state.playing && !state.waiting {
            let total = max(0.01, token.token.widths.reduce(0, +))
            HStack(spacing: 0) {
                ForEach(Array(token.token.letters.enumerated()), id: \.offset) { index, letter in
                    let width = token.width * token.token.widths[index] / total
                    if letter.end > letter.start {
                        // 系统定时视图的遮罩实验；实际刷新率由 WidgetKit 决定。
                        ProgressView(timerInterval: state.date(for: letter.start)...state.date(for: letter.end), countsDown: false)
                            .labelsHidden().tint(.white)
                            .contentTransition(.identity)
                            .transition(.identity)
                            .animation(nil, value: state.revision)
                            .frame(width: width, height: 4)
                            .scaleEffect(x: 1, y: token.font / 2)
                            .frame(width: width, height: token.font * 1.5)
                            .clipped().background(.black)
                            .compositingGroup().luminanceToAlpha()
                    } else {
                        Rectangle().fill(state.position >= letter.start ? .white : .clear)
                            .frame(width: width)
                    }
                }
            }
        } else {
            Rectangle().frame(width: token.width * fraction, height: token.font * 1.5)
                .frame(width: token.width, alignment: .leading)
        }
    }
}
