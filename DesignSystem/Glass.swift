import SwiftUI

/// Floating glass "Journal today" pill on Today. Morphs into a ✓ + streak bubble once written.
struct JournalPill: View {
    let written: Bool
    let streak: Int
    let action: () -> Void
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: action) {
                    Label(written ? "Journaled" : "Journal today",
                          systemImage: written ? "checkmark.circle.fill" : "square.and.pencil")
                        .font(.headline)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(written ? .green.opacity(0.35) : .clear).interactive(), in: .capsule)
                .glassEffectID("pill", in: glass)

                if written && streak > 1 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .numberStyle()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("streak", in: glass)
                        .accessibilityLabel("\(streak)-day journal streak")
                }
            }
        }
        .animation(.smooth, value: written)
        .accessibilityHint(written ? "Opens today's entry" : "Writes today's journal entry")
    }
}

/// Segmented control drawn as morphing glass capsules (the grid range picker).
struct GlassSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    let selected = option.value == selection
                    Button {
                        withAnimation(.smooth) { selection = option.value }
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(.green.opacity(0.3)).interactive() : .regular.interactive(),
                                 in: .capsule)
                    .glassEffectID(i, in: glass)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// A short celebration when the day reaches 100 % (≈1.1 s). Crossfade only with Reduce Motion.
struct DayCompleteCelebration: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                    .font(.system(size: i.isMultiple(of: 2) ? 22 : 8))
                    .foregroundStyle([Color.green, .mint, .yellow, .orange, .teal][i % 5])
                    .keyframeAnimator(initialValue: Burst(), trigger: trigger) { view, value in
                        view.offset(x: cos(Double(i) / 10 * 2 * .pi) * value.distance,
                                    y: sin(Double(i) / 10 * 2 * .pi) * value.distance)
                            .opacity(value.opacity)
                            .scaleEffect(value.scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.distance) {
                            SpringKeyframe(reduceMotion ? 0 : 120, duration: 0.6, spring: .snappy)
                            LinearKeyframe(reduceMotion ? 0 : 140, duration: 0.5)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.15)
                            LinearKeyframe(1, duration: 0.5)
                            LinearKeyframe(0, duration: 0.45)
                        }
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1.2, duration: 0.4)
                            LinearKeyframe(0.6, duration: 0.7)
                        }
                    }
            }
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .keyframeAnimator(initialValue: Burst(), trigger: trigger) { view, value in
                    view.scaleEffect(reduceMotion ? 1 : value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        SpringKeyframe(1.25, duration: 0.35)
                        SpringKeyframe(1.0, duration: 0.3)
                        LinearKeyframe(1.0, duration: 0.45)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(1, duration: 0.2)
                        LinearKeyframe(1, duration: 0.5)
                        LinearKeyframe(0, duration: 0.4)
                    }
                }
        }
        .allowsHitTesting(false)
        .sensoryFeedback(.success, trigger: trigger)
        .accessibilityHidden(true)
    }

    struct Burst {
        var distance = 0.0
        var opacity = 0.0
        var scale = 0.3
    }
}
