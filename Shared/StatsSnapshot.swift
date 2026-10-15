import Engine
import Foundation
import SwiftData
import SwiftUI

/// Everything the Statistics screen and stats widgets show. Built from the engine.
struct StatsSnapshot: Sendable {
    struct Point: Identifiable, Sendable {
        var id: Int { day.dayNumber }
        let day: LocalDate
        let value: Double
        var date: Date { day.startDate() }
    }

    struct Bucket: Identifiable, Sendable {
        var id: Int { start.dayNumber }
        let start: LocalDate
        let label: String
        let tally: Tally
    }

    struct HabitStat: Identifiable, Sendable {
        let id: UUID
        let name: String
        let colorName: String
        let strength: Double
        let current: Streak
        let best: Streak
        var color: Color { HabitColor.named(colorName).color }
    }

    struct WeekdayStat: Identifiable, Sendable {
        var id: Int { weekday }
        let weekday: Int
        let symbol: String
        let tally: Tally
    }

    struct MoodPoint: Identifiable, Sendable {
        var id: Int { start.dayNumber }
        let start: LocalDate
        let mood: Double
        var date: Date { start.startDate() }
    }

    let today: LocalDate
    /// Daily overall strength for the last 365 days.
    let strength: [Point]
    let habits: [HabitStat]
    let weekly: [Bucket]
    let monthly: [Bucket]
    let weekdays: [WeekdayStat]
    let journalMonthly: [Bucket]
    let mood: [MoodPoint]
    let journalStreak: Int
    let journalDays30: Int
    let averageWords30: Int?
    let thisWeek: Tally
    let lastWeek: Tally
    /// Completion fraction per day this week and last week (nil = nothing due / future).
    let thisWeekDays: [Double?]
    let lastWeekDays: [Double?]

    var hasHabits: Bool { !habits.isEmpty }

    static func compute(habits: [Habit], entries: [JournalEntry], today: LocalDate) -> StatsSnapshot {
        let firstWeekday = AppSettings.firstWeekday
        let engines = habits.map { $0.engine(today: today) }
        let yearAgo = today.adding(days: -364)
        let series = Stats.overallStrength(engines, from: yearAgo, to: today)
        let strength = series.enumerated().map { Point(day: yearAgo.adding(days: $0.offset), value: $0.element) }

        let habitStats = zip(habits, engines).map { habit, engine in
            HabitStat(id: habit.id, name: habit.name, colorName: habit.colorName, strength: engine.strength,
                      current: engine.currentStreak, best: engine.bestStreak)
        }

        let weekly = Stats.weekly(engines, weeks: 12, today: today, firstWeekday: firstWeekday).map {
            Bucket(start: $0.start, label: $0.start.formatted(.dateTime.day().month(.abbreviated)), tally: $0.tally)
        }
        let monthly = Stats.monthly(engines, months: 12, today: today).map {
            Bucket(start: $0.month, label: $0.month.formatted(.dateTime.month(.abbreviated)), tally: $0.tally)
        }

        let byWeekday = Stats.byWeekday(engines, from: today.adding(days: -90), to: today)
        let symbols = Calendar.current.shortWeekdaySymbols
        let weekdays = (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }.map {
            WeekdayStat(weekday: $0, symbol: symbols[$0 - 1], tally: byWeekday[$0] ?? Tally())
        }

        let written = entries.filter { $0.wordCount > 0 || !$0.photoIDs.isEmpty }
        let writtenDates = Set(written.compactMap(\.localDate))
        let journalMonthly = Stats.entriesPerMonth(writtenDates, months: 12, today: today).map {
            Bucket(start: $0.month, label: $0.month.formatted(.dateTime.month(.abbreviated)), tally: Tally(done: $0.count, due: 0))
        }
        var moods: [LocalDate: Int] = [:]
        for entry in entries { if let d = entry.localDate, entry.mood > 0 { moods[d] = entry.mood } }
        let mood = Stats.moodByWeek(moods, weeks: 12, today: today, firstWeekday: firstWeekday)
            .compactMap { w in w.mood.map { MoodPoint(start: w.start, mood: $0) } }
        let recent = written.filter { ($0.localDate ?? today) > today.adding(days: -30) }
        let averageWords = recent.isEmpty ? nil : recent.map(\.wordCount).reduce(0, +) / recent.count

        let thisWeekStart = today.startOfWeek(firstWeekday: firstWeekday)
        let lastWeekStart = thisWeekStart.adding(days: -7)
        func days(from start: LocalDate) -> [Double?] {
            (0..<7).map { offset in
                let day = start.adding(days: offset)
                return day > today ? nil : Overall.fraction(on: day, engines: engines)
            }
        }

        return StatsSnapshot(
            today: today, strength: strength, habits: habitStats, weekly: weekly, monthly: monthly,
            weekdays: weekdays, journalMonthly: journalMonthly, mood: mood,
            journalStreak: JournalStats.streak(entryDates: writtenDates, today: today),
            journalDays30: recent.count, averageWords30: averageWords,
            thisWeek: Stats.tally(engines, from: thisWeekStart, to: today),
            lastWeek: Stats.tally(engines, from: lastWeekStart, to: thisWeekStart.adding(days: -1)),
            thisWeekDays: days(from: thisWeekStart), lastWeekDays: days(from: lastWeekStart))
    }

    static func load(context: ModelContext, today: LocalDate = AppSettings.today()) -> StatsSnapshot {
        let habits = (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.archivedAt == nil },
                                                                 sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        return compute(habits: habits, entries: entries, today: today)
    }

    static func load() -> StatsSnapshot? {
        guard let container = try? SharedModelContainer.appGroup() else { return nil }
        return load(context: ModelContext(container))
    }

    var currentStrength: Double { strength.last?.value ?? 0 }

    func strength(daysAgo: Int) -> Double {
        let index = strength.count - 1 - daysAgo
        return strength.indices.contains(index) ? strength[index].value : 0
    }
}

/// One plain sentence per card, Apple Health style. Patterns, not causes.
enum StatsInsights {
    static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }

    static func strength(_ s: StatsSnapshot, days: Int) -> String {
        guard s.hasHabits else { return String(localized: "Add a habit to start building strength.") }
        let now = s.currentStrength
        let delta = Int(((now - s.strength(daysAgo: days)) * 100).rounded())
        let period = days >= 365 ? String(localized: "this year") : String(localized: "in the last \(days) days")
        if abs(delta) < 2 { return String(localized: "Overall strength is \(percent(now)), holding steady \(period).") }
        return delta > 0
            ? String(localized: "Overall strength is \(percent(now)), up \(delta) points \(period).")
            : String(localized: "Overall strength is \(percent(now)), down \(-delta) points \(period).")
    }

    static func completion(_ s: StatsSnapshot, monthly: Bool) -> String {
        let buckets = (monthly ? s.monthly : s.weekly).filter { $0.tally.due > 0 }
        guard let current = buckets.last, let rate = current.tally.rate else {
            return String(localized: "Insights appear after a few days of check-ins.")
        }
        if monthly {
            let earlier = buckets.dropLast().reversed()
            if let better = earlier.first(where: { ($0.tally.rate ?? 0) > rate }) {
                if better.start == earlier.first?.start {
                    return String(localized: "\(percent(rate)) of scheduled habits done this month, below last month's \(percent(better.tally.rate ?? 0)).")
                }
                return String(localized: "\(percent(rate)) of scheduled habits done this month — your best since \(better.label).")
            }
            return earlier.isEmpty
                ? String(localized: "\(percent(rate)) of scheduled habits done this month.")
                : String(localized: "\(percent(rate)) of scheduled habits done this month — your best month yet.")
        }
        if let previous = buckets.dropLast().last?.tally.rate {
            let word = rate >= previous ? String(localized: "up from") : String(localized: "down from")
            return String(localized: "\(percent(rate)) of scheduled habits done this week, \(word) \(percent(previous)) last week.")
        }
        return String(localized: "\(percent(rate)) of scheduled habits done this week.")
    }

    static func streaks(_ s: StatsSnapshot) -> String {
        guard let top = s.habits.max(by: { $0.current.count < $1.current.count }), top.current.count > 0 else {
            return String(localized: "No active streaks yet — check something off today.")
        }
        let unit = top.current.unit == .weeks ? String(localized: "weeks") : String(localized: "days")
        if top.current.count >= top.best.count {
            return String(localized: "\(top.name) is on its longest streak ever: \(top.current.count) \(unit).")
        }
        return String(localized: "Your longest active streak is \(top.name): \(top.current.count) \(unit).")
    }

    static func weekdays(_ s: StatsSnapshot) -> String {
        let rated = s.weekdays.compactMap { w in w.tally.rate.map { (w, $0) } }.filter { $0.0.tally.due >= 3 }
        guard let best = rated.max(by: { $0.1 < $1.1 }), let worst = rated.min(by: { $0.1 < $1.1 }),
              best.1 - worst.1 >= 0.05 else {
            return rated.isEmpty ? String(localized: "Weekday patterns appear after a couple of weeks.")
                                 : String(localized: "You're about equally consistent every day of the week.")
        }
        let bestDay = Calendar.current.weekdaySymbols[best.0.weekday - 1]
        let worstDay = Calendar.current.weekdaySymbols[worst.0.weekday - 1]
        return String(localized: "\(bestDay)s are your strongest day (\(percent(best.1))); \(worstDay)s slip to \(percent(worst.1)).")
    }

    static func journal(_ s: StatsSnapshot) -> String {
        guard s.journalDays30 > 0 else { return String(localized: "Write a few lines tonight to start your journal stats.") }
        if let words = s.averageWords30 {
            return String(localized: "You journaled \(s.journalDays30) of the last 30 days, averaging \(words) words.")
        }
        return String(localized: "You journaled \(s.journalDays30) of the last 30 days.")
    }
}
