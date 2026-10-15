import Engine
import SwiftData
import SwiftUI

/// Mesh header with the rolling "% remaining", countdown tiles, and the weeks grid.
struct LifeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var profiles: [LifeProfile]
    @Query(filter: #Predicate<Countdown> { $0.archivedAt == nil }, sort: \Countdown.sortOrder) private var countdowns: [Countdown]

    @State private var editingProfile = false
    @State private var addingCountdown = false
    @State private var opened: Countdown?
    @Namespace private var zoom

    var body: some View {
        let profile = profiles.first
        let grid = profile?.grid(today: model.today)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LifeHeader(grid: grid) { editingProfile = true }

                countdownRow

                if let grid, let profile {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Life in weeks").font(.headline)
                            Spacer()
                            Text("Age \(grid.age)").font(.subheadline).foregroundStyle(.secondary).numberStyle()
                        }
                        LifeWeeksGrid(grid: grid, eras: profile.eras)
                        if !profile.eras.isEmpty { EraLegend(eras: profile.eras) }
                    }
                    .card()
                }
            }
            .padding(Metrics.margin)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Life")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Add", systemImage: "plus") {
                    Button("New Countdown", systemImage: "timer") { addingCountdown = true }
                    Button("Birth Date & Eras", systemImage: "person.crop.circle") { editingProfile = true }
                }
            }
        }
        .sheet(isPresented: $editingProfile) { LifeSettingsView(profile: profile) }
        .sheet(isPresented: $addingCountdown) {
            CountdownEditorView(countdown: nil, nextSortOrder: (countdowns.map(\.sortOrder).max() ?? -1) + 1)
        }
        #if os(iOS)
        .fullScreenCover(item: $opened) { countdown in
            CountdownDetailView(countdown: countdown)
                .navigationTransition(.zoom(sourceID: countdown.id, in: zoom))
        }
        #else
        .sheet(item: $opened) { CountdownDetailView(countdown: $0).frame(minWidth: 560, minHeight: 520) }
        #endif
        .task(id: model.today) { archiveFinishedCountdowns() }
        .onAppear {
            if let index = model.countdownToOpen, countdowns.indices.contains(index) {
                opened = countdowns[index]
                model.countdownToOpen = nil
            }
        }
    }

    @ViewBuilder
    private var countdownRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Countdowns").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(countdowns) { countdown in
                        Button { opened = countdown } label: {
                            CountdownTile(countdown: countdown)
                        }
                        .buttonStyle(.plain)
                        #if os(iOS)
                        .matchedTransitionSource(id: countdown.id, in: zoom)
                        #endif
                        .scrollTransition(.animated(.smooth), axis: .horizontal) { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.92).opacity(phase.isIdentity ? 1 : 0.7)
                        }
                    }
                    Button { addingCountdown = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.title2)
                            Text("New").font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 120, height: 150)
                        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    /// A one-off countdown is celebrated on its day, then archived the day after.
    private func archiveFinishedCountdowns() {
        var changed = false
        for countdown in countdowns where !countdown.repeatsYearly && !countdown.countUp {
            let targetDay = LocalDate(countdown.targetDate, dayEndsAtHour: 0)
            if targetDay < model.today {
                countdown.archivedAt = .now
                changed = true
            }
        }
        if changed { Persistence.save(context) }
    }
}

/// Mesh-gradient header: rolling % remaining and the weeks headline.
private struct LifeHeader: View {
    let grid: LifeGrid?
    let onSetUp: () -> Void
    @State private var shown: Double = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LivingMesh(colors: LivingMesh.life)
            VStack(alignment: .leading, spacing: 6) {
                if let grid {
                    Text("Life remaining")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(shown, format: .percent.precision(.fractionLength(1)))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: shown))
                        .foregroundStyle(.white)
                    Text("\(grid.weeksLived.formatted()) weeks lived · \(grid.weeksRemaining.formatted()) remain")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .numberStyle()
                } else {
                    Text("Your life in weeks").font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text("Add your birth date to see it.").foregroundStyle(.white.opacity(0.85))
                    Button("Set Birth Date", action: onSetUp)
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                        .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 24))
        .onAppear(perform: roll)
        .onChange(of: grid?.fractionRemaining) { roll() }
        .accessibilityElement(children: .combine)
    }

    private func roll() {
        guard let grid else { return }
        withAnimation(.smooth(duration: 1.1)) { shown = grid.fractionRemaining }
    }
}

private struct EraLegend: View {
    let eras: [LifeEra]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(eras, id: \.self) { era in
                    Label {
                        Text(era.name).font(.caption)
                    } icon: {
                        Circle().fill(HabitColor.named(era.colorName).color).frame(width: 8, height: 8)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { LifeView() }
        .environment(AppModel())
        .modelContainer(PreviewData.container)
}
