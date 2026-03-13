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
                Text(entry.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            currentDirectory: task.workingDirectory.path(percentEncoded: false)
        )
        entry.isRunning = true
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }
}
