import Foundation
import GRDB

struct ProjectApp: Identifiable {
    var id: UUID
    var projectID: UUID?  // nil = global app (appears in all projects)
    var appPath: String
    var displayName: String

    var isGlobal: Bool { projectID == nil }
}

extension ProjectApp: Equatable {}

extension ProjectApp: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ProjectApp: FetchableRecord {
    init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        projectID = (row["projectId"] as String?).flatMap { UUID(uuidString: $0) }
        appPath = row["appPath"]
        displayName = row["displayName"]
    }
}

extension ProjectApp: PersistableRecord {
    static var databaseTableName: String { "projectApps" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["projectId"] = projectID?.uuidString
        container["appPath"] = appPath
        container["displayName"] = displayName
    }
}
