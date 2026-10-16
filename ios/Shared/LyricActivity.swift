import ActivityKit
import InkFlowCore

struct LyricActivity: ActivityAttributes {
    typealias Source = LyricSource
    typealias ContentState = LyricSnapshot
    var song: String
}
