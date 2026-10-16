import Foundation

public enum LyricStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case flow, mv, columns, scatter, collage, cinema
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flow: return "雾光"
        case .mv: return "自动文字 MV"
        case .columns: return "纵书"
        case .scatter: return "散章"
        case .collage: return "拼贴"
        case .cinema: return "镜叙"
        }
    }

    public func resolved(for line: LyricLine, repeated: Bool) -> LyricStyle {
        guard self == .mv else { return self }
        if repeated { return .cinema }
        if line.text.contains(where: { "!！?？「」“”".contains($0) }) { return .collage }
        if Double(line.text.count) / max(0.001, line.end - line.start) > 5.5 { return .collage }
        if LyricLanguage.detect(line.text) == .latin { return .scatter }
        if line.end - line.start > 6.5 { return .columns }
        return .collage
    }
}

public enum LyricLanguage: String, Codable, Sendable {
    case latin, cjk, mixed
    public static func isCJK(_ value: Unicode.Scalar) -> Bool {
        (0x3040...0x30ff).contains(value.value) || (0x3400...0x9fff).contains(value.value)
            || (0x20000...0x3134f).contains(value.value) || (0xac00...0xd7af).contains(value.value)
    }
    public static func detect(_ text: String) -> LyricLanguage {
        let cjk = text.unicodeScalars.filter(isCJK).count
        let latin = text.unicodeScalars.filter { !isCJK($0) && CharacterSet.letters.contains($0) }.count
        if latin > cjk * 2 { return .latin }
        if cjk > latin * 2 { return .cjk }
        return .mixed
    }
}

public struct Appearance: Codable, Hashable, Sendable {
    public var style: LyricStyle = .mv
    public var rows = 2
    public var glow = 0.65
    public var weight = 0.55
    public var scale = 1.0
    public var theme = "white"
    public var calibration = 0.0
    public init() {}
    public mutating func normalize() {
        rows = rows == 1 ? 1 : 2
        glow = clamped(glow, 0, 2)
        weight = clamped(weight, 0.3, 0.8)
        scale = clamped(scale, 0.65, 1.2)
        calibration = clamped(calibration, -3, 3)
    }
}
