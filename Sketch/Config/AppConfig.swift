import Foundation

struct AppConfig: Codable {
    var retentionDays: Int

    static let `default` = AppConfig(retentionDays: 1)

    enum CodingKeys: String, CodingKey {
        case retentionDays
    }

    init(retentionDays: Int) {
        self.retentionDays = retentionDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
}
