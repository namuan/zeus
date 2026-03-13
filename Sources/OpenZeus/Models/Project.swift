import Foundation
import GRDB

struct Project: Identifiable {
    var id: UUID
    var name: String
    var directoryURL: URL
}

extension Project: Equatable {
    static func == (lhs: Project, rhs: Project) -> Bool { lhs.id == rhs.id }
}

extension Project: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Project: FetchableRecord {
    init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        name = row["name"]
        directoryURL = URL(fileURLWithPath: row["directoryURL"] as String)
    }
}

extension Project: PersistableRecord {
    static var databaseTableName: String { "projects" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["name"] = name
        container["directoryURL"] = directoryURL.path(percentEncoded: false)
    }
}
