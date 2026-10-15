import Engine
import SwiftData
import SwiftUI

extension Countdown {
    var color: Color { HabitColor.named(colorName).color }
}

/// The headline number and its caption: "41 days", "Today", "44 days since".
struct CountdownText {
    let countdown: Countdown
    let state: CountdownState

    var number: Int { state.days }

    var caption: String {
        if countdown.countUp { return state.days == 1 ? String(localized: "day since") : String(localized: "days since") }
        if state.hasArrived { return String(localized: "Today!") }
        if state.days == 0 { return countdown.isAllDay ? String(localized: "Today") : String(localized: "Less than a day") }
        return state.days == 1 ? String(localized: "day to go") : String(localized: "days to go")
    }

    /// "5 weeks, 6 days"
    var weeksAndDays: String {
        switch (state.weeks, state.extraDays) {
        case (0, let d): String(localized: "\(d) days")
        case (let w, 0): String(localized: "\(w) weeks")
        case (let w, let d): String(localized: "\(w) weeks, \(d) days")
        }
    }
}

/// A tile in the Life screen's horizontal row.
struct CountdownTile: View {
    let countdown: Countdown

    var body: some View {
        let state = countdown.state()
        let text = CountdownText(countdown: countdown, state: state)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: countdown.symbol).font(.headline)
                Spacer()
                if !countdown.countUp {
                    ProgressRing(progress: state.progress, color: .white, lineWidth: 3) { EmptyView() }
                        .frame(width: 22, height: 22)
                }
            }
            Spacer(minLength: 0)
            Text(text.number, format: .number)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(text.number)))
            Text(text.caption).font(.caption.weight(.semibold)).opacity(0.85)
            Text(countdown.title).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 150, height: 150, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [countdown.color, countdown.color.mix(with: .black, by: 0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let id = countdown.photoID.flatMap(UUID.init(uuidString:)), let image = ImageStore.thumbnail(id: id) {
                    Image(platformImage: image).resizable().scaledToFill().opacity(0.45)
                }
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(countdown.title), \(text.number) \(text.caption)")
    }
}

/// Full-screen live clock: D:H:M:S, weeks + days, progress ring, celebration on the day.
struct CountdownDetailView: View {
    let countdown: Countdown
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ZStack {
                LivingMesh(colors: LivingMesh.palette(countdown.color)).ignoresSafeArea()
                if let id = countdown.photoID.flatMap(UUID.init(uuidString:)), let image = ImageStore.image(id: id) {
                    Image(platformImage: image).resizable().scaledToFill().opacity(0.3).ignoresSafeArea()
                }
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    content(now: timeline.date)
                }
                .foregroundStyle(.white)
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") { editing = true }
                }
            }
            .sheet(isPresented: $editing) { CountdownEditorView(countdown: countdown, nextSortOrder: 0) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let state = countdown.state(now: now)
        let text = CountdownText(countdown: countdown, state: state)
        VStack(spacing: 20) {
            Image(systemName: countdown.symbol).font(.system(size: 44))
            Text(countdown.title).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text(state.occurrence.formatted(countdown.isAllDay ? .dateTime.weekday(.wide).month(.wide).day().year()
                                            : .dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                .font(.headline).opacity(0.85)

            if state.hasArrived && !countdown.countUp {
                Celebration()
                Button("Archive") {
                    countdown.archivedAt = .now
                    Persistence.save(context)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
            } else {
                clock(now: now, state: state)
                Text(text.weeksAndDays).font(.title3.weight(.semibold)).numberStyle().opacity(0.9)
                #if os(iOS)
                if !countdown.isAllDay && !countdown.countUp && !state.hasArrived {
                    Button(CountdownActivities.isRunning(countdown.id) ? "On Lock Screen ✓" : "Show on Lock Screen",
                           systemImage: "lock.iphone") {
                        CountdownActivities.start(id: countdown.id, title: countdown.title, symbol: countdown.symbol,
                                                  colorName: countdown.colorName, target: state.occurrence)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                #endif
                if !countdown.countUp {
                    ProgressRing(progress: state.progress, color: .white, lineWidth: 8) {
                        Text(state.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.headline).numberStyle()
                            .contentTransition(.numericText(value: state.progress))
                    }
                    .frame(width: 96, height: 96)
                }
            }
        }
        .frame(maxWidth: 520)
    }

    /// Days : hours : minutes : seconds, each rolling.
    private func clock(now: Date, state: CountdownState) -> some View {
        let seconds = max(0, Int(countdown.countUp ? now.timeIntervalSince(state.occurrence)
                                                   : state.occurrence.timeIntervalSince(now)))
        let parts = [(seconds / 86_400, String(localized: "days")), (seconds / 3600 % 24, String(localized: "hrs")),
                     (seconds / 60 % 60, String(localized: "min")), (seconds % 60, String(localized: "sec"))]
        return HStack(spacing: 14) {
            ForEach(parts.indices, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(parts[i].0, format: .number)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(parts[i].0)))
                        .animation(.snappy, value: parts[i].0)
                    Text(parts[i].1).font(.caption.weight(.semibold)).opacity(0.8)
                }
                .frame(minWidth: 64)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short burst when the day arrives (under 1.2 s), then a gentle glow.
private struct Celebration: View {
    @State private var trigger = 0

    var body: some View {
        Image(systemName: "party.popper.fill")
            .font(.system(size: 72))
            .keyframeAnimator(initialValue: Burst(), trigger: trigger) { view, value in
                view.scaleEffect(value.scale).rotationEffect(.degrees(value.angle))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.4, duration: 0.35)
                    SpringKeyframe(0.9, duration: 0.3)
                    SpringKeyframe(1.0, duration: 0.4)
                }
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-14, duration: 0.25)
                    CubicKeyframe(10, duration: 0.3)
                    CubicKeyframe(0, duration: 0.4)
                }
            }
            .symbolEffect(.bounce, value: trigger)
            .sensoryFeedback(.success, trigger: trigger)
            .onAppear { trigger += 1 }
        Text("It's here!").font(.title.weight(.bold))
    }

    struct Burst {
        var scale = 0.4
        var angle = 0.0
    }
}
