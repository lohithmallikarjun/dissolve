import SwiftData
import SwiftUI

/// CI only: launched with `-widgetGallery`, renders every widget layout to PNGs in
/// Documents/widget-gallery so they can be screenshotted without a Home Screen.
enum WidgetGallery {
    @MainActor
    static func renderIfRequested(container: ModelContainer) async {
        guard ProcessInfo.processInfo.arguments.contains("-widgetGallery") else { return }
        #if os(iOS)
        let snapshot = DashboardLoader.load(context: container.mainContext)
        let journal = JournalSnapshot.load(context: container.mainContext)
        let first = snapshot.habits.first
        let water = snapshot.habits.first { $0.kind == .quantity } ?? first

        let items: [(String, CGSize, AnyView)] = [
            ("habit-small", CGSize(width: 170, height: 170), AnyView(SingleHabitSmallView(habit: water))),
            ("today-medium", CGSize(width: 364, height: 170), AnyView(ChecklistWidgetView(snapshot: snapshot, maxItems: 4))),
            ("today-large", CGSize(width: 364, height: 382),
             AnyView(ChecklistWidgetView(snapshot: snapshot, maxItems: 7, showsStrip: true))),
            ("grid-small", CGSize(width: 170, height: 170), AnyView(GridSmallView(snapshot: snapshot))),
            ("grid-medium", CGSize(width: 364, height: 170), AnyView(GridMediumView(snapshot: snapshot))),
            ("grid-large", CGSize(width: 364, height: 382),
             AnyView(GridLargeView(title: first?.name ?? "All habits", grid: first?.grid ?? snapshot.overall,
                                   color: first?.color ?? .green, streak: "\(first?.streak.count ?? 0) days"))),
            ("lock-rectangular-habit", CGSize(width: 172, height: 76), AnyView(HabitRectangularView(habit: snapshot.nextUndone))),
            ("lock-rectangular-dots", CGSize(width: 172, height: 76), AnyView(GridDotsRectangularView(snapshot: snapshot))),
            ("lock-circular", CGSize(width: 76, height: 76), AnyView(PercentCircularView(fraction: snapshot.todayFraction))),
            ("journal-small", CGSize(width: 170, height: 170), AnyView(JournalSmallView(snapshot: journal))),
            ("journal-memory-medium", CGSize(width: 364, height: 170), AnyView(JournalMemoryView(snapshot: journal))),
            ("lock-rectangular-journal", CGSize(width: 172, height: 76),
             AnyView(JournalStreakRectangularView(snapshot: journal))),
        ]

        let folder = URL.documentsDirectory.appending(path: "widget-gallery")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            for (name, size, view) in items {
                let isAccessory = name.hasPrefix("lock")
                let framed = view
                    .padding(isAccessory ? 4 : 16)
                    .frame(width: size.width, height: size.height)
                    .background(isAccessory ? Color.gray.opacity(0.35) : Color(.secondarySystemBackground),
                                in: .rect(cornerRadius: isAccessory ? 12 : 22, style: .continuous))
                    .padding(8)
                    .environment(\.colorScheme, scheme)
                    .tint(.green)
                let renderer = ImageRenderer(content: framed)
                renderer.scale = 3
                if let data = renderer.uiImage?.pngData() {
                    try? data.write(to: folder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        print("Dissolve: widget gallery written to \(folder.path)")
        #endif
    }
}
