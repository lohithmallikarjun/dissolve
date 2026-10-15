import SwiftUI
import WidgetKit

@main
struct DissolveWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HabitWidgetsBundle().body
        TimeWidgetsBundle().body
        JournalWidgetsBundle().body
        StatsWidget()
        DiagnosticWidget()
        #if os(iOS)
        ControlsBundle().body
        CountdownLiveActivity()
        #endif
    }
}

struct HabitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SingleHabitWidget()
        TodayHabitsWidget()
        ConsistencyWidget()
        YearGridWidget()
    }
}

struct JournalWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JournalTodayWidget()
        OnThisDayWidget()
    }
}

struct TimeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        UpcomingCountdownsWidget()
        LifeWidget()
    }
}
