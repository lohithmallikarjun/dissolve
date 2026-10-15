import SwiftUI

extension View {
    /// Solid content card (not glass): 20 pt padding, continuous 22 pt corners.
    func card(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(.background.secondary, in: .rect(cornerRadius: 22))
    }

    /// Rounded, fixed-width digits for every number.
    func numberStyle() -> some View {
        fontDesign(.rounded).monospacedDigit()
    }
}

enum Metrics {
    #if os(macOS)
    static let margin: CGFloat = 20
    #else
    static let margin: CGFloat = 16
    #endif
}

/// Placeholder for features that arrive in a later milestone.
struct ComingSoonView: View {
    let title: LocalizedStringKey
    let symbol: String
    let milestone: Int

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text("Arrives in Milestone \(milestone).")
        }
    }
}

#Preview {
    ComingSoonView(title: "Journal", symbol: "book", milestone: 2)
}
