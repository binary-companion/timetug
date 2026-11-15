import AppKit

/// The licence notices of what the app links (the engine's crates, KeyboardShortcuts), which the build phase
/// `scripts/ci/copy-licence-notices.sh` puts in `Contents/Resources/Licenses/`. The About screens show them.
enum ThirdPartyNotices {
    static let folderName = "Licenses"
    /// Shown in this order, each under a heading.
    private static let sections: [(file: String, heading: String)] = [
        ("TimeTugEngine-LICENSE", "TimeTug engine (timetug-shared): licence"),
        ("KeyboardShortcuts-LICENSE", "KeyboardShortcuts by Sindre Sorhus: licence"),
        ("TimeTugEngine-THIRD-PARTY-NOTICES.md", "TimeTug engine (timetug-shared): third-party notices"),
    ]
    static var fileNames: [String] { sections.map(\.file) }

    static func directory(resourceURL: URL?) -> URL? {
        guard let resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent(folderName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// All the notices as one text, or nil when any file is missing (the build fails in that case, so nil means
    /// a damaged copy of the app).
    static func text(resourceURL: URL?) -> String? {
        guard let directory = directory(resourceURL: resourceURL) else { return nil }
        var parts: [String] = []
        for section in sections {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(section.file), encoding: .utf8) else { return nil }
            parts.append("\(section.heading)\n\(String(repeating: "=", count: section.heading.count))\n\n\(text)")
        }
        return parts.joined(separator: "\n\n\n")
    }
}

/// The small window that shows the notices (opened from the About screens).
@MainActor
final class ThirdPartyNoticesWindowController {
    static let shared = ThirdPartyNoticesWindowController()
    private var window: NSWindow?

    func show(on screen: NSScreen? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        WindowPresenter.present(window, on: screen)
    }

    private func makeWindow() -> NSWindow {
        let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                               styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        created.title = "Third-party notices"
        created.isReleasedWhenClosed = false
        created.minSize = NSSize(width: 360, height: 240)
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textContainerInset = NSSize(width: 10, height: 10)
            textView.string = ThirdPartyNotices.text(resourceURL: Bundle.main.resourceURL)
                ?? "The licence notices are missing from this copy of TimeTug. See https://github.com/binary-companion/timetug-shared/blob/main/THIRD-PARTY-NOTICES.md"
            textView.setAccessibilityLabel("Third-party notices")
        }
        created.contentView = scroll
        created.center()
        return created
    }
}
