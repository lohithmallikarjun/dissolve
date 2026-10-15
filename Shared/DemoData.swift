import Engine
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Plausible sample habits with months of history, for previews, widget placeholders and CI screenshots.
/// Deterministic, so screenshots are stable.
enum DemoData {
    /// Seeds the real store when launched with `-demoData` and the store has no habits yet.
    @MainActor
    static func seedIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoData") else { return }
        let count = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        guard count == 0 else { return }
        let today = AppSettings.today()
        seed(into: context, today: today)
        seedJournal(into: context, today: today, withPhotos: true)
        try? context.save()
    }

    static let journalLines = [
        "Long walk by the lake before work — the light was unreal.",
        "Finally finished the chapter I'd been stuck on for a week.",
        "Cooked dinner for friends; the dal turned out perfect.",
        "Slow morning, lots of tea, and a good conversation with Mum.",
        "Ran 5 km without stopping for the first time.",
        "Quiet day. Tidied the desk and read in the park.",
        "Tough meeting, but I said what I needed to say.",
        "Watched the sunset from the terrace with a coffee.",
    ]

    /// About two months of entries, plus one from a year ago (for "On this day").
    /// Photos are generated gradients, only when asked (they need the image renderer).
    @MainActor
    static func seedJournal(into context: ModelContext, today: LocalDate, withPhotos: Bool) {
        var rng = SplitMix64(seed: 7)
        let template = JournalStore.defaultTemplate(in: context)
        var days = (1...60).map { today.adding(days: -$0) }.filter { _ in rng.chance(0.8) }
        days.append(today.adding(days: -365))
        for (index, date) in days.enumerated() {
            let entry = JournalEntry(date: date, templateID: template.id)
            context.insert(entry)
            entry.mood = Int(rng.next(in: 2.5...5.99))
            for t in template.orderedBlocks {
                let block = EntryBlock(kind: t.kind, order: t.order, promptText: t.promptText, placeholder: t.placeholder)
                context.insert(block)
                block.entry = entry
                switch t.kind {
                case .prompt: block.text = journalLines[index % journalLines.count]
                case .text: block.text = index % 3 == 0 ? "Grateful for small things. Tomorrow: early night." : ""
                case .image:
                    if withPhotos, index % 4 == 0 || date == today.adding(days: -365),
                       let saved = demoPhoto(seed: index) {
                        context.insert(Photo(id: saved.id, width: saved.width, height: saved.height))
                        block.photoIDs = [saved.id.uuidString]
                    }
                default: break
                }
            }
            entry.recountWords()
        }
    }

    @MainActor
    private static func demoPhoto(seed: Int) -> ImageStore.Saved? {
        let palettes: [[Color]] = [[.orange, .pink, .purple], [.teal, .blue, .indigo], [.yellow, .orange, .red],
                                   [.mint, .green, .teal]]
        let colors = palettes[seed % palettes.count]
        let view = ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.35)).frame(width: 260).offset(x: 180, y: -120)
            Rectangle().fill(.black.opacity(0.18)).frame(height: 220).offset(y: 230)
        }
        .frame(width: 1200, height: 900)
        let renderer = ImageRenderer(content: view)
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return try? ImageStore.save(imageData: data as Data)
    }

    static func seed(into context: ModelContext, today: LocalDate, days: Int = 300) {
        var rng = SplitMix64(seed: 42)
        let start = today.adding(days: -days)

        func make(_ name: String, _ symbol: String, _ color: HabitColor, _ kind: HabitKind, target: Double = 1,
                  unit: String = "", rule: ScheduleRule, order: Int) -> Habit {
            let habit = Habit(name: name, symbol: symbol, colorName: color.rawValue, kind: kind, target: target,
                              unit: unit, sortOrder: order, startDate: start)
            context.insert(habit)
            let schedule = HabitSchedule(rule: rule, effectiveFrom: start)
            context.insert(schedule)
            schedule.habit = habit
            return habit
        }

        func log(_ habit: Habit, _ date: LocalDate, value: Double = 0, skipped: Bool = false, note: String = "") {
            let log = HabitLog(habit: habit, date: date)
            log.value = value
            log.isSkipped = skipped
            log.note = note
            context.insert(log)
            log.habit = habit
        }

        let meditate = make("Meditate", "brain.head.profile", .mint, .binary, rule: .daily, order: 0)
        let water = make("Water", "drop.fill", .blue, .quantity, target: 8, unit: "glasses", rule: .daily, order: 1)
        let gym = make("Gym", "dumbbell.fill", .orange, .binary, rule: .timesPerWeek(3), order: 2)
        let read = make("Read", "book.fill", .indigo, .timed, target: 20, rule: .weekdays([2, 3, 4, 5, 6]), order: 3)
        let coffee = make("Coffee", "cup.and.saucer.fill", .brown, .limit, target: 2, unit: "cups", rule: .daily, order: 4)

        for offset in 0..<days {
            let date = start.adding(days: offset)
            // Consistency improves over time.
            let skill = 0.55 + 0.4 * Double(offset) / Double(days)
            if rng.chance(0.03) {
                log(meditate, date, skipped: true)
            } else if rng.chance(skill) {
                log(meditate, date, value: 1, note: offset % 37 == 0 ? "Felt calm afterwards." : "")
            }
            log(water, date, value: Double(Int(rng.next(in: 3...9) * skill + 2)))
            if [2, 4, 6].contains(date.weekday), rng.chance(skill + 0.1) { log(gym, date, value: 1) }
            if (2...6).contains(date.weekday), rng.chance(skill) { log(read, date, value: Double(Int(rng.next(in: 10...35)))) }
            log(coffee, date, value: Double(Int(rng.next(in: 0...3.4))))
        }

        // Today: partly done.
        for habit in [meditate, water, gym, read, coffee] {
            if let existing = habit.logs.first(where: { $0.date == today.description }) { context.delete(existing) }
        }
        log(meditate, today, value: 1)
        log(water, today, value: 5)
        log(coffee, today, value: 1)
    }
}

/// Small deterministic RNG.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
}

/// In-memory seeded store for SwiftUI previews and widget placeholders.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = SharedModelContainer.inMemory()
        DemoData.seed(into: container.mainContext, today: AppSettings.today(), days: 200)
        DemoData.seedJournal(into: container.mainContext, today: AppSettings.today(), withPhotos: false)
        try? container.mainContext.save()
        return container
    }()
}
