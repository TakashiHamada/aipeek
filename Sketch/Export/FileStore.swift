import Foundation

enum FileStore {
    static let bundleFolderName = "com.giftten.aipeek"
    static let sessionsFolderName = "sessions"
    static let configFileName = "config.json"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH-mm-ss"
        return f
    }()

    static var appSupportRoot: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(bundleFolderName, isDirectory: true)
    }

    /// User-supplied override for the sessions folder location. When set, all
    /// reads/writes go here instead of `appSupportRoot/sessions`. config.json
    /// itself always stays in `appSupportRoot` so the user can find it.
    ///
    /// Concurrency: written only from @MainActor (`AppSettings`); read from
    /// any actor through `sessionsRoot`. No lock — last-writer-wins is fine
    /// because writes are user-driven config edits at human pace.
    nonisolated(unsafe) static var customSessionsRoot: URL?

    static var sessionsRoot: URL {
        if let custom = customSessionsRoot {
            return custom
        }
        return appSupportRoot.appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    /// The default sessions root, ignoring any user override.
    static var defaultSessionsRoot: URL {
        appSupportRoot.appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    static var configFileURL: URL {
        appSupportRoot.appendingPathComponent(configFileName)
    }

    static func ensureAppSupportRoot() throws {
        try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
    }

    /// Compute the next available filename for the given date (creating the
    /// date folder if needed) without writing any data. Used to reserve an
    /// auto-save target up front.
    /// If a slot can't be found within 99 attempts, falls back to a millisecond
    /// suffix so we never silently overwrite an existing file.
    static func reserveFilename(at date: Date) throws -> URL {
        let dateFolderName = dateFormatter.string(from: date)
        let timeStamp = timeFormatter.string(from: date)

        let folderURL = sessionsRoot.appendingPathComponent(dateFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var fileURL = folderURL.appendingPathComponent("sketch_\(timeStamp).jpg")
        var counter = 2
        while FileManager.default.fileExists(atPath: fileURL.path), counter <= 99 {
            fileURL = folderURL.appendingPathComponent("sketch_\(timeStamp)_\(counter).jpg")
            counter += 1
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            // 99 collisions in the same second is implausible from this app
            // alone, but could happen if the user dumped files into the folder
            // externally. Fall back to a millisecond suffix instead of
            // overwriting.
            let ms = Int(Date().timeIntervalSince1970 * 1000) % 1000
            fileURL = folderURL.appendingPathComponent("sketch_\(timeStamp)_ms\(ms).jpg")
        }
        return fileURL
    }

    /// Atomically write the given bytes to `url` (JPEG in current usage, but
    /// the function itself is format-agnostic). Parent folder is auto-created.
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Convenience: reserve a fresh filename for `date` and write `data` to it.
    /// Used by the manual Copy & Save flow (when auto-save is OFF).
    @discardableResult
    static func save(_ data: Data, at date: Date) throws -> URL {
        let url = try reserveFilename(at: date)
        try write(data, to: url)
        return url
    }

    /// Return all session date folder names (YYYY-MM-DD) sorted descending.
    static func listSessionDateFolders() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .compactMap { url -> String? in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { return nil }
                let name = url.lastPathComponent
                guard dateFormatter.date(from: name) != nil else { return nil }
                return name
            }
            .sorted(by: >)
    }

    static func removeSessionFolder(named name: String) throws {
        let url = sessionsRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.removeItem(at: url)
    }
}
