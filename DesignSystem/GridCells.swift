import Engine
import SwiftUI
import WidgetKit

/// A precomputed grid: layout plus a cell for every visible day. Cheap to pass to widgets.
struct GridSnapshot: Sendable {
    let layout: GridLayout
    /// `[column][row]`; nil after today.
    let cells: [[GridCell?]]

    init(layout: GridLayout, cell: (LocalDate) -> GridCell) {
        self.layout = layout
        cells = (0..<layout.weeks).map { column in
            (0..<7).map { row in layout.date(column: column, row: row).map(cell) }
        }
    }

    static func overall(engines: [HabitEngine], today: LocalDate, weeks: Int) -> GridSnapshot {
        GridSnapshot(layout: GridLayout(endingAt: today, weeks: weeks, firstWeekday: AppSettings.firstWeekday)) {
            Overall.cell(on: $0, engines: engines)
        }
    }

    static func habit(_ engine: HabitEngine, weeks: Int) -> GridSnapshot {
        GridSnapshot(layout: GridLayout(endingAt: engine.today, weeks: weeks, firstWeekday: engine.firstWeekday)) {
            engine.cell(on: $0)
        }
    }

    /// The last `count` days' cells, oldest first.
    func lastDays(_ count: Int) -> [GridCell] {
        let dates = layout.allDates.suffix(count)
        return dates.map { date in
            let offset = layout.start.days(to: date)
            return cells[offset / 7][offset % 7] ?? .empty
        }
    }
}

/// One day's square. Levels: 0 system fill, then the colour at 30 / 50 / 75 / 100 %.
struct GridCellView: View {
    let cell: GridCell?
    let color: Color
    var cornerRadius: CGFloat = 3
    var isToday = false

    static let opacities: [Double] = [0, 0.3, 0.5, 0.75, 1]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let cell {
            if cell.isSkipped {
                shape.strokeBorder(color.opacity(0.7), lineWidth: 1.2)
            } else if cell.level == 0 {
                shape.fill(Color.primary.opacity(0.08))
                    .overlay { if isToday { shape.strokeBorder(color.opacity(0.6), lineWidth: 1) } }
            } else {
                shape.fill(color.opacity(Self.opacities[min(cell.level, 4)]))
                    .widgetAccentable()
            }
        } else {
            shape.fill(.clear)
        }
    }
}

/// A static, non-interactive grid for widgets and the Today strip.
struct MiniGrid: View {
    let snapshot: GridSnapshot
    let color: Color
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let columns = CGFloat(snapshot.layout.weeks)
            let byWidth = (proxy.size.width - spacing * (columns - 1)) / columns
            let byHeight = (proxy.size.height - spacing * 6) / 7
            let size = max(1, min(byWidth, byHeight))
            HStack(spacing: spacing) {
                ForEach(0..<snapshot.layout.weeks, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            GridCellView(
                                cell: snapshot.cells[column][row], color: color,
                                cornerRadius: size * 0.25,
                                isToday: snapshot.layout.date(column: column, row: row) == snapshot.layout.today)
                                .frame(width: size, height: size)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }
}

/// "Less ▢▢▢▢▢ More"
struct GridLegend: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach(0..<5, id: \.self) { level in
                GridCellView(cell: GridCell(level: level), color: color, cornerRadius: 2)
                    .frame(width: size, height: size)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

#Preview {
    let today = LocalDate("2026-10-15")!
    let snapshot = GridSnapshot(layout: GridLayout(endingAt: today, weeks: 20)) { date in
        GridCell(level: (date.dayNumber * 7) % 5, isSkipped: date.dayNumber % 23 == 0)
    }
    VStack(alignment: .trailing) {
        MiniGrid(snapshot: snapshot, color: .green).frame(height: 120)
        GridLegend(color: .green)
    }
    .padding()
}
