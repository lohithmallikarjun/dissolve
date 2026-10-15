import SwiftUI

/// The 12 system colours a habit can use.
enum HabitColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }

    var name: LocalizedStringKey { LocalizedStringKey(rawValue.capitalized) }

    static func named(_ name: String) -> HabitColor { HabitColor(rawValue: name) ?? .green }
}

extension Habit {
    var color: Color { HabitColor.named(colorName).color }
}

/// SF Symbols offered in the habit editor.
enum HabitSymbols {
    static let all: [String] = [
        "checkmark", "drop.fill", "figure.run", "figure.walk", "dumbbell.fill", "bicycle",
        "figure.yoga", "brain.head.profile", "book.fill", "pencil", "bed.double.fill", "sun.max.fill",
        "leaf.fill", "carrot.fill", "fork.knife", "cup.and.saucer.fill", "pills.fill", "heart.fill",
        "music.note", "guitars.fill", "paintbrush.fill", "laptopcomputer", "phone.down.fill", "nosign",
        "moon.stars.fill", "sparkles", "flame.fill", "dollarsign.circle.fill", "house.fill", "pawprint.fill",
        "tooth.fill", "shower.fill", "graduationcap.fill", "globe", "camera.fill", "hands.sparkles.fill",
    ]
}
