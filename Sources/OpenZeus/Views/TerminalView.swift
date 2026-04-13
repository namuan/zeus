import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers

struct TerminalPane: View {
    let task: AgentTask
    let projectDirectory: String
    let projectName: String
    @EnvironmentObject var terminalStore: TerminalStore

    var body: some View {
        logDebug("TerminalPane: rendering for task \(task.name) (\(task.id.uuidString))")
        return TerminalPaneContent(
            sessionID: task.id,
            projectID: task.projectID,
            command: task.command,
            workingDirectory: task.effectiveWorkingDirectory,
            navigationTitle: task.name,
            entry: terminalStore.entry(for: task.id)
        )
        .onAppear {
            logInfo("TerminalPane.onAppear: task=\(task.name), watchMode=\(task.watchMode), cwd='\(task.effectiveWorkingDirectory)', projectDirectory='\(projectDirectory)'")
            terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: task.watchMode, workingDirectory: task.effectiveWorkingDirectory, projectDirectory: projectDirectory, projectName: projectName)
            terminalStore.clearAttention(taskID: task.id)
        }
        .onChange(of: task.watchMode) { _, newMode in
            logInfo("TerminalPane.onChange watchMode: \(newMode)")
            terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: newMode, workingDirectory: task.effectiveWorkingDirectory, projectDirectory: projectDirectory, projectName: projectName)
        }
        .onChange(of: task.name) { _, newName in
            logInfo("TerminalPane.onChange name: '\(newName)'")
            terminalStore.updateTaskMetadata(taskID: task.id, name: newName, watchMode: task.watchMode, workingDirectory: task.effectiveWorkingDirectory, projectDirectory: projectDirectory, projectName: projectName)
        }
        .onChange(of: task.worktreePath) { _, _ in
            logInfo("TerminalPane.onChange worktreePath: '\(task.effectiveWorkingDirectory)'")
            terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: task.watchMode, workingDirectory: task.effectiveWorkingDirectory, projectDirectory: projectDirectory, projectName: projectName)
        }
    }
}

// Shown when a project is selected but no task is selected.
struct NoTaskDetailPane: View {
    let project: Project
    @EnvironmentObject var terminalStore: TerminalStore

    var body: some View {
        let cwd = project.directoryURL.path(percentEncoded: false)
        return TerminalPaneContent(
            sessionID: project.id,
            projectID: project.id,
            command: "",
            workingDirectory: cwd,
            navigationTitle: project.name,
            entry: terminalStore.entry(for: project.id),
            autoStart: false
        )
        .onAppear {
            terminalStore.updateTaskMetadata(taskID: project.id, name: project.name, watchMode: .off, workingDirectory: cwd, projectDirectory: cwd)
        }
    }
}

private struct TerminalPaneContent: View {
    let sessionID: UUID
    let projectID: UUID
    let command: String
    let workingDirectory: String
    let navigationTitle: String
    @ObservedObject var entry: TerminalEntry
    @State private var terminalVisible: Bool
    @Environment(\.appConfig) private var appConfig

    init(sessionID: UUID, projectID: UUID, command: String, workingDirectory: String,
         navigationTitle: String, entry: TerminalEntry, autoStart: Bool = true) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.command = command
        self.workingDirectory = workingDirectory
        self.navigationTitle = navigationTitle
        self._entry = ObservedObject(wrappedValue: entry)
        self._terminalVisible = State(initialValue: autoStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !entry.tmuxUnavailable {
                WindowControlBar(
                    entry: entry,
                    projectID: projectID,
                    workingDirectory: workingDirectory,
                    terminalVisible: $terminalVisible
                )
                Divider()
            }
            AppLauncherBar(projectID: projectID, workingDirectory: workingDirectory)
            Divider()
            if entry.tmuxUnavailable {
                Label("tmux not found — sessions won't persist", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            if terminalVisible {
                TerminalRepresentable(sessionID: sessionID, command: command, workingDirectory: workingDirectory, entry: entry, terminalConfig: appConfig.terminal)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(navigationTitle)
    }
}

private struct TerminalBarCommand: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let command: String
    var colorName: String

    static let colorNames = [
        "none", "blue", "teal", "green", "orange", "red", "purple", "pink", "brown", "gray"
    ]

    private struct RGB { let r: CGFloat; let g: CGFloat; let b: CGFloat }

    private static let colorMap: [String: RGB] = [
        "blue": RGB(r: 0.65, g: 0.80, b: 0.94),
        "teal": RGB(r: 0.60, g: 0.85, b: 0.82),
        "green": RGB(r: 0.62, g: 0.85, b: 0.62),
        "orange": RGB(r: 0.96, g: 0.80, b: 0.55),
        "red": RGB(r: 0.94, g: 0.68, b: 0.68),
        "purple": RGB(r: 0.80, g: 0.70, b: 0.92),
        "pink": RGB(r: 0.92, g: 0.72, b: 0.82),
        "brown": RGB(r: 0.82, g: 0.74, b: 0.62),
        "gray": RGB(r: 0.80, g: 0.80, b: 0.80)
    ]

    static func displayColor(for colorName: String) -> SwiftUI.Color {
        guard let c = colorMap[colorName] else { return SwiftUI.Color.primary.opacity(0.1) }
        return SwiftUI.Color(nsColor: NSColor(calibratedRed: c.r, green: c.g, blue: c.b, alpha: 1))
    }

    var displayColor: SwiftUI.Color { Self.displayColor(for: colorName) }
}

private enum TerminalBarCommandEditorTarget: Equatable {
    case addButton
    case command(UUID)
}

private struct TerminalBarCommandEditorState: Equatable {
    var target: TerminalBarCommandEditorTarget
    var commandID: UUID?
    var name: String
    var command: String
    var colorName: String
}

private struct WindowControlBar: View {
    private static let defaultTerminalBarCommands: [TerminalBarCommand] = []
    private static let terminalBarCommandsStorageKey = "terminalBarCommands"

    @ObservedObject var entry: TerminalEntry
    let projectID: UUID
    let workingDirectory: String
    @Binding var terminalVisible: Bool
    @EnvironmentObject var db: AppDatabase
    @Environment(\.appConfig) private var appConfig
    @State private var showCommands = false
    @State private var terminalBarCommandEditor: TerminalBarCommandEditorState?
    @State private var terminalBarCommands: [TerminalBarCommand]

    init(entry: TerminalEntry, projectID: UUID, workingDirectory: String, terminalVisible: Binding<Bool>) {
        logDebug("WindowControlBar.init: projectID=\(projectID), windows.count=\(entry.windows.count)")
        self._entry = ObservedObject(wrappedValue: entry)
        self.projectID = projectID
        self.workingDirectory = workingDirectory
        self._terminalVisible = terminalVisible
        self._terminalBarCommands = State(initialValue: Self.loadTerminalBarCommands(for: projectID))
    }

    var body: some View {
        HStack(spacing: 6) {
            terminalControls
            Divider().frame(height: 16)
            terminalBarCommandControls
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.bar)
        .overlay(alignment: .trailing) {
            HStack(spacing: 6) {
                GitControlsView(workingDirectory: workingDirectory, gitConfig: appConfig.git)
                    .id(workingDirectory)
                Divider().frame(height: 16)
                windowTabs
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 10)
        }
    }

    @ViewBuilder
    private var terminalControls: some View {
        Button {
            logInfo("WindowControlBar: + button clicked, terminalVisible=\(terminalVisible)")
            if terminalVisible {
                entry.openWindow()
            } else {
                terminalVisible = true
            }
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
    }

    private var terminalBarCommandControls: some View {
        HStack(spacing: 4) {
            ForEach(terminalBarCommands) { savedCommand in
                Button {
                    logInfo("WindowControlBar: terminal bar command '\(savedCommand.command)' sent")
                    entry.sendCommand(savedCommand.command)
                } label: {
                    Text(savedCommand.name)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(savedCommand.displayColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .help(savedCommand.command)
                .popover(isPresented: editorBinding(for: .command(savedCommand.id))) { editorPopoverContent(commandID: savedCommand.id) }
                .contextMenu {
                    Button("Edit") {
                        beginEditing(savedCommand)
                    }
                    Button("Delete", role: .destructive) {
                        deleteTerminalBarCommand(savedCommand.id)
                    }
                }
            }

            Button {
                beginAdding()
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .help("Add terminal bar command")
            .popover(isPresented: editorBinding(for: .addButton)) { editorPopoverContent(commandID: nil) }
        }
    }

    @ViewBuilder
    private func editorPopoverContent(commandID: UUID?) -> some View {
        if let editor = activeEditor(for: commandID) {
            TerminalBarCommandEditorPopover(
                initialName: editor.name,
                initialCommand: editor.command,
                initialColorName: editor.colorName
            ) { name, command, colorName in
                saveTerminalBarCommand(name: name, command: command, colorName: colorName, editingID: editor.commandID)
                terminalBarCommandEditor = nil
            } onCancel: {
                terminalBarCommandEditor = nil
            }
        }
    }

    private func activeEditor(for commandID: UUID?) -> TerminalBarCommandEditorState? {
        guard let editor = terminalBarCommandEditor else { return nil }
        return editor.commandID == commandID ? editor : nil
    }

    private func editorBinding(for target: TerminalBarCommandEditorTarget) -> Binding<Bool> {
        Binding(
            get: { terminalBarCommandEditor?.target == target },
            set: { isPresented in
                if !isPresented, terminalBarCommandEditor?.target == target {
                    terminalBarCommandEditor = nil
                }
            }
        )
    }

    private func beginAdding() {
        terminalBarCommandEditor = TerminalBarCommandEditorState(
            target: .addButton,
            commandID: nil,
            name: "",
            command: "",
            colorName: "none"
        )
    }

    private func beginEditing(_ command: TerminalBarCommand) {
        terminalBarCommandEditor = TerminalBarCommandEditorState(
            target: .command(command.id),
            commandID: command.id,
            name: command.name,
            command: command.command,
            colorName: command.colorName
        )
    }

    private func saveTerminalBarCommand(name: String, command: String, colorName: String, editingID: UUID?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else { return }

        let updatedCommands: [TerminalBarCommand]
        if let editingID,
           let index = terminalBarCommands.firstIndex(where: { $0.id == editingID }) {
            var commands = terminalBarCommands
            commands[index] = TerminalBarCommand(id: editingID, name: trimmedName, command: trimmedCommand, colorName: colorName)
            updatedCommands = commands
        } else {
            updatedCommands = terminalBarCommands + [TerminalBarCommand(id: UUID(), name: trimmedName, command: trimmedCommand, colorName: colorName)]
        }
        terminalBarCommands = updatedCommands
        Self.saveTerminalBarCommands(updatedCommands)
    }

    private func deleteTerminalBarCommand(_ id: UUID) {
        let updatedCommands = terminalBarCommands.filter { $0.id != id }
        terminalBarCommands = updatedCommands
        Self.saveTerminalBarCommands(updatedCommands)
    }

    private static func legacyTerminalBarCommandsStorageKey(for projectID: UUID) -> String {
        "terminalBarCommands.\(projectID.uuidString)"
    }

    private static func loadTerminalBarCommands(for projectID: UUID) -> [TerminalBarCommand] {
        if let commands = loadTerminalBarCommands(forKey: terminalBarCommandsStorageKey) {
            return commands
        }

        let legacyKey = legacyTerminalBarCommandsStorageKey(for: projectID)
        guard let commands = loadTerminalBarCommands(forKey: legacyKey) else {
            return defaultTerminalBarCommands
        }

        saveTerminalBarCommands(commands)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return commands
    }

    private static func loadTerminalBarCommands(forKey key: String) -> [TerminalBarCommand]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([TerminalBarCommand].self, from: data)
    }

    private static func saveTerminalBarCommands(_ commands: [TerminalBarCommand]) {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        UserDefaults.standard.set(data, forKey: terminalBarCommandsStorageKey)
    }

    private var windowTabs: some View {
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
    }
}

private struct TerminalBarCommandEditorPopover: View {
    let initialName: String
    let initialCommand: String
    let initialColorName: String
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    @Environment(\.appConfig) private var appConfig
    @State private var name = ""
    @State private var command = ""
    @State private var selectedColorName = "none"
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case command
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            TextField("Command name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)

            TextField("Actual command", text: $command)
                .textFieldStyle(.roundedBorder)
                .fontDesign(.monospaced)
                .focused($focusedField, equals: .command)
                .onSubmit(save)

            CommandVariablesHelpText()

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 5), spacing: 6) {
                    ForEach(TerminalBarCommand.colorNames, id: \.self) { colorName in
                        let color = TerminalBarCommand.displayColor(for: colorName)
                        Button {
                            selectedColorName = colorName
                        } label: {
                            Circle()
                                .fill(colorName == "none" ? Color.primary.opacity(0.1) : color)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.primary.opacity(selectedColorName == colorName ? 0.6 : 0), lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(colorName.capitalized)
                    }
                }
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(trimmedName.isEmpty || trimmedCommand.isEmpty)
            }
        }
        .padding(24)
        .frame(width: min(CGFloat(appConfig.ui.quickCommandsWidth), 360))
        .onAppear {
            name = initialName
            command = initialCommand
            selectedColorName = initialColorName
            focusedField = .name
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else { return }
        onSave(trimmedName, trimmedCommand, selectedColorName)
    }
}

// MARK: - Git controls (shared)

private struct GitControlsView: View {
    @StateObject private var gitService: GitService
    @State private var showRevertConfirmation = false
    @State private var showChangesPopover = false

    init(workingDirectory: String, gitConfig: GitConfig = .init()) {
        _gitService = StateObject(wrappedValue: GitService(
            workingDirectory: workingDirectory,
            gitExecutablePath: gitConfig.executablePath,
            statusDebounceMs: gitConfig.statusDebounceMs,
            statusPollIntervalSeconds: gitConfig.statusPollIntervalSeconds
        ))
    }

    var body: some View {
        HStack(spacing: 3) {
            gitButtons
        }
        .animation(.easeInOut(duration: 0.2), value: gitService.stats)
        .onAppear {
            logInfo("GitControlsView.onAppear: fetching git status")
            Task { await gitService.fetchStatus() }
            gitService.startWatching()
        }
        .onDisappear {
            gitService.stopWatching()
        }
        .popover(isPresented: $showChangesPopover, arrowEdge: .bottom) {
            GitChangesPopover(
                files: gitService.changedFiles,
                unpushedFiles: gitService.unpushedFiles,
                fetchDiff: { path, staged, untracked, unpushed in
                    await gitService.fetchDiff(path: path, staged: staged, untracked: untracked, unpushed: unpushed)
                },
                revertFile: { path, kind in
                    switch kind {
                    case .staged:   _ = await gitService.unstageFile(path: path)
                    case .unstaged: _ = await gitService.discardFileChanges(path: path)
                    case .untracked: _ = await gitService.removeUntrackedFile(path: path)
                    case .unpushed: break
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var gitButtons: some View {
        Button { Task { await gitService.fetchStatus() } } label: {
            Image(systemName: "arrow.clockwise")
        }
        .help("Refresh Git Status")
        .disabled(gitService.isLoading)

        if let stats = gitService.stats {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                Text(stats.branch)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .help("Current branch: \(stats.branch)")
            .transition(.opacity)

            if stats.ahead > 0 {
                Button { showChangesPopover.toggle() } label: {
                    statusBadge("\(stats.ahead)", systemImage: "arrow.up", color: .blue)
                }
                .buttonStyle(.plain)
                .help(stats.aheadLabel)
                .transition(.opacity)
            }
            if stats.hasRemote && stats.behind > 0 {
                statusBadge("\(stats.behind)", systemImage: "arrow.down", color: .orange)
                    .help("\(stats.behind) commits behind remote")
                    .transition(.opacity)
            }

            if stats.hasChanges {
                Button { showChangesPopover.toggle() } label: {
                    HStack(spacing: 4) {
                        if stats.staged > 0 {
                            changeCountBadge("+\(stats.staged)", color: .green)
                        }
                        if stats.unstaged > 0 {
                            changeCountBadge("~\(stats.unstaged)", color: .orange)
                        }
                        if stats.untracked > 0 {
                            changeCountBadge("?\(stats.untracked)", color: .secondary)
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Show changed files")
                .transition(.opacity)
            }
        } else if gitService.isLoading {
            ProgressView()
                .controlSize(.small)
                .transition(.opacity)
        }

        if gitService.stats?.hasChanges == true {
            Button { showRevertConfirmation = true } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Revert All Changes")
            .transition(.opacity)
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

    private func changeCountBadge(_ text: String, color: SwiftUI.Color) -> some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(color.opacity(0.18))
            }
    }

    private func statusBadge(_ text: String, systemImage: String, color: SwiftUI.Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(color.opacity(0.18))
            }
    }
}

private enum DiffKind { case staged, unstaged, untracked, unpushed }

private struct GitChangesPopover: View {
    let files: [GitFileChange]
    let unpushedFiles: [GitFileChange]
    let fetchDiff: (String, Bool, Bool, Bool) async -> String
    let revertFile: (String, DiffKind) async -> Void

    private var staged: [GitFileChange] { files.filter { $0.isStaged } }
    private var unstaged: [GitFileChange] { files.filter { $0.isUnstaged } }
    private var untracked: [GitFileChange] { files.filter { $0.isUntracked } }

    // All files start expanded. Toggling a file adds/removes it from this set.
    @State private var collapsedFiles: Set<String> = []
    @State private var loadingFiles: Set<String> = []
    @State private var diffs: [String: String] = [:]
    @State private var diffTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingRevert: (file: GitFileChange, kind: DiffKind)?

    private var allKeys: [String] {
        staged.map { diffKey($0.path, .staged) } +
        unstaged.map { diffKey($0.path, .unstaged) } +
        untracked.map { diffKey($0.path, .untracked) } +
        unpushedFiles.map { diffKey($0.path, .unpushed) }
    }

    private var allCollapsed: Bool {
        let keys = allKeys
        return !keys.isEmpty && keys.allSatisfy { collapsedFiles.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Spacer()
                Button {
                    if allCollapsed {
                        collapsedFiles.removeAll()
                    } else {
                        collapsedFiles.formUnion(allKeys)
                    }
                } label: {
                    Label(
                        allCollapsed ? "Expand All" : "Collapse All",
                        systemImage: allCollapsed ? "chevron.down.2" : "chevron.up.2"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !staged.isEmpty {
                        section(title: "Staged", color: .blue, files: staged, kind: .staged) { $0.stagedLabel }
                    }
                    if !unstaged.isEmpty {
                        section(title: "Unstaged", color: .yellow, files: unstaged, kind: .unstaged) { $0.unstagedLabel }
                    }
                    if !untracked.isEmpty {
                        section(title: "Untracked", color: .secondary, files: untracked, kind: .untracked) { _ in "untracked" }
                    }
                    if !unpushedFiles.isEmpty {
                        section(title: "Not Pushed", color: .purple, files: unpushedFiles, kind: .unpushed) { $0.stagedLabel }
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 600, idealWidth: 750, maxWidth: 1100, minHeight: 400, idealHeight: 700, maxHeight: 1000)
        .onAppear { fetchAllDiffs() }
        .onDisappear {
            diffTasks.values.forEach { $0.cancel() }
            diffTasks.removeAll()
        }
        .confirmationDialog(
            pendingRevert.map { confirmationStrings(for: $0.kind).title } ?? "Confirm",
            isPresented: Binding(
                get: { pendingRevert != nil },
                set: { if !$0 { pendingRevert = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingRevert {
                Button(confirmationStrings(for: pending.kind).action, role: .destructive) {
                    Task {
                        await revertFile(pending.file.path, pending.kind)
                        pendingRevert = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingRevert = nil }
            }
        } message: {
            if let pending = pendingRevert {
                Text(pending.file.path)
            }
        }
    }

    private func confirmationStrings(for kind: DiffKind) -> (title: String, action: String) {
        switch kind {
        case .unstaged: return ("Discard changes?", "Discard Changes")
        case .untracked: return ("Delete file?", "Delete File")
        default: return ("Confirm", "Confirm")
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        color: SwiftUI.Color,
        files: [GitFileChange],
        kind: DiffKind,
        label: @escaping (GitFileChange) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            ForEach(files) { file in
                fileRow(file: file, color: color, kind: kind, label: label(file))
            }
        }
    }

    /// Returns the dictionary key used for `diffs`, `loadingFiles`, and `diffTasks`.
    /// Unpushed entries use a prefixed key to avoid collision with working-tree entries
    /// for the same path.
    private func diffKey(_ path: String, _ kind: DiffKind) -> String {
        kind == .unpushed ? "unpushed:\(path)" : path
    }

    @ViewBuilder
    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func revertButton(file: GitFileChange, kind: DiffKind) -> some View {
        switch kind {
        case .staged:
            iconButton(systemName: "minus.circle", help: "Unstage file") {
                Task { await revertFile(file.path, kind) }
            }
        case .unstaged:
            iconButton(systemName: "arrow.uturn.backward.circle", help: "Discard changes") {
                pendingRevert = (file, kind)
            }
        case .untracked:
            iconButton(systemName: "trash", help: "Delete file") {
                pendingRevert = (file, kind)
            }
        case .unpushed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fileRow(file: GitFileChange, color: SwiftUI.Color, kind: DiffKind, label: String) -> some View {
        let key         = diffKey(file.path, kind)
        let isCollapsed = collapsedFiles.contains(key)
        let isLoading   = loadingFiles.contains(key)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                if isCollapsed {
                    collapsedFiles.remove(key)
                } else {
                    collapsedFiles.insert(key)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10, alignment: .center)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color.opacity(0.18))
                        }
                    Text(file.path)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    revertButton(file: file, kind: kind)
                        .padding(.trailing, 4)
                }
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading diff…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
                } else if let diff = diffs[key] {
                    if diff.isEmpty {
                        Text("No diff available")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                            .padding(.vertical, 4)
                    } else {
                        DiffContentView(text: diff)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func fetchAllDiffs() {
        let work: [(path: String, kind: DiffKind)] =
            staged.map { ($0.path, .staged) } +
            unstaged.map { ($0.path, .unstaged) } +
            untracked.map { ($0.path, .untracked) } +
            unpushedFiles.map { ($0.path, .unpushed) }

        for item in work {
            let key = diffKey(item.path, item.kind)
            guard diffs[key] == nil && diffTasks[key] == nil else { continue }
            loadingFiles.insert(key)
            diffTasks[key] = Task {
                let diff = await fetchDiff(
                    item.path,
                    item.kind == .staged,
                    item.kind == .untracked,
                    item.kind == .unpushed
                )
                guard !Task.isCancelled else { return }
                diffs[key] = diff
                loadingFiles.remove(key)
                diffTasks.removeValue(forKey: key)
            }
        }
    }
}

private struct DiffContentView: View {
    let text: String

    private enum DiffLineKind {
        case added, removed, hunk, header, comment, context

        init(_ line: String) {
            if line.hasPrefix("#") { self = .comment; return }
            if line.hasPrefix("+++") || line.hasPrefix("---") ||
               line.hasPrefix("diff ") || line.hasPrefix("index ") ||
               line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                self = .header; return
            }
            if line.hasPrefix("+") { self = .added; return }
            if line.hasPrefix("-") { self = .removed; return }
            if line.hasPrefix("@@") { self = .hunk; return }
            self = .context
        }

        var foreground: SwiftUI.Color {
            switch self {
            case .added:   return SwiftUI.Color(nsColor: .systemGreen)
            case .removed: return SwiftUI.Color(nsColor: .systemRed)
            case .hunk:    return SwiftUI.Color(nsColor: .systemBlue)
            case .header, .comment: return .secondary
            case .context: return .primary
            }
        }

        var background: SwiftUI.Color {
            switch self {
            case .added:   return SwiftUI.Color(nsColor: .systemGreen).opacity(0.08)
            case .removed: return SwiftUI.Color(nsColor: .systemRed).opacity(0.08)
            case .hunk:    return SwiftUI.Color(nsColor: .systemBlue).opacity(0.08)
            default:       return .clear
            }
        }
    }

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let kind = DiffLineKind(line)
                Text(verbatim: line.isEmpty ? " " : line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(kind.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(kind.background)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
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
                        if app.isGlobal {
                            Button {
                                db.demoteProjectAppToLocal(id: app.id, projectID: projectID)
                            } label: {
                                Label("Demote to Local", systemImage: "pin")
                            }
                        } else {
                            Button {
                                db.promoteProjectAppToGlobal(id: app.id)
                            } label: {
                                Label("Promote to Global", systemImage: "globe")
                            }
                        }
                        Divider()
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
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                    if app.isGlobal {
                        Image(systemName: "globe")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                            )
                            .offset(x: 3, y: 3)
                    }
                }
                .frame(width: 17, height: 17)
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
    var terminalConfig: TerminalConfig = .init()
    nonisolated(unsafe) private var scrollAccumulator: CGFloat = 0
    nonisolated(unsafe) private var scrollTimer: Timer?
    nonisolated(unsafe) private var didSelectionDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        didSelectionDrag = false
        window?.makeFirstResponder(subviews.first)
        subviews.first?.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        subviews.first?.mouseUp(with: event)
        if didSelectionDrag, let terminalView = subviews.first as? TerminalView {
            logInfo("Auto-copying terminal selection to clipboard")
            terminalView.copy(self)
        }
        didSelectionDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        didSelectionDrag = true
        subviews.first?.mouseDragged(with: event)
    }
    override func mouseMoved(with event: NSEvent) { subviews.first?.mouseMoved(with: event) }

    override func scrollWheel(with event: NSEvent) {
        guard let sessionName, let tmux = tmuxExecutable(searchPaths: terminalConfig.tmuxSearchPaths) else {
            subviews.first?.scrollWheel(with: event) ?? super.scrollWheel(with: event)
            return
        }

        scrollAccumulator += event.scrollingDeltaY
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: terminalConfig.scrollTimerIntervalSeconds, repeats: false) { [weak self] _ in
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
    let sessionID: UUID
    let command: String
    let workingDirectory: String
    @ObservedObject var entry: TerminalEntry
    let terminalConfig: TerminalConfig

    func makeNSView(context: Context) -> TerminalContainerView {
        logInfo("TerminalRepresentable.makeNSView: creating TerminalContainerView for session \(sessionID)")
        return TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.terminalConfig = terminalConfig
        let terminalView = entry.terminalView
        logDebug("TerminalRepresentable.updateNSView: session=\(sessionID), process running=\(terminalView.process?.running ?? false)")

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

        logDebug("Syncing allowMouseReporting=\(entry.mouseReportingEnabled)")
        terminalView.allowMouseReporting = entry.mouseReportingEnabled

        if terminalView.process?.running == true {
            if let sessionName = container.sessionName, let tmux = tmuxExecutable(searchPaths: terminalConfig.tmuxSearchPaths) {
                Task {
                    try? await Task.sleep(for: .milliseconds(terminalConfig.mouseModeDelayMs))
                    logDebug("TerminalRepresentable.updateNSView: ensuring tmux mouse mode is enabled")
                    await runProcessOutput(tmux, args: ["set-option", "-t", sessionName, "mouse", "on"])
                }
            }
            logDebug("TerminalRepresentable.updateNSView: process already running, skipping")
            return
        }

        let shell = command.isEmpty ? terminalConfig.resolvedShell : command
        logInfo("TerminalRepresentable.updateNSView: starting process, shell='\(shell)', cwd='\(workingDirectory)'")

        if let tmux = tmuxExecutable(searchPaths: terminalConfig.tmuxSearchPaths) {
            let sessionName = "\(terminalConfig.tmuxSessionPrefix)\(sessionID.uuidString)"
            container.sessionName = sessionName
            logInfo("TerminalRepresentable.updateNSView: starting tmux session '\(sessionName)'")
            terminalView.startProcess(
                executable: tmux,
                args: ["new-session", "-A", "-s", sessionName, shell, "-l"],
                currentDirectory: workingDirectory
            )
            Task {
                try? await Task.sleep(for: .milliseconds(terminalConfig.mouseModeDelayMs))
                logDebug("TerminalRepresentable.updateNSView: enabling tmux mouse mode")
                await runProcessOutput(tmux, args: ["set-option", "-t", sessionName, "mouse", "on"])
            }
        } else {
            logWarning("TerminalRepresentable.updateNSView: tmux not found, using direct shell")
            entry.tmuxUnavailable = true
            terminalView.startProcess(
                executable: shell,
                args: ["-l"],
                currentDirectory: workingDirectory
            )
        }

        logInfo("TerminalRepresentable.updateNSView: marking entry as running")
        entry.isRunning = true
        Task { @MainActor in
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }
}
