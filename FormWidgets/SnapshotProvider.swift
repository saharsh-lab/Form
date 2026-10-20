import WidgetKit
import FormCore

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil until the app has saved a snapshot (or without the App Group).
    let snapshot: WidgetSnapshot?
    /// True only for the widget gallery preview, which shows sample values.
    var isPreview = false
}

/// Reads the snapshot the app writes after every save. The app reloads widget
/// timelines when data changes; the timeline adds an entry at midnight so
/// "today" values reset even if the app isn't opened.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample(), isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = Self.load()
        if context.isPreview && stored == nil {
            completion(SnapshotEntry(date: Date(), snapshot: .sample(), isPreview: true))
        } else {
            completion(SnapshotEntry(date: Date(), snapshot: stored))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = Self.load()
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            entries.append(SnapshotEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func load() -> WidgetSnapshot? {
        AppGroup.widgetSnapshotURL.flatMap(WidgetSnapshotStore.read(from:))
    }
}
