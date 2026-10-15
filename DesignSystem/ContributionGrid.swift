import Engine
import SwiftUI

/// The interactive GitHub-style grid: month labels, weekday labels, legend, tap/hover per cell.
///
/// iPhone: tap shows a popover; tapping the same cell again calls `onEdit`.
/// Mac: hover shows a tooltip; click selects (the parent shows an inspector), click again edits.
struct ContributionGrid<Popover: View>: View {
    let snapshot: GridSnapshot
    let color: Color
    @Binding var selection: LocalDate?
    /// VoiceOver / tooltip text for a day, e.g. "March 3, 2 of 3 habits".
    let label: (LocalDate) -> String
    var onEdit: (LocalDate) -> Void = { _ in }
    @ViewBuilder var popover: (LocalDate) -> Popover

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var appeared = false

    let spacing: CGFloat = 3
    let labelWidth: CGFloat = 26

    private var cellSize: CGFloat {
        let columns = CGFloat(snapshot.layout.weeks)
        let available = width - labelWidth - spacing * (columns - 1)
        return min(max(available / columns, 6), 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            monthLabels
            HStack(alignment: .top, spacing: spacing) {
                weekdayLabels
                ForEach(0..<snapshot.layout.weeks, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cellView(column: column, row: row)
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.6, anchor: .bottom)
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.25)
                            : .smooth(duration: 0.45).delay(Double(column) * 0.012),
                        value: appeared)
                }
            }
            HStack {
                Spacer()
                GridLegend(color: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { appeared = true }
    }

    private var monthLabels: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: 14)
            ForEach(snapshot.layout.monthLabels, id: \.self) { label in
                Text(Calendar.current.shortMonthSymbols[label.month - 1])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: labelWidth + spacing + CGFloat(label.column) * (cellSize + spacing))
            }
        }
        .accessibilityHidden(true)
    }

    private var weekdayLabels: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(snapshot.layout.rowWeekdays.enumerated()), id: \.offset) { row, weekday in
                Text(row % 2 == 0 ? Calendar.current.veryShortWeekdaySymbols[weekday - 1] : "")
                    .font(.system(size: max(min(cellSize * 0.7, 11), 7)))
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - spacing, height: cellSize, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cellView(column: Int, row: Int) -> some View {
        let date = snapshot.layout.date(column: column, row: row)
        let isToday = date == snapshot.layout.today
        let cell = GridCellView(
            cell: snapshot.cells[column][row], color: color,
            cornerRadius: cellSize * 0.22, isToday: isToday)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if let date, date == selection {
                    RoundedRectangle(cornerRadius: cellSize * 0.22, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: 1.5)
                }
            }
        if let date {
            cell
                .modifier(TodayPulse(active: isToday && !reduceMotion))
                .contentShape(.rect)
                .onTapGesture { tap(date) }
                .help(label(date))
                .accessibilityElement()
                .accessibilityLabel(label(date))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Edit") { onEdit(date) }
                #if os(iOS)
                .popover(isPresented: popoverBinding(for: date)) {
                    popover(date)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
                #endif
        } else {
            cell.accessibilityHidden(true)
        }
    }

    private func tap(_ date: LocalDate) {
        if selection == date {
            onEdit(date)
        } else {
            withAnimation(.snappy) { selection = date }
        }
    }

    #if os(iOS)
    private func popoverBinding(for date: LocalDate) -> Binding<Bool> {
        Binding(
            get: { selection == date },
            set: { if !$0, selection == date { selection = nil } })
    }
    #endif
}

/// Today's cell breathes gently.
private struct TodayPulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([false, true]) { view, phase in
                view.scaleEffect(phase ? 1.12 : 1).opacity(phase ? 1 : 0.85)
            } animation: { _ in .easeInOut(duration: 1.4) }
        } else {
            content
        }
    }
}

#Preview {
    @Previewable @State var selection: LocalDate?
    let today = LocalDate("2026-10-15")!
    let snapshot = GridSnapshot(layout: WeekGrid(endingAt: today, weeks: 53)) { date in
        GridCell(level: (date.dayNumber * 7 + date.day) % 5, isSkipped: date.dayNumber % 29 == 0)
    }
    ContributionGrid(snapshot: snapshot, color: .green, selection: $selection, label: { $0.formatted() }) { date in
        Text(date.formatted())
    }
    .padding()
}
