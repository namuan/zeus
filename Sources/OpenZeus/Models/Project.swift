import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var directoryURL: URL
    @Relationship(deleteRule: .cascade, inverse: \AgentTask.project) var tasks: [AgentTask] = []

    init(id: UUID = UUID(), name: String, directoryURL: URL, tasks: [AgentTask] = []) {
        self.id = id
        self.name = name
        self.directoryURL = directoryURL
        self.tasks = tasks
    }
}
