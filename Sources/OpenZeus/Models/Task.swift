import Foundation
import SwiftData

@Model
final class AgentTask {
    @Attribute(.unique) var id: UUID
    var name: String
    var command: String
    var environment: [String: String]
    var workingDirectory: URL
    var status: AgentStatus
    var terminalState: TerminalState?
    var project: Project?

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        environment: [String: String] = [:],
        workingDirectory: URL,
        status: AgentStatus = .idle,
        terminalState: TerminalState? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.status = status
        self.terminalState = terminalState
        self.project = project
    }
}
