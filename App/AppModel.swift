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
    private(set) var today: LocalDate

    init() {
        let today = AppSettings.today()
        self.today = today
        day = today
        if let tab = ProcessInfo.processInfo.arguments.firstIndex(of: "-section")
            .flatMap({ ProcessInfo.processInfo.arguments.dropFirst($0 + 1).first })
            .flatMap(AppSection.init(rawValue:)) {
            section = tab
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
