import Foundation
import GRDB

struct Project: Identifiable {
    var id: UUID
    var name: String
    var directoryURL: URL
    var isDeleted: Bool = false
    var startupCommandID: UUID?
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
        var rawPath = row["directoryURL"] as String
        if rawPath.hasSuffix("/") { rawPath = String(rawPath.dropLast()) }
        directoryURL = URL(fileURLWithPath: rawPath)
        isDeleted = (row["isDeleted"] as? Int64 ?? 0) != 0
        startupCommandID = (row["startupCommandId"] as String?).flatMap(UUID.init(uuidString:))
    }
}

extension Project: PersistableRecord {
    static var databaseTableName: String { "projects" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["name"] = name
        container["directoryURL"] = directoryURL.path(percentEncoded: false)
        container["isDeleted"] = isDeleted ? 1 : 0
        container["startupCommandId"] = startupCommandID?.uuidString
    }
}
