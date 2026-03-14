import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    let task: AgentTask
    @EnvironmentObject var terminalStore: TerminalStore

    var body: some View {
        TerminalPaneContent(task: task, entry: terminalStore.entry(for: task.id))
            .onAppear {
                terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: task.watchMode, workingDirectory: task.workingDirectory.path(percentEncoded: false))
                terminalStore.clearAttention(taskID: task.id)
            }
            .onChange(of: task.watchMode) { _, newMode in
                terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: newMode, workingDirectory: task.workingDirectory.path(percentEncoded: false))
            }
            .onChange(of: task.name) { _, newName in
                terminalStore.updateTaskMetadata(taskID: task.id, name: newName, watchMode: task.watchMode, workingDirectory: task.workingDirectory.path(percentEncoded: false))
            }
    }
}

private struct TerminalPaneContent: View {
    let task: AgentTask
    @ObservedObject var entry: TerminalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !entry.tmuxUnavailable {
                WindowControlBar(entry: entry)
                Divider()
            }
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

private struct WindowControlBar: View {
    @ObservedObject var entry: TerminalEntry

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(entry.windows, id: \.index) { window in
                        Button { entry.selectWindow(index: window.index) } label: {
                            Text(window.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    window.index == entry.currentWindowIndex
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.1)
                                )
                                .foregroundStyle(
                                    window.index == entry.currentWindowIndex
                                        ? Color.white
                                        : Color.primary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider().frame(height: 16)

            Button { entry.openWindow() } label: {
                Image(systemName: "plus")
            }
            .help("New Window")

            Button { entry.previousWindow() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(entry.windows.count <= 1)
            .help("Previous Window")

            Button { entry.nextWindow() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(entry.windows.count <= 1)
            .help("Next Window")

            Divider().frame(height: 16)

            Button { entry.splitHorizontal() } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .help("Split Pane Horizontally")

            Button { entry.splitVertical() } label: {
                Image(systemName: "rectangle.split.1x2")
            }
            .help("Split Pane Vertically")

            Button { entry.rotatePane() } label: {
                Image(systemName: "rectangle.2.swap")
            }
            .disabled(entry.paneCount <= 1)
            .help("Rotate Panes")

            Button { entry.closeWindow() } label: {
                Image(systemName: "xmark")
            }
            .disabled(entry.windows.count <= 1)
            .help("Close Window")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.bar)
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

