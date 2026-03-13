import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    let task: AgentTask
    @EnvironmentObject var terminalStore: TerminalStore

    var body: some View {
        TerminalPaneContent(task: task, entry: terminalStore.entry(for: task.id))
    }
}

private struct TerminalPaneContent: View {
    let task: AgentTask
    @ObservedObject var entry: TerminalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(task.name)
                    .font(.headline)
                Spacer()
                if entry.tmuxUnavailable {
                    Label("tmux not found — sessions won't persist", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(entry.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.bar)

            TerminalRepresentable(task: task, entry: entry)
        }
        .navigationTitle(task.name)
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    let task: AgentTask
    let entry: TerminalEntry

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.autoresizesSubviews = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let terminalView = entry.terminalView

        // Swap in the correct terminal view if it isn't already the active subview
        if container.subviews.first !== terminalView {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(terminalView)
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                terminalView.topAnchor.constraint(equalTo: container.topAnchor),
                terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        guard terminalView.process?.running != true else { return }

        let shell = task.command.isEmpty
            ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash")
            : task.command
        let cwd = task.workingDirectory.path(percentEncoded: false)

        if let tmux = tmuxExecutable() {
            let sessionName = "zeus-\(task.id.uuidString)"
            // -A: attach to existing session if present, otherwise create
            // Providing the shell ensures new sessions start with the user's shell
            terminalView.startProcess(
                executable: tmux,
                args: ["new-session", "-A", "-s", sessionName, shell, "-l"],
                currentDirectory: cwd
            )
        } else {
            entry.tmuxUnavailable = true
            terminalView.startProcess(
                executable: shell,
                args: ["-l"],
                currentDirectory: cwd
            )
        }

        entry.isRunning = true
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }
}

private func tmuxExecutable() -> String? {
    let candidates = [
        "/opt/homebrew/bin/tmux", // Apple Silicon Homebrew
        "/usr/local/bin/tmux",    // Intel Homebrew
        "/usr/bin/tmux",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}
