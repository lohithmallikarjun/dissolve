import Engine
import SwiftUI
import WidgetKit

/// Small: "D-41", title, ring. A live timer in the final hours.
struct CountdownSmallView: View {
    let countdown: CountdownSummary?

    var body: some View {
        if let c = countdown {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: c.symbol).font(.headline).foregroundStyle(c.color).widgetAccentable()
                    Spacer()
                    if !c.countUp {
                        Gauge(value: c.progress) { EmptyView() }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(c.color)
                            .scaleEffect(0.6)
                            .frame(width: 34, height: 34)
                    }
                }
                Spacer(minLength: 0)
                if c.isFinalHours {
                    Text(c.occurrence, style: .timer)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text(c.shortLabel)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(c.occurrence, format: .dateTime.month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "dissolve://life"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "timer").font(.title2).foregroundStyle(.orange)
                Text("Add a countdown in Dissolve").font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Medium: the next three countdowns.
struct CountdownListView: View {
    let countdowns: [CountdownSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Countdowns").font(.headline)
            if countdowns.isEmpty {
                Text("Add a countdown in Dissolve").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(countdowns.prefix(3)) { c in
                HStack(spacing: 10) {
                    Image(systemName: c.symbol)
                        .foregroundStyle(c.color)
                        .frame(width: 22)
                        .widgetAccentable()
                    Text(c.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                    if c.isFinalHours {
                        Text(c.occurrence, style: .timer).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(c.countUp ? "\(c.days)d since" : c.days == 0 ? "Today" : "\(c.days)d")
                            .font(.subheadline.weight(.semibold))
                            .numberStyle()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "dissolve://life"))
    }
}

/// Lock Screen inline: "Marathon · 41d".
struct CountdownInlineView: View {
    let countdown: CountdownSummary?
    var body: some View {
        if let c = countdown {
            Label("\(c.title) · \(c.countUp ? "+" : "")\(c.days)d", systemImage: c.symbol)
        } else {
            Label("No countdowns", systemImage: "timer")
        }
    }
}

/// Lock Screen circular: a gauge with days left.
struct CountdownCircularView: View {
    let countdown: CountdownSummary?
    var body: some View {
        if let c = countdown {
            Gauge(value: c.countUp ? 1 : c.progress) {
                Image(systemName: c.symbol)
            } currentValueLabel: {
                Text("\(c.days)").numberStyle()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            Image(systemName: "timer")
        }
    }
}

/// Small: % of life remaining.
struct LifeSmallView: View {
    let life: TimeSnapshot.Life?

    var body: some View {
        if let life {
            VStack(alignment: .leading, spacing: 6) {
                Text("Life remaining").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(Color.indigo.opacity(0.2), lineWidth: 10)
                    Circle().trim(from: 0, to: life.fractionRemaining)
                        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                    Text(life.fractionRemaining, format: .percent.precision(.fractionLength(1)))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Text("\(life.weeksRemaining.formatted()) weeks left").font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "dissolve://life"))
        } else {
            LifeSetUpPrompt()
        }
    }
}

/// Large: one dot per year of life.
struct LifeYearsView: View {
    let life: TimeSnapshot.Life?

    var body: some View {
        if let life {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your life in years").font(.headline)
                    Spacer()
                    Text(life.fractionRemaining, format: .percent.precision(.fractionLength(1)))
                        .font(.headline).foregroundStyle(.indigo).monospacedDigit()
                }
                let columns = 10
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<Int((Double(life.years) / Double(columns)).rounded(.up)), id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let year = row * columns + column
                                if year < life.years {
                                    Circle()
                                        .fill(year < life.age ? Color.indigo : year == life.age ? Color.green : Color.clear)
                                        .overlay { Circle().strokeBorder(Color.secondary.opacity(year > life.age ? 0.5 : 0), lineWidth: 1) }
                                        .widgetAccentable(year <= life.age)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
                Text("\(life.weeksLived.formatted()) weeks lived · \(life.weeksRemaining.formatted()) remain")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "dissolve://life"))
        } else {
            LifeSetUpPrompt()
        }
    }
}

struct LifeCircularView: View {
    let life: TimeSnapshot.Life?
    var body: some View {
        Gauge(value: life?.fractionRemaining ?? 0) {
            Image(systemName: "hourglass")
        } currentValueLabel: {
            Text("\(Int(((life?.fractionRemaining ?? 0) * 100).rounded()))").numberStyle()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

private struct LifeSetUpPrompt: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hourglass").font(.title2).foregroundStyle(.indigo)
            Text("Add your birth date in Dissolve").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
