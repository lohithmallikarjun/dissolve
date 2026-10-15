import Foundation
#if os(iOS)
import UIKit
#endif

/// A stable per-install ID, used to name this device's sync files.
enum DeviceIdentity {
    static var id: String {
        let defaults = AppGroup.defaults
        if let existing = defaults.string(forKey: SharedKeys.deviceID) { return existing }
        let new = UUID().uuidString
        defaults.set(new, forKey: SharedKeys.deviceID)
        return new
    }

    @MainActor static var name: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }

    static var platform: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }
}
