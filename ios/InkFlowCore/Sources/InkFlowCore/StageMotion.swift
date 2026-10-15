import Foundation

public struct TokenPose: Sendable, Identifiable {
    public var token: PlacedToken
    public var x: Double
    public var y: Double
    public var rotation: Double
    public var scale: Double
    public var opacity: Double
    public var blur: Double
    public var fill: Double
    public var hero: Bool
    public var id: Int { token.index }
}

public struct AmbientPose: Codable, Sendable {
    public var x = 0.0
    public var y = 0.0
    public var rotation = 0.0
    public var scale = 1.0
    public var depth = 0.0
}

public enum StageMotion {
    private static func smooth(_ n: Double) -> Double { 1 - pow(1 - clamped(n), 3) }

    public static func page(in plan: StagePlan, at time: Double) -> Int {
        max(0, plan.pages.lastIndex { ($0.first?.token.start ?? .infinity) <= time } ?? 0)
    }

    public static func poses(_ plan: StagePlan, at time: Double, waiting: Bool = false,
                              reduced: Bool = false) -> [TokenPose] {
        guard !plan.pages.isEmpty else { return [] }
        let position = waiting ? plan.line.start : min(time, plan.line.end)
        let words = plan.pages[page(in: plan, at: position)]
        let active = words.firstIndex { position < $0.token.end } ?? max(0, words.count - 1)
        let phase = fillProgress(at: position, start: plan.line.start, end: plan.line.end)
        let enter = smooth((position - plan.line.start + 0.08) / 0.65)
        let motion = reduced ? 0.0 : 1.0
        return words.enumerated().map { i, word in
            let basicExtent = word.width / 2 + word.font * 0.04 + 16
            let basicX = clamped(word.x, basicExtent, plan.width - basicExtent)
            var x = basicX, y = word.y, rotation = 0.0, scale = 1.0, blur = 0.0
            let local = smooth((position - word.token.start + 0.22) / 0.22)
            let arrival = clamped((position - word.token.start + 0.24) / 0.24)
            let eased = reduced ? 1 : arrival * arrival * (3 - 2 * arrival)
            var opacity = 0.25 + 0.75 * eased
            switch plan.style {
            case .columns:
                var arrival = local
                if plan.language == .latin {
                    let row = words.filter { $0.row == word.row }
                    let left = words.map { $0.x - $0.width / 2 }.min() ?? 0
                    let rowLeft = row.map { $0.x - $0.width / 2 }.min() ?? 0
                    x = basicX - rowLeft + left
                    arrival = smooth((position - (row.first?.token.start ?? 0) + 0.22) / 0.22)
                } else {
                    x += sin(phase * .pi * 2 + Double(i) * 0.25) * 3 * motion
                    rotation = sin(word.x * 0.017) * 1.4 * motion
                }
                y += (1 - arrival) * 24 * motion
                opacity = 0.45 + 0.55 * arrival
                blur = (1 - arrival) * 2 * motion
            case .scatter:
                let arrival = smooth((position - word.token.start + 0.36) / 0.36)
                let tilt = Double((word.index * 7 + plan.line.text.utf16.count) % 11 - 5)
                x += (1 - arrival) * (i % 2 == 1 ? 4 : -4) * motion * (plan.language == .latin ? 0 : 1)
                y += (1 - arrival) * 18 * motion
                rotation = tilt * motion * (plan.language == .latin ? 0.45 : 1)
                opacity = 0.42 + 0.58 * arrival
                scale = 0.94 + 0.06 * arrival
                blur = (1 - arrival) * 1.2 * motion
            case .collage:
                rotation = (word.row % 2 == 1 ? 1 : -1) * (plan.language == .latin ? 2 : 4)
                let rowEnter = smooth((position - plan.line.start - Double(word.row) * 0.09 + 0.1) / 0.7)
                y += word.row % 2 == 1 ? 2 : -2
                x += (1 - rowEnter) * (word.row % 2 == 1 ? -26 : 26) * motion
                opacity = 0.65 + 0.35 * local
                rotation += sin(phase * .pi + Double(i) * 0.7) * 0.65 * motion
            case .cinema:
                x += (x - plan.width / 2) * phase * motion * 0.035 + (1 - enter) * 18 * motion
                y += (basicX - plan.width / 2) * -0.035 * motion
                rotation = -2 * motion
                scale = 0.98 + phase * motion * 0.04
                opacity = 0.6 + 0.4 * local
            default: break
            }
            if reduced { rotation = 0; blur = 0; scale = 1 }
            let radians = abs(rotation) * .pi / 180
            let ex = (word.width * cos(radians) + word.font * 1.5 * sin(radians)) * scale / 2 + 40
            let ey = (word.font * 1.5 * cos(radians) + word.width * sin(radians)) * scale / 2 + 40
            let fit = min(1, (plan.width - 48) / (ex * 2), (plan.height - 76) / (ey * 2))
            scale *= fit
            x = clamped(x, ex * fit, plan.width - ex * fit)
            y = clamped(y, ey * fit, plan.height - ey * fit)
            let filled = zip(word.token.letters, word.token.widths).reduce(0) {
                $0 + $1.1 * fillProgress(at: position, start: $1.0.start, end: $1.0.end)
            }
            let fill = clamped(filled / max(0.01, word.token.widths.reduce(0, +)))
            return TokenPose(token: word, x: x, y: y, rotation: rotation, scale: scale,
                             opacity: waiting ? 0.48 : opacity, blur: waiting ? 0 : blur,
                             fill: waiting ? 0 : fill, hero: i == active)
        }
    }

    public static func ambient(_ style: LyricStyle, at seconds: Double, reduced: Bool = false) -> AmbientPose {
        guard !reduced else { return AmbientPose() }
        let drift = sin(seconds * 0.48), lift = sin(seconds * 0.61 + 0.8)
        var p = AmbientPose()
        switch style {
        case .cinema:
            // Offset the lettering's base tilt, then swing through both directions.
            let swing = sin(seconds * 0.82) + sin(seconds * 1.64) * 0.18
            p.rotation = 2 + swing * 4.2
            p.x = sin(seconds * 0.82 + 0.7) * 7
            p.y = lift * 2
            p.scale += sin(seconds * 0.41) * 0.014
        case .columns:
            p.x = drift * 1.5; p.y = lift * 4; p.rotation = drift * 0.35
        case .collage:
            p.x = drift * 3; p.y = lift * 1.5
            p.rotation = (sin(seconds * 0.7) + sin(seconds * 1.4) * 0.15) * 0.8
        case .scatter:
            p.x = sin(seconds * 0.65) * 4; p.y = cos(seconds * 0.65) * 3
            p.rotation = lift * 0.6; p.scale += sin(seconds * 0.45) * 0.012
        case .flow:
            p.y = lift * 1.8; p.scale += sin(seconds * 0.38) * 0.004
        default: p.x = drift * 3; p.y = lift * 2; p.rotation = drift * 0.18
        }
        p.depth = sin(seconds * 0.42)
        return p
    }
}
