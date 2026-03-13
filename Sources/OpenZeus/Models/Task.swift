import Foundation
import GRDB

struct AgentTask: Identifiable {
    var id: UUID
    var projectID: UUID
    var name: String
    var taskDescription: String?
    var command: String
    var environment: [String: String]
    var workingDirectory: URL
    var status: AgentStatus
    var terminalState: TerminalState?
    var watchMode: WatchMode = .off
}

extension AgentTask: Equatable {
    static func == (lhs: AgentTask, rhs: AgentTask) -> Bool { lhs.id == rhs.id }
}

extension AgentTask: FetchableRecord {
    init(row: Row) throws {
        id = UUID(uuidString: row["id"]) ?? UUID()
        projectID = UUID(uuidString: row["projectId"]) ?? UUID()
        name = row["name"]
        taskDescription = row["taskDescription"]
        command = row["command"]
        let envString: String = row["environment"]
        environment = (try? JSONDecoder().decode([String: String].self, from: Data(envString.utf8))) ?? [:]
        workingDirectory = URL(fileURLWithPath: row["workingDirectory"] as String)
        status = AgentStatus(rawValue: row["status"]) ?? .idle
        if let tsString: String = row["terminalState"],
           let data = tsString.data(using: .utf8) {
            terminalState = try? JSONDecoder().decode(TerminalState.self, from: data)
        }
        watchMode = WatchMode(rawValue: row["watchMode"] as? String ?? "") ?? .off
    }
}

extension AgentTask: PersistableRecord {
    static var databaseTableName: String { "tasks" }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["projectId"] = projectID.uuidString
        container["name"] = name
        container["taskDescription"] = taskDescription
        container["command"] = command
        let envData = (try? JSONEncoder().encode(environment)) ?? Data("{}".utf8)
        container["environment"] = String(data: envData, encoding: .utf8) ?? "{}"
        container["workingDirectory"] = workingDirectory.path(percentEncoded: false)
        container["status"] = status.rawValue
        if let ts = terminalState, let data = try? JSONEncoder().encode(ts) {
            container["terminalState"] = String(data: data, encoding: .utf8)
        } else {
            container["terminalState"] = nil
        }
        container["watchMode"] = watchMode.rawValue
    }
}
