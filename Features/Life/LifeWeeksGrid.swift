import Engine
import SwiftUI

/// "Life in Weeks": 52 columns × lifespan rows, drawn with Canvas (thousands of cells).
/// Past weeks filled (tinted by era), the current week pulsing, future weeks outlined.
struct LifeWeeksGrid: View {
    let grid: LifeGrid
    let eras: [LifeEra]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let labelWidth: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let cell = cellSize(for: proxy.size)
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: true) { context, _ in
                    draw(in: &context, cell: cell)
                }
                if let current = grid.current {
                    let dot = cell * 0.78
                    Circle()
                        .fill(Color.green)
                        .frame(width: dot, height: dot)
                        .phaseAnimator(reduceMotion ? [false] : [false, true]) { view, phase in
                            view.scaleEffect(phase ? 1.6 : 1).opacity(phase ? 0.6 : 1)
                        } animation: { _ in .easeInOut(duration: 1.2) }
                        .position(x: labelWidth + (CGFloat(current.column) + 0.5) * cell,
                                  y: (CGFloat(current.row) + 0.5) * cell)
                }
            }
        }
        .aspectRatio((labelWidth / 8 + CGFloat(LifeGrid.weeksPerYear)) / CGFloat(grid.years), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Life in weeks: \(grid.weeksLived) weeks lived, \(grid.weeksRemaining) remain")
    }

    private func cellSize(for size: CGSize) -> CGFloat {
        min((size.width - labelWidth) / CGFloat(LifeGrid.weeksPerYear), size.height / CGFloat(grid.years))
    }

    private func draw(in context: inout GraphicsContext, cell: CGFloat) {
        let dot = cell * 0.78
        let inset = (cell - dot) / 2
        var pastByColor: [String: Path] = [:]
        var future = Path()

        for row in 0..<grid.years {
            for column in 0..<LifeGrid.weeksPerYear {
                let c = LifeGrid.Cell(row: row, column: column)
                let rect = CGRect(x: labelWidth + CGFloat(column) * cell + inset,
                                  y: CGFloat(row) * cell + inset, width: dot, height: dot)
                switch grid.state(c) {
                case .past:
                    let key = grid.era(for: c, in: eras)?.colorName ?? ""
                    pastByColor[key, default: Path()].addEllipse(in: rect)
                case .current:
                    break  // the pulsing overlay
                case .future:
                    future.addEllipse(in: rect.insetBy(dx: dot * 0.12, dy: dot * 0.12))
                }
            }
            if row % 10 == 0 {
                context.draw(Text("\(row)").font(.system(size: max(cell * 0.9, 7))).foregroundStyle(.secondary),
                             at: CGPoint(x: labelWidth - 4, y: (CGFloat(row) + 0.5) * cell), anchor: .trailing)
            }
        }
        for (colorName, path) in pastByColor {
            let color = colorName.isEmpty ? Color.primary.opacity(0.7) : HabitColor.named(colorName).color
            context.fill(path, with: .color(color))
        }
        context.stroke(future, with: .color(Color.secondary.opacity(0.45)), lineWidth: max(cell * 0.08, 0.5))
    }
}

#Preview {
    LifeWeeksGrid(
        grid: LifeGrid(birth: LocalDate("1995-06-12")!, years: 80, today: LocalDate("2026-10-15")!),
        eras: [LifeEra(name: "University", start: LocalDate("2013-08-01")!, end: LocalDate("2017-06-30")!, colorName: "purple")])
        .padding()
}
