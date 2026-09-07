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

    static func tmuxLaunchArguments(
        sessionName: String,
        shell: String,
        workingDirectory: String,
        startupCommand: String?
    ) -> [String] {
        var arguments = ["new-session", "-A", "-c", workingDirectory, "-s", sessionName, shell, "-l"]
        if let startupCommand {
            let literalCommand = startupCommand.hasSuffix(";")
                ? String(startupCommand.dropLast()) + "\\;"
                : startupCommand
            arguments += [
                ";", "send-keys", "-t", sessionName, "-l", "--", literalCommand,
                ";", "send-keys", "-t", sessionName, "Enter"
            ]
        }
        return arguments
    }
}
