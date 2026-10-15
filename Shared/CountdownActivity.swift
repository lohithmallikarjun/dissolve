#if os(iOS)
import ActivityKit
import Foundation

/// A countdown's Live Activity on the Lock Screen and Dynamic Island in its final hours.
/// Started and ended on the device (no push notifications).
struct CountdownActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var target: Date
    }

    var countdownID: String
    var title: String
    var symbol: String
    var colorName: String
}

@MainActor
enum CountdownActivities {
    /// How close a timed countdown must be for its Live Activity to start automatically.
    static let window: TimeInterval = 8 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isRunning(_ id: UUID) -> Bool {
        Activity<CountdownActivityAttributes>.activities.contains { $0.attributes.countdownID == id.uuidString }
    }

    static func start(id: UUID, title: String, symbol: String, colorName: String, target: Date) {
        guard isAvailable, target > .now, !isRunning(id) else { return }
        let attributes = CountdownActivityAttributes(countdownID: id.uuidString, title: title, symbol: symbol, colorName: colorName)
        let content = ActivityContent(state: CountdownActivityAttributes.ContentState(target: target),
                                      staleDate: target.addingTimeInterval(60))
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    /// Starts activities for timed countdowns in their final hours; ends finished or removed ones.
    static func refresh(_ countdowns: [(id: UUID, title: String, symbol: String, colorName: String, target: Date, isTimed: Bool)]) {
        let now = Date.now
        for c in countdowns where c.isTimed && c.target > now && c.target.timeIntervalSince(now) <= window {
            start(id: c.id, title: c.title, symbol: c.symbol, colorName: c.colorName, target: c.target)
        }
        let live = Set(countdowns.filter { $0.isTimed && $0.target > now.addingTimeInterval(-3600) }.map { $0.id.uuidString })
        Task.detached { await endAll(except: live) }
    }

    /// Ends activities for countdowns that are finished, archived or deleted.
    nonisolated static func endAll(except live: Set<String>) async {
        for activity in Activity<CountdownActivityAttributes>.activities where !live.contains(activity.attributes.countdownID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#endif
