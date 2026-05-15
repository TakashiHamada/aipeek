import Foundation

struct AppConfig: Codable {
    var autoSave: Bool
    var autoCopyOnSave: Bool
    var retentionDays: Int

    static let `default` = AppConfig(autoSave: true, autoCopyOnSave: true, retentionDays: 1)

    enum CodingKeys: String, CodingKey {
        case autoSave
        case autoCopyOnSave
        case retentionDays
    }

    init(autoSave: Bool, autoCopyOnSave: Bool, retentionDays: Int) {
        self.autoSave = autoSave
        self.autoCopyOnSave = autoCopyOnSave
        self.retentionDays = retentionDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.autoSave = (try? container.decodeIfPresent(Bool.self, forKey: .autoSave)) ?? AppConfig.default.autoSave
        self.autoCopyOnSave = (try? container.decodeIfPresent(Bool.self, forKey: .autoCopyOnSave)) ?? AppConfig.default.autoCopyOnSave
        self.retentionDays = (try? container.decodeIfPresent(Int.self, forKey: .retentionDays)) ?? AppConfig.default.retentionDays
    }

    static func load(from url: URL) -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return .default
        }
    }

    func save(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Non-fatal: persist next time
        }
    }
}
