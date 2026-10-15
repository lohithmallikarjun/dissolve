import LocalAuthentication
import Observation
import SwiftUI

/// Face ID / Touch ID lock for the journal. Locks again whenever the app leaves the foreground.
@MainActor @Observable
final class JournalLock {
    private static let enabledKey = "journal.lockEnabled"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var isUnlocked = false
    private(set) var failure: String?

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey)
        // CI screenshots run without a passcode; don't block on the lock there.
        if ProcessInfo.processInfo.arguments.contains("-demoData") { isUnlocked = true }
    }

    var isLocked: Bool { isEnabled && !isUnlocked }

    func lock() {
        if isEnabled { isUnlocked = false }
    }

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        // No passcode or biometrics set up: nothing to protect with.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: String(localized: "Unlock your journal"))
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: String(localized: "Passcode")
        }
    }
}
