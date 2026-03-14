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
                WindowControlBar(entry: entry, projectID: task.projectID)
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
    let projectID: UUID
    @State private var showCommands = false

    var body: some View {
        HStack(spacing: 6) {
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

            Divider().frame(height: 16)

            Button { showCommands.toggle() } label: {
                Image(systemName: "bolt.fill")
            }
            .help("Quick Commands")
            .popover(isPresented: $showCommands) {
                QuickCommandsPopover(projectID: projectID) { command in
                    entry.sendCommand(command)
                    showCommands = false
                }
            }

            Divider().frame(height: 16)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.bar)
        .overlay(alignment: .trailing) {
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
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 10)
        }
    }
}

private class TerminalContainerView: NSView {
    var sessionName: String?
    nonisolated(unsafe) private var scrollAccumulator: CGFloat = 0
    nonisolated(unsafe) private var scrollTimer: Timer?

    // Return self for all hit tests so that scroll events land here
    // instead of being consumed by LocalProcessTerminalView's own scrollWheel
    // (which has no tmux scrollback to operate on).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    // Don't steal keyboard focus — that stays with the terminal subview.
    override var acceptsFirstResponder: Bool { false }

    // Forward click/drag to the terminal so selection works natively.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(subviews.first)
        subviews.first?.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) { subviews.first?.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) { subviews.first?.mouseDragged(with: event) }
    override func rightMouseDown(with event: NSEvent) { subviews.first?.rightMouseDown(with: event) }
    override func rightMouseUp(with event: NSEvent) { subviews.first?.rightMouseUp(with: event) }
    override func otherMouseDown(with event: NSEvent) { subviews.first?.otherMouseDown(with: event) }
    override func mouseMoved(with event: NSEvent) { subviews.first?.mouseMoved(with: event) }

    override func scrollWheel(with event: NSEvent) {
        guard let sessionName, let tmux = tmuxExecutable() else {
            subviews.first?.scrollWheel(with: event) ?? super.scrollWheel(with: event)
            return
        }

        scrollAccumulator += event.scrollingDeltaY
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self else { return }
            let delta = self.scrollAccumulator
            self.scrollAccumulator = 0
            let steps = max(1, Int(abs(delta) / 8))
            let goingUp = delta > 0
            Task {
                if goingUp {
                    await runProcessOutput(tmux, args: ["copy-mode", "-t", sessionName])
                    await runProcessOutput(tmux, args: ["send-keys", "-X", "-N", "\(steps)", "-t", sessionName, "scroll-up"])
                } else {
                    await runProcessOutput(tmux, args: ["send-keys", "-X", "-N", "\(steps)", "-t", sessionName, "scroll-down"])
                }
            }
        }
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
            container.sessionName = sessionName
            terminalView.startProcess(
                executable: tmux,
                args: ["new-session", "-A", "-s", sessionName, shell, "-l"],
                currentDirectory: cwd
            )
            // Disable mouse mode for this session so tmux does not send
            // mouse-tracking escape sequences that would intercept SwiftTerm's
            // native text-selection handlers.
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await runProcessOutput(tmux, args: ["set-option", "-t", sessionName, "mouse", "off"])
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
        Task { @MainActor in
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }
}

