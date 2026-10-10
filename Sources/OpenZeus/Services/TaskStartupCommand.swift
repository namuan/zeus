import Foundation

enum TaskStartupCommand {
    enum ConfigurationError: LocalizedError {
        case invalidCommand

        var errorDescription: String? {
            "Choose a non-empty, single-line Quick Command from this project or Global."
        }
    }

    static func isValid(_ command: String) -> Bool {
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && command.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    }
}
