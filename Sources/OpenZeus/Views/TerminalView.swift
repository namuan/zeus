import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    let task: AgentTask
    @EnvironmentObject var terminalStore: TerminalStore

    var body: some View {
        TerminalPaneContent(task: task, entry: terminalStore.entry(for: task.id))
            .onAppear {
                terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: task.watchMode)
                terminalStore.clearAttention(taskID: task.id)
            }
            .onChange(of: task.watchMode) { _, newMode in
                terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: newMode)
            }
            .onChange(of: task.name) { _, newName in
                terminalStore.updateTaskMetadata(taskID: task.id, name: newName, watchMode: task.watchMode)
            }
    }
}

private struct TerminalPaneContent: View {
    let task: AgentTask
    @ObservedObject var entry: TerminalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.tmuxUnavailable {
                Label("tmux not found — sessions won't persist", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            TerminalRepresentable(task: task, entry: entry)
        }
        .navigationTitle(task.name)
    }
}

private class TerminalContainerView: NSView {
    override func scrollWheel(with event: NSEvent) {
        subviews.first?.scrollWheel(with: event) ?? super.scrollWheel(with: event)
    }
}

private struct TerminalRepresentable: NSViewRepresentable {
    let task: AgentTask
    let entry: TerminalEntry

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
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
            terminalView.startProcess(
                executable: tmux,
                args: ["new-session", "-A", "-s", sessionName, shell, "-l"],
                currentDirectory: cwd
            )
            // Enable mouse scrolling on the tmux server.
            // Runs after a short delay to ensure the session is ready.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tmux)
                p.arguments = ["set-option", "-g", "mouse", "on"]
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                try? p.run()
            }
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

