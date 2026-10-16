import Foundation

/// A scene is sampled from the published song position, never a view's render time.
public struct StageFrame {
    public static let cadence = 0.5
    public let poses: [TokenPose]
    public let ambient: AmbientPose
    public let page: Int

    public init(plan: StagePlan, state: LyricSnapshot, reduced: Bool = false) {
        let time = state.waiting ? plan.line.start : state.position
        page = StageMotion.page(in: plan, at: min(time, plan.line.end))
        poses = StageMotion.poses(plan, at: time, waiting: state.waiting, reduced: reduced)
        ambient = StageMotion.ambient(plan.style, at: time, reduced: reduced)
    }
}
