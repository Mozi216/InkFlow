import Foundation

public struct LyricServiceResult {
    public enum Availability: Equatable { case available, instrumental, unavailable }
    public let document: LyricDocument
    public let availability: Availability

    public init(yrc: String?, lrc: String?, pureMusic: Bool, duration: Double) {
        var parsed = LyricParser.parse(yrc: yrc, lrc: lrc, duration: duration)
        let placeholders = ["纯音乐，请欣赏", "纯音乐,请欣赏", "纯音乐，请欣赏。", "纯音乐", "暂无歌词"]
        parsed.lines.removeAll { placeholders.contains($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        document = parsed
        let hasLyrics = parsed.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        availability = hasLyrics ? .available : (pureMusic ? .instrumental : .unavailable)
    }
}
