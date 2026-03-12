import Foundation

enum AgentStatus: String, Codable, Sendable {
    case idle
    case running
    case stopped
    case error
}
