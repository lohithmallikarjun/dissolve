import Engine
import SwiftUI
import WidgetKit

enum DeepLink {
    static let journalToday = URL(string: "dissolve://journal/today")!
    static func journal(_ date: LocalDate) -> URL { URL(string: "dissolve://journal/\(date)")! }
}

/// Small: today's prompt, or a tick when written. Tap opens today's entry.
struct JournalSmallView: View {
    let snapshot: JournalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: snapshot.writtenToday ? "checkmark.circle.fill" : "book.fill")
                    .font(.title3)
                    .foregroundStyle(snapshot.writtenToday ? .green : .indigo)
                    .widgetAccentable()
                Spacer()
                if snapshot.streak > 0 {
                    Label("\(snapshot.streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .numberStyle()
                }
            }
            Spacer(minLength: 0)
            if snapshot.writtenToday {
                Text("Journaled today").font(.headline)
                Text("Tap to add more").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(snapshot.prompt)
                    .font(.headline)
                    .lineLimit(3)
                Text("Tap to write").font(.caption).foregroundStyle(.secondary)
            }
        }
        .widgetURL(DeepLink.journalToday)
    }
}

/// Medium: an "On this day" photo and first line.
struct JournalMemoryView: View {
    let snapshot: JournalSnapshot

    var body: some View {
        if let memory = snapshot.memory {
            HStack(spacing: 12) {
                if let id = memory.photoID, let image = ImageStore.thumbnail(id: id) {
                    Image(platformImage: image)
                        .resizable()
                        .widgetAccentedRenderingMode(.desaturated)
                        .scaledToFill()
                        .frame(width: 120)
                        .frame(maxHeight: .infinity)
                        .clipShape(.rect(cornerRadius: 14))
                        .privacySensitive()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.isOnThisDay ? "On this day" : "Remember")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .widgetAccentable()
                    Text(memory.date.formatted(.dateTime.month(.wide).day().year()))
                        .font(.headline)
                    Text(memory.firstLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .privacySensitive()
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(DeepLink.journal(memory.date))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("On this day", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Text("Memories appear here once you've journaled for a while.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DeepLink.journalToday)
        }
    }
}

/// Lock Screen rectangular: journal streak.
struct JournalStreakRectangularView: View {
    let snapshot: JournalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Journal", systemImage: "book.fill")
                .font(.headline)
                .widgetAccentable()
            Text("\(snapshot.streak)-day streak").numberStyle()
            Text(snapshot.writtenToday ? "Written today ✓" : "Not written yet").font(.caption)
        }
        .widgetURL(DeepLink.journalToday)
    }
}
