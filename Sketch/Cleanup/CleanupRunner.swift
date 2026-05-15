import Foundation
import os

enum CleanupRunner {
    private static let log = Logger(subsystem: "com.giftten.sketch", category: "cleanup")

    /// Run cleanup once at startup. No-op if there is no sessions folder yet.
    static func runOnLaunch(retentionDays: Int) {
        let policy = RetentionPolicy(retentionDays: retentionDays)
        let folders = FileStore.listSessionDateFolders()
        let toDelete = policy.foldersToDelete(sortedDescending: folders)

        guard !toDelete.isEmpty else {
            log.info("cleanup: nothing to delete (policy=\(retentionDays), folders=\(folders.count))")
            return
        }

        for name in toDelete {
            do {
                try FileStore.removeSessionFolder(named: name)
                log.info("cleanup: removed \(name, privacy: .public)")
            } catch {
                log.error("cleanup: failed to remove \(name, privacy: .public) — \(String(describing: error), privacy: .public)")
            }
        }
    }
}
