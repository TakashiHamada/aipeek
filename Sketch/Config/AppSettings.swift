import Foundation
import Combine

/// Observable wrapper around AppConfig. SwiftUI views bind to its @Published
/// properties; changes are persisted back to config.json automatically.
@MainActor
final class AppSettings: ObservableObject {
    @Published var autoSave: Bool {
        didSet { persistIfReady() }
    }
    @Published var autoCopyOnSave: Bool {
        didSet { persistIfReady() }
    }
    @Published var retentionDays: Int {
        didSet { persistIfReady() }
    }
    /// User-editable sessions folder location. **Non-optional and always
    /// populated** — when no override is set we still show the default path so
    /// the UI's text field is never empty.
    ///
    /// On the way out to disk (`persistIfReady`), if the value matches
    /// `FileStore.defaultSessionsRoot` we store `nil` in `config.json` rather
    /// than the literal path string. That keeps config.json tidy and lets us
    /// follow future changes to the default location automatically.
    /// Compare against `AppConfig.customSessionsRoot: String?` which *is*
    /// optional — same concept, different layer.
    @Published var customSessionsRoot: String {
        didSet {
            applyCustomSessionsRoot()
            persistIfReady()
        }
    }

    private var isInitialized = false

    init() {
        let config = AppConfig.load(from: FileStore.configFileURL)
        self.autoSave = config.autoSave
        self.autoCopyOnSave = config.autoCopyOnSave
        self.retentionDays = config.retentionDays
        // Show the actual path (default if no override stored) in the field.
        let stored = config.customSessionsRoot?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            self.customSessionsRoot = stored
        } else {
            self.customSessionsRoot = FileStore.defaultSessionsRoot.path
        }
        self.isInitialized = true
        applyCustomSessionsRoot()
    }

    /// True when the field matches the default sessions location.
    var isUsingDefaultSessionsRoot: Bool {
        let expanded = (customSessionsRoot.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        return expanded == FileStore.defaultSessionsRoot.path
    }

    /// Reset the field to the default location.
    func resetSessionsRootToDefault() {
        customSessionsRoot = FileStore.defaultSessionsRoot.path
    }

    /// Push the current customSessionsRoot into FileStore so writes go to the right place.
    private func applyCustomSessionsRoot() {
        let trimmed = customSessionsRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            FileStore.customSessionsRoot = nil
            return
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded == FileStore.defaultSessionsRoot.path {
            FileStore.customSessionsRoot = nil
        } else {
            FileStore.customSessionsRoot = URL(fileURLWithPath: expanded, isDirectory: true)
        }
    }

    private func persistIfReady() {
        guard isInitialized else { return }
        let trimmed = customSessionsRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        // Don't pollute config.json with the default path — store nil instead.
        let valueToStore: String? = (trimmed.isEmpty || expanded == FileStore.defaultSessionsRoot.path) ? nil : trimmed
        AppConfig(
            autoSave: autoSave,
            autoCopyOnSave: autoCopyOnSave,
            retentionDays: retentionDays,
            customSessionsRoot: valueToStore
        ).save(to: FileStore.configFileURL)
    }
}
