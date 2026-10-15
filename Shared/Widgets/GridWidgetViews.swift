import Engine
import SwiftUI
import WidgetKit

/// Small: last 5 weeks + perfect-day streak.
struct GridSmallView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniGrid(snapshot: snapshot.overall.suffix(weeks: 5), color: .green, spacing: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(.orange).widgetAccentable()
                Text(snapshot.perfectStreak, format: .number)
                    .font(.title2.weight(.bold))
                    .numberStyle()
                Text("perfect days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Medium: 20-week overall grid.
struct GridMediumView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Consistency").font(.headline)
                Spacer()
                Label("\(snapshot.perfectStreak)", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .numberStyle()
            }
            MiniGrid(snapshot: snapshot.overall.suffix(weeks: 20), color: .green, spacing: 3)
        }
    }
}

/// Large: a full year, for all habits or one.
struct GridLargeView: View {
    let title: String
    let grid: GridSnapshot
    let color: Color
    let streak: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(streak)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .numberStyle()
            }
            MiniGrid(snapshot: grid.suffix(weeks: 20), color: color, spacing: 3)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text("Past year").font(.caption2).foregroundStyle(.secondary)
            MiniGrid(snapshot: grid, color: color, spacing: 1)
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                GridLegend(color: color, size: 8)
            }
        }
    }
}

/// Lock Screen rectangular: the last 7 days as dots.
struct GridDotsRectangularView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        let cells = snapshot.overall.lastDays(7)
        let dates = (0..<7).map { snapshot.today.adding(days: $0 - 6) }
        VStack(alignment: .leading, spacing: 4) {
            Label("\(snapshot.perfectStreak) perfect days", systemImage: "flame.fill")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(cells[i].level == 0 ? Color.primary.opacity(0.2) : Color.primary.opacity(0.25 + 0.75 * Double(cells[i].level) / 4))
                            .frame(width: 12, height: 12)
                            .widgetAccentable(cells[i].level > 0)
                        Text(Calendar.current.veryShortWeekdaySymbols[dates[i].weekday - 1])
                            .font(.system(size: 9))
                    }
                }
            }
        }
    }
}
