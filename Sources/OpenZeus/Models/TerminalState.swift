import Foundation

struct TerminalState: Codable, Equatable, Sendable {
    var lastCommand: String?
    var scrollOffset: Double?
    var customPrompt: String?
    var environmentOverrides: [String: String]
}
