import Engine
import Foundation
import Observation

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case today, progress, journal, life
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .progress: String(localized: "Progress")
        case .journal: String(localized: "Journal")
        case .life: String(localized: "Life")
        }
    }

    var symbol: String {
        switch self {
        case .today: "checkmark.circle"
        case .progress: "square.grid.3x3.fill"
        case .journal: "book"
        case .life: "hourglass"
        }
    }
}

/// App-wide navigation state and the current day.
@MainActor @Observable
final class AppModel {
    var section: AppSection = .today
    /// Mac sidebar: a habit selected under "Habits".
    var selectedHabitID: UUID?
    /// The day shown on Today (editable: any past day).
    var day: LocalDate
    /// Set to open that day's journal entry (deep links, ⌘N).
    var journalDate: LocalDate?
    /// Mac sidebar: Templates selected.
    var showsTemplates = false
    /// CI screenshots: opens the countdown at this index on the Life screen.
    var countdownToOpen: Int?
    private(set) var today: LocalDate

    init() {
        let today = AppSettings.today()
        self.today = today
        day = today
        // CI screenshots: `-section:progress`. One token, so macOS doesn't treat the value as a file to open.
        if let tab = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-section:") })
            .flatMap({ AppSection(rawValue: String($0.dropFirst("-section:".count))) }) {
            section = tab
        }
        // CI screenshots: `-openCountdown:0` opens the first countdown.
        if let index = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-openCountdown:") })
            .flatMap({ Int($0.dropFirst("-openCountdown:".count)) }) {
            section = .life
            countdownToOpen = index
        }
        // CI screenshots: `-openJournal:-1` opens yesterday's entry.
        if let offset = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-openJournal:") })
            .flatMap({ Int($0.dropFirst("-openJournal:".count)) }) {
            section = .journal
            journalDate = today.adding(days: offset)
        }
    }

    /// Call when the app becomes active and at each day boundary.
    func refreshToday() {
        let new = AppSettings.today()
        guard new != today else { return }
        if day == today { day = new }
        today = new
    }

    func showDay(_ date: LocalDate) {
        day = min(date, today)
        section = .today
        selectedHabitID = nil
        showsTemplates = false
    }

    func openJournal(_ date: LocalDate? = nil) {
        section = .journal
        selectedHabitID = nil
        showsTemplates = false
        journalDate = min(date ?? today, today)
    }

    /// `dissolve://journal/today` or `dissolve://journal/2026-10-15` (widgets).
    func handle(_ url: URL) {
        guard url.scheme == "dissolve" else { return }
        switch url.host() {
        case "journal":
            let last = url.lastPathComponent
            openJournal(last == "today" || last == "/" ? today : LocalDate(last))
        case "today":
            showDay(today)
        case "progress":
            section = .progress
        case "life":
            section = .life
        default:
            break
        }
    }

    func moveDay(by days: Int) {
        day = min(day.adding(days: days), today)
    }

    /// Wakes at each day boundary to roll "today" over.
    func runDayClock() async {
        while !Task.isCancelled {
            let wait = AppSettings.nextDayBoundary().timeIntervalSinceNow + 1
            try? await Task.sleep(for: .seconds(max(wait, 60)))
            refreshToday()
        }
    }
}
