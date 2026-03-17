import Foundation
import GRDB

struct SavedCommand: Identifiable {
    var id: UUID
    var projectID: UUID?  // nil = global command (available in all projects)
    var command: String

    var isGlobal: Bool { projectID == nil }
}

extension SavedCommand: Equatable {}

extension SavedCommand: FetchableRecord {
    init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        projectID = (row["projectId"] as String?).flatMap { UUID(uuidString: $0) }
        command = row["command"]
    }
}

extension SavedCommand: PersistableRecord {
    static var databaseTableName: String { "savedCommands" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["projectId"] = projectID?.uuidString
        container["command"] = command
    }
}
