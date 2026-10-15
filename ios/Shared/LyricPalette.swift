import SwiftUI

enum LyricPalette {
    static func ink(_ theme: String) -> Color {
        switch theme {
        case "cream": return Color(red: 1, green: 0.91, blue: 0.75)
        case "rose": return Color(red: 1, green: 0.82, blue: 0.85)
        case "sage": return Color(red: 0.84, green: 0.93, blue: 0.85)
        default: return .white
        }
    }
}
