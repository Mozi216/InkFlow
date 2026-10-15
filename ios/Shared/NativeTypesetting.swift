import InkFlowCore
import NaturalLanguage
import UIKit

enum NativeTypesetting {
    private struct Key: Hashable {
        var line: LyricLine
        var appearance: Appearance
        var repeated: Bool
    }
    private static var plans: [Key: StagePlan] = [:]
    private static let lock = NSLock()
    static func font(size: Double, weight: Double, style: LyricStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: UIFont.Weight(rawValue: weight))
        if style == .columns, let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    static func plan(_ state: LyricActivity.ContentState) -> StagePlan {
        let key = Key(line: state.line, appearance: state.appearance, repeated: state.repeated)
        lock.lock()
        let cached = plans[key]
        lock.unlock()
        if let cached { return cached }
        let mode = state.appearance.style.resolved(for: state.line, repeated: state.repeated)
        let font = font(size: 100, weight: state.appearance.weight, style: mode)
        let rows = [.flow, .collage, .cinema].contains(mode) ? 1 : state.appearance.rows
        let result = StageLayout.make(line: state.line, fontLimit: 50 * state.appearance.scale,
            style: mode, repeated: state.repeated, rows: rows, segments: segments(state.line.text)) { text in
            (text as NSString).size(withAttributes: [.font: font]).width / 100
        }
        lock.lock()
        if plans.count >= 12 { plans.removeAll(keepingCapacity: true) }
        plans[key] = result
        lock.unlock()
        return result
    }

    static func segments(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var parts: [String] = []
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if cursor < range.lowerBound {
                let between = String(text[cursor..<range.lowerBound])
                if !parts.isEmpty && !between.contains(where: \.isWhitespace) { parts[parts.count - 1] += between }
                else { parts.append(between) }
            }
            parts.append(String(text[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex { parts.append(String(text[cursor...])) }
        return parts
    }
}
