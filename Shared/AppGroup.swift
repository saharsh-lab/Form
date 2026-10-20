import Foundation

/// The App Group shared by the app and its widget extension. Compiled into both targets.
enum AppGroup {
    static let fallbackIdentifier = "group.com.example.form"

    /// Read from Info.plist (`FormAppGroupIdentifier`), which XcodeGen fills from the `FORM_APP_GROUP` build setting.
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "FormAppGroupIdentifier") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? fallbackIdentifier
    }

    /// The shared container, or nil when the App Group entitlement is unavailable
    /// (for example a signing team without App Group support).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Where the app writes the widget snapshot; nil without the App Group.
    static var widgetSnapshotURL: URL? {
        containerURL.map { $0.appendingPathComponent("widget-snapshot.json") }
    }
}
