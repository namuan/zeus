import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers

struct TerminalPane: View {
    let task: AgentTask
    @EnvironmentObject var terminalStore: TerminalStore

    var body: some View {
        logDebug("TerminalPane: rendering for task \(task.name) (\(task.id.uuidString))")
        return TerminalPaneContent(task: task, entry: terminalStore.entry(for: task.id))
            .onAppear {
                logInfo("TerminalPane.onAppear: task=\(task.name), watchMode=\(task.watchMode), cwd='\(task.workingDirectory.path(percentEncoded: false))'")
                terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: task.watchMode, workingDirectory: task.workingDirectory.path(percentEncoded: false))
                terminalStore.clearAttention(taskID: task.id)
            }
            .onChange(of: task.watchMode) { _, newMode in
                logInfo("TerminalPane.onChange watchMode: \(newMode)")
                terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: newMode, workingDirectory: task.workingDirectory.path(percentEncoded: false))
            }
            .onChange(of: task.name) { _, newName in
                logInfo("TerminalPane.onChange name: '\(newName)'")
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
                WindowControlBar(entry: entry, projectID: task.projectID, workingDirectory: task.workingDirectory.path(percentEncoded: false))
                Divider()
            }
            AppLauncherBar(projectID: task.projectID, workingDirectory: task.workingDirectory.path(percentEncoded: false))
            Divider()
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
    let workingDirectory: String
    @EnvironmentObject var db: AppDatabase
    @State private var showCommands = false
    @StateObject private var gitService: GitService
    @State private var showRevertConfirmation = false

    init(entry: TerminalEntry, projectID: UUID, workingDirectory: String) {
        logDebug("WindowControlBar.init: projectID=\(projectID), windows.count=\(entry.windows.count)")
        self.entry = entry
        self.projectID = projectID
        self.workingDirectory = workingDirectory
        _gitService = StateObject(wrappedValue: GitService(workingDirectory: workingDirectory))
    }

    var body: some View {
        HStack(spacing: 6) {
            // Window controls
            Button {
                logInfo("WindowControlBar: + button clicked")
                entry.openWindow()
            } label: {
                Image(systemName: "plus")
            }
            .help("New Window")

            Button {
                logInfo("WindowControlBar: chevron.left button clicked")
                entry.previousWindow()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(entry.windows.count <= 1)
            .help("Previous Window")

            Button {
                logInfo("WindowControlBar: chevron.right button clicked")
                entry.nextWindow()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(entry.windows.count <= 1)
            .help("Next Window")

            Divider().frame(height: 16)

            // Pane controls
            Button {
                logInfo("WindowControlBar: split horizontal button clicked")
                entry.splitHorizontal()
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .help("Split Pane Horizontally")

            Button {
                logInfo("WindowControlBar: split vertical button clicked")
                entry.splitVertical()
            } label: {
                Image(systemName: "rectangle.split.1x2")
            }
            .help("Split Pane Vertically")

            Button {
                logInfo("WindowControlBar: rotate pane button clicked")
                entry.rotatePane()
            } label: {
                Image(systemName: "rectangle.2.swap")
            }
            .disabled(entry.paneCount <= 1)
            .help("Rotate Panes")

            Button {
                logInfo("WindowControlBar: xmark (close) button clicked")
                entry.closeWindow()
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(entry.windows.count <= 1)
            .help("Close Window")

            Divider().frame(height: 16)

            // Quick Commands
            Button {
                logInfo("WindowControlBar: bolt (quick commands) button clicked, showCommands=\(!showCommands)")
                showCommands.toggle()
            } label: {
                Image(systemName: "bolt.fill")
            }
            .help("Quick Commands")
            .popover(isPresented: $showCommands) {
                QuickCommandsPopover(projectID: projectID) { command in
                    logInfo("WindowControlBar: quick command '\(command)' sent, hasActiveProcess=\(entry.hasActiveProcess)")
                    entry.sendCommand(command, inNewVerticalPane: entry.hasActiveProcess)
                    showCommands = false
                }
                .environmentObject(db)
            }

            Divider().frame(height: 16)

            // Git controls
            gitButtons

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
                        Button {
                            logInfo("WindowControlBar: window tab clicked, index=\(window.index), name='\(window.name)'")
                            entry.selectWindow(index: window.index)
                        } label: {
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
        .onAppear {
            logInfo("WindowControlBar.onAppear: fetching git status")
            Task { await gitService.fetchStatus() }
        }
    }

    // MARK: - Git Buttons

    @ViewBuilder
    private var gitButtons: some View {
        // Refresh button
        Button { Task { await gitService.fetchStatus() } } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh Git Status")
        .disabled(gitService.isLoading)

        // Git stats display
        if let stats = gitService.stats {
            // Branch indicator
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                Text(stats.branch)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .help("Current branch: \(stats.branch)")

            // Behind/Ahead indicators
            if stats.hasRemote {
                if stats.behind > 0 {
                    Label("\(stats.behind)", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("\(stats.behind) commits behind remote")
                }
                if stats.ahead > 0 {
                    Label("\(stats.ahead)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .help("\(stats.ahead) commits ahead of remote")
                }
            }

            // Change counts
            if stats.staged > 0 {
                Text("+\(stats.staged)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                    .help("\(stats.staged) staged changes")
            }
            if stats.unstaged > 0 {
                Text("~\(stats.unstaged)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                    .help("\(stats.unstaged) unstaged changes")
            }
            if stats.untracked > 0 {
                Text("?\(stats.untracked)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .help("\(stats.untracked) untracked files")
            }
        } else if gitService.isLoading {
            ProgressView()
                .controlSize(.small)
        }

        if gitService.stats?.hasChanges == true {
            // Revert changes with confirmation
            Button { showRevertConfirmation = true } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Revert All Changes")
            .confirmationDialog(
                "Revert all changes?",
                isPresented: $showRevertConfirmation,
                titleVisibility: .visible
            ) {
                Button("Revert All Changes", role: .destructive) {
                    Task { await gitService.revertAllChanges() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will discard all staged, unstaged, and untracked changes. This cannot be undone.")
            }
        }
    }
}

// MARK: - App Launcher Bar

private struct AppLauncherBar: View {
    let projectID: UUID
    let workingDirectory: String
    @EnvironmentObject var db: AppDatabase

    private var apps: [ProjectApp] {
        db.projectApps(for: projectID)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(apps) { app in
                AppLauncherButton(app: app, workingDirectory: workingDirectory)
                    .contextMenu {
                        Button("Remove \(app.displayName)", role: .destructive) {
                            db.deleteProjectApp(id: app.id)
                        }
                    }
            }
            Button {
                addApp()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .help("Add Application")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.bar)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an application to open with this project"
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let displayName = url.deletingPathExtension().lastPathComponent
        let app = ProjectApp(
            id: UUID(),
            projectID: projectID,
            appPath: url.path,
            displayName: displayName
        )
        db.insertProjectApp(app)
    }
}

private struct AppLauncherButton: View {
    let app: ProjectApp
    let workingDirectory: String

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: app.appPath)
    }

    var body: some View {
        Button {
            let appURL = URL(fileURLWithPath: app.appPath)
            let dirURL = URL(fileURLWithPath: workingDirectory)
            NSWorkspace.shared.open(
                [dirURL],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(app.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .help("Open \(app.displayName)")
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
        logInfo("TerminalRepresentable.makeNSView: creating TerminalContainerView for task \(task.name)")
        return TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        let terminalView = entry.terminalView
        logDebug("TerminalRepresentable.updateNSView: task=\(task.name), process running=\(terminalView.process?.running ?? false)")

        // Swap in the correct terminal view if it isn't already the active subview
        if container.subviews.first !== terminalView {
            logInfo("TerminalRepresentable.updateNSView: swapping terminal view into container")
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

        if terminalView.process?.running == true {
            if let sessionName = container.sessionName, let tmux = tmuxExecutable() {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    logDebug("TerminalRepresentable.updateNSView: ensuring tmux mouse mode is enabled")
                    await runProcessOutput(tmux, args: ["set-option", "-t", sessionName, "mouse", "on"])
                }
            }
            logDebug("TerminalRepresentable.updateNSView: process already running, skipping")
            return
        }

        let shell = task.command.isEmpty
            ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash")
            : task.command
        let cwd = task.workingDirectory.path(percentEncoded: false)
        logInfo("TerminalRepresentable.updateNSView: starting process, shell='\(shell)', cwd='\(cwd)'")

        if let tmux = tmuxExecutable() {
            let sessionName = "zeus-\(task.id.uuidString)"
            container.sessionName = sessionName
            logInfo("TerminalRepresentable.updateNSView: starting tmux session '\(sessionName)'")
            terminalView.startProcess(
                executable: tmux,
                args: ["new-session", "-A", "-s", sessionName, shell, "-l"],
                currentDirectory: cwd
            )
            // Enable mouse mode so clicking switches panes and tmux can handle
            // mouse interactions inside the session.
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                logDebug("TerminalRepresentable.updateNSView: enabling tmux mouse mode")
                await runProcessOutput(tmux, args: ["set-option", "-t", sessionName, "mouse", "on"])
            }
        } else {
            logWarning("TerminalRepresentable.updateNSView: tmux not found, using direct shell")
            entry.tmuxUnavailable = true
            terminalView.startProcess(
                executable: shell,
                args: ["-l"],
                currentDirectory: cwd
            )
        }

        logInfo("TerminalRepresentable.updateNSView: marking entry as running")
        entry.isRunning = true
        Task { @MainActor in
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }
}
