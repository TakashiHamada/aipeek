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
    /// User-editable sessions folder location. Empty string is treated as nil.
    /// Path may contain `~`; resolved via NSString.expandingTildeInPath.
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
        self.customSessionsRoot = config.customSessionsRoot ?? ""
        self.isInitialized = true
        applyCustomSessionsRoot()
    }

    /// The active sessions root URL, taking the user's override into account.
    var resolvedSessionsRoot: URL {
        FileStore.sessionsRoot
    }

    /// Push the current customSessionsRoot into FileStore so writes go to the right place.
    private func applyCustomSessionsRoot() {
        let trimmed = customSessionsRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            FileStore.customSessionsRoot = nil
        } else {
            let expanded = (trimmed as NSString).expandingTildeInPath
            FileStore.customSessionsRoot = URL(fileURLWithPath: expanded, isDirectory: true)
        }
    }

    private func persistIfReady() {
        guard isInitialized else { return }
        let trimmed = customSessionsRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig(
            autoSave: autoSave,
            autoCopyOnSave: autoCopyOnSave,
            retentionDays: retentionDays,
            customSessionsRoot: trimmed.isEmpty ? nil : trimmed
        ).save(to: FileStore.configFileURL)
    }
}
