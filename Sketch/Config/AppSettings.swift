import Foundation
import Combine

/// Observable wrapper around AppConfig. SwiftUI views bind to its @Published
/// properties; changes are persisted back to config.json automatically.
@MainActor
final class AppSettings: ObservableObject {
    @Published var autoSave: Bool {
        didSet { persistIfReady() }
    }
    @Published var retentionDays: Int {
        didSet { persistIfReady() }
    }

    private var isInitialized = false

    init() {
        let config = AppConfig.load(from: FileStore.configFileURL)
        self.autoSave = config.autoSave
        self.retentionDays = config.retentionDays
        self.isInitialized = true
    }

    private func persistIfReady() {
        guard isInitialized else { return }
        AppConfig(autoSave: autoSave, retentionDays: retentionDays)
            .save(to: FileStore.configFileURL)
    }
}
