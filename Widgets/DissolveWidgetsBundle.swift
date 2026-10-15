import SwiftUI
import WidgetKit

@main
struct DissolveWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SingleHabitWidget()
        TodayHabitsWidget()
        ConsistencyWidget()
        YearGridWidget()
        JournalTodayWidget()
        OnThisDayWidget()
        DiagnosticWidget()
    }
}
