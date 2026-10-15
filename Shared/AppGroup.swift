import Foundation

/// The App Group shared by the app and the widget extension.
enum AppGroup {
    static let id = "group.com.lohith.dissolve"

    /// nil when the App Group is missing from the provisioning profile.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

/// Keys in `AppGroup.defaults`.
enum SharedKeys {
    static let deviceID = "device.id"
    static let diagnosticCounter = "m0.counter"
    static let diagnosticUpdatedAt = "m0.updatedAt"
}
