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
