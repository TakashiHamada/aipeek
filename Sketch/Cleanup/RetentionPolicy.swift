import Foundation

enum RetentionPolicy {
    case keepAll
    case deleteAll
    case keepLatest(Int)

    init(retentionDays: Int) {
        switch retentionDays {
        case -1: self = .keepAll
        case 0: self = .deleteAll
        default: self = .keepLatest(max(retentionDays, 1))
        }
    }

    /// Given session folder names sorted descending, returns the names that should be deleted.
    func foldersToDelete(sortedDescending names: [String]) -> [String] {
        switch self {
        case .keepAll:
            return []
        case .deleteAll:
            return names
        case .keepLatest(let n):
            return Array(names.dropFirst(n))
        }
    }
}
