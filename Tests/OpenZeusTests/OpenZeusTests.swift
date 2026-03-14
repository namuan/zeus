import Foundation
import Testing
@testable import OpenZeus

@Test func agentStatusCodable() throws {
    let statuses: [AgentStatus] = [.idle, .running, .stopped, .error]
    for status in statuses {
        let data = try #require(try? JSONEncoder().encode(status))
        let decoded = try #require(try? JSONDecoder().decode(AgentStatus.self, from: data))
        #expect(decoded == status)
    }
}

@Test func terminalStateRoundTrip() throws {
    let state = TerminalState(
        lastCommand: "swift build",
        scrollOffset: 42.0,
        customPrompt: "> ",
        environmentOverrides: ["KEY": "VALUE"]
    )
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(TerminalState.self, from: data)
    #expect(decoded == state)
}

@Test func terminalStateEquality() {
    let a = TerminalState(lastCommand: nil, scrollOffset: nil, customPrompt: nil, environmentOverrides: [:])
    let b = TerminalState(lastCommand: nil, scrollOffset: nil, customPrompt: nil, environmentOverrides: [:])
    #expect(a == b)
}

@Test @MainActor func savedCommandInsertAndFetch() throws {
    let db = try AppDatabase(inMemory: ())
    let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/tmp"))
    db.insertProject(project)
    let cmd = SavedCommand(id: UUID(), projectID: project.id, command: "swift build")
    db.insertSavedCommand(cmd)
    // Allow ValueObservation to fire
    let fetched = db.savedCommands(for: project.id)
    #expect(fetched.count == 1)
    #expect(fetched.first?.command == "swift build")
    #expect(fetched.first?.projectID == project.id)
}

@Test @MainActor func savedCommandDeleteWorks() throws {
    let db = try AppDatabase(inMemory: ())
    let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/tmp"))
    db.insertProject(project)
    let cmd = SavedCommand(id: UUID(), projectID: project.id, command: "echo hello")
    db.insertSavedCommand(cmd)
    db.deleteSavedCommand(id: cmd.id)
    let fetched = db.savedCommands(for: project.id)
    #expect(fetched.isEmpty)
}
