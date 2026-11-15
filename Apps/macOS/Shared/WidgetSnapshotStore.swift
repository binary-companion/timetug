import Foundation

/// Reads and writes the agenda snapshot in the App Group container. The app writes; widgets read.
struct WidgetSnapshotStore {
    enum StoreError: Error { case noContainer }

    static let fileName = "agenda-snapshot.json"

    let directory: URL?

    init(directory: URL? = AppGroup.containerURL) { self.directory = directory }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func write(_ snapshot: WidgetSnapshot) throws {
        guard let fileURL else { throw StoreError.noContainer }
        try WidgetSnapshot.makeEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? WidgetSnapshot.makeDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
