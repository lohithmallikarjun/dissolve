import SwiftUI

/// A slowly drifting MeshGradient for the Life and Countdown headers.
/// Holds still with Reduce Motion.
struct LivingMesh: View {
    let colors: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            MeshGradient(width: 3, height: 3, points: Self.points(t), colors: colors, smoothsColors: true)
        }
    }

    private static func points(_ t: Float) -> [SIMD2<Float>] {
        func wobble(_ phase: Float, _ speed: Float = 0.35) -> Float { 0.5 + 0.18 * sin(t * speed + phase) }
        return [
            [0, 0], [wobble(0.0, 0.2), 0], [1, 0],
            [0, wobble(1.3)], [wobble(2.1), wobble(0.7)], [1, wobble(2.9)],
            [0, 1], [wobble(3.7, 0.25), 1], [1, 1],
        ]
    }

    /// Nine colours around one base colour.
    static func palette(_ base: Color) -> [Color] {
        [base.mix(with: .black, by: 0.25), base, base.mix(with: .pink, by: 0.35),
         base.mix(with: .blue, by: 0.3), base.mix(with: .white, by: 0.15), base.mix(with: .purple, by: 0.3),
         base.mix(with: .black, by: 0.35), base.mix(with: .orange, by: 0.25), base.mix(with: .black, by: 0.2)]
    }

    static let life: [Color] = [.indigo, .purple, .blue, .teal, .indigo, .pink, .blue, .purple, .orange]
}

#Preview {
    LivingMesh(colors: LivingMesh.life).frame(height: 240)
}
