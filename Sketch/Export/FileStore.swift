import Foundation

enum FileStore {
    static let bundleFolderName = "com.giftten.sketch"
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

    static var sessionsRoot: URL {
        appSupportRoot.appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    static var configFileURL: URL {
        appSupportRoot.appendingPathComponent(configFileName)
    }

    /// Ensure the app support root directory exists.
    static func ensureAppSupportRoot() throws {
        try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
    }

    /// Save PNG data and return the resulting file URL.
    @discardableResult
    static func save(_ data: Data, at date: Date) throws -> URL {
        let dateFolderName = dateFormatter.string(from: date)
        let timeStamp = timeFormatter.string(from: date)

        let folderURL = sessionsRoot.appendingPathComponent(dateFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var fileURL = folderURL.appendingPathComponent("sketch_\(timeStamp).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = folderURL.appendingPathComponent("sketch_\(timeStamp)_\(counter).png")
            counter += 1
            if counter > 99 { break }
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
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
