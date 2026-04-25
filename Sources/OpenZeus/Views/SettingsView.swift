import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config: AppConfig
    @State private var saveTask: Task<Void, Never>?

    init() {
        _config = State(initialValue: AppConfig.load())
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                TerminalTab(config: $config.terminal)
                    .tabItem { Label("Terminal", systemImage: "terminal") }

                NotificationsTab(config: $config.notifications)
                    .tabItem { Label("Notifications", systemImage: "bell") }

                GitTab(config: $config.git)
                    .tabItem { Label("Git", systemImage: "arrow.triangle.branch") }

                WorktreeTab(
                    config: $config.worktree,
                    terminalConfig: config.terminal,
                    gitExecutablePath: config.git.executablePath
                )
                .tabItem { Label("Worktree", systemImage: "square.split.2x1") }

                InterfaceTab(config: $config.ui)
                    .tabItem { Label("Interface", systemImage: "sidebar.left") }

                DataTab(storage: $config.storage, logging: $config.logging)
                    .tabItem { Label("Data", systemImage: "externaldrive") }

                LLMTab(config: $config.llm)
                    .tabItem { Label("LLM", systemImage: "sparkles") }
            }
            .frame(width: 500, height: 480)
        }
        .background {
            Button(action: { dismiss() }) { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityHidden(true)
        }
        .onAppear {
            config = AppConfig.load()
        }
        .onChange(of: config) { _, newConfig in
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                newConfig.save()
                NotificationCenter.default.post(name: .appConfigChanged, object: nil)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            config.save()
            NotificationCenter.default.post(name: .appConfigChanged, object: nil)
        }
    }
}

// MARK: - Terminal

private struct TerminalTab: View {
    @Binding var config: TerminalConfig

    private static let fontWeights = [
        "ultralight", "thin", "light", "regular",
        "medium", "semibold", "bold", "heavy", "black",
    ]

    var body: some View {
        Form {
            Section("Font") {
                TextField("Family", text: $config.fontFamily)
                    .help("\"monospacedSystemFont\" for the system default, or a PostScript name like \"JetBrainsMono-Regular\".")

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: $config.fontSize, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("", value: $config.fontSize, in: 8...72)
                        .labelsHidden()
                }

                Picker("Weight", selection: $config.fontWeight) {
                    ForEach(Self.fontWeights, id: \.self) {
                        Text($0.capitalized).tag($0)
                    }
                }
            }

            Section("Shell") {
                TextField("Default shell (empty = $SHELL)", text: $config.defaultShell)
                    .help("Empty uses $SHELL, falling back to /bin/bash.")
            }

            Section("Timing") {
                DoubleRow("Poll interval", value: $config.pollIntervalSeconds, unit: "s")
                    .help("How often to check each tmux session for an active process.")
                IntFieldRow("Tmux settle delay", value: $config.tmuxSettleDelayMs, unit: "ms")
                    .help("Wait after tmux window/pane operations before refreshing state.")
                DoubleRow("Scroll timer interval", value: $config.scrollTimerIntervalSeconds, unit: "s")
                IntFieldRow("Mouse mode delay", value: $config.mouseModeDelayMs, unit: "ms")
                IntFieldRow("SIGTERM grace period", value: $config.sigtermGracePeriodMs, unit: "ms")
                DoubleRow("Orphan cleanup interval", value: $config.orphanCleanupIntervalSeconds, unit: "s")
                    .help("How often to scan for and kill orphaned tmux sessions.")
            }

            Section("Tmux") {
                TextField("Session prefix", text: $config.tmuxSessionPrefix)
                    .help("Prefix for tmux session names (e.g. \"zeus-<task-uuid>\").")
                TextField("pkill path", text: $config.pkillPath)
                ArrayField("Search paths", array: $config.tmuxSearchPaths)
            }

            Section("Process Detection") {
                ArrayField("Known shells", array: $config.knownShells)
                    .help("Process names considered idle. One per line.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @Binding var config: NotificationConfig

    private static let systemSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi",
        "Submarine", "Tink",
    ]

    var body: some View {
        Form {
            Section("Alert Sound") {
                Picker("Sound", selection: $config.soundName) {
                    ForEach(Self.systemSounds, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Custom…").tag(config.soundName).opacity(
                        Self.systemSounds.contains(config.soundName) ? 0 : 1
                    )
                }
                if !Self.systemSounds.contains(config.soundName) {
                    TextField("Sound name", text: $config.soundName)
                }
                HStack {
                    Spacer()
                    Button("Preview") { NSSound(named: config.soundName)?.play() }
                }
            }

            Section("Notification Content") {
                TextField("Title", text: $config.notificationTitle)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Body template", text: $config.notificationBodyTemplate)
                    Text("Use {taskName} as a placeholder for the task's name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Git

private struct GitTab: View {
    @Binding var config: GitConfig

    var body: some View {
        Form {
            Section("Executable") {
                TextField("Path", text: $config.executablePath)
                HStack {
                    Spacer()
                    Button("Browse…") { browseForExecutable() }
                }
            }

            Section("Auto-refresh") {
                LabeledContent("Debounce delay") {
                    HStack(spacing: 4) {
                        TextField("", value: $config.statusDebounceMs, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("ms")
                            .foregroundStyle(.secondary)
                    }
                }
                .help("How long to wait after a file-system change before refreshing git status. Lower values feel more responsive but may cause extra git calls during rapid writes.")

                LabeledContent("Remote poll interval") {
                    HStack(spacing: 4) {
                        TextField("", value: $config.statusPollIntervalSeconds, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
                }
                .help("How often to poll for remote ahead/behind counts. File-system watching cannot detect remote changes, so this slow poll keeps that info fresh.")

                Text("Local changes (staged, unstaged, untracked) are detected instantly via file-system events. Only remote tracking requires periodic polling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func browseForExecutable() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/bin")
        panel.message = "Choose the git executable"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            config.executablePath = url.path
        }
    }
}

// MARK: - Worktree

private struct WorktreeTab: View {
    @EnvironmentObject private var appDatabase: AppDatabase
    @Binding var config: WorktreeConfig
    let terminalConfig: TerminalConfig
    let gitExecutablePath: String

    @State private var cleanupItems: [CleanupItem] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var removingIDs: Set<UUID> = []

    var body: some View {
        Form {
            Section("Base Directory") {
                HStack {
                    TextField("Path (e.g. ~/worktrees)", text: $config.basePath)
                        .help("Root folder where all task worktrees are created. Supports ~ for home directory.")
                    Button("Browse…") { browseForDirectory() }
                }
                Text("Worktrees are placed at {path}/{project}/{task-uuid}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Branching") {
                TextField("Base branch", text: $config.defaultBaseBranch)
                    .help("Branch to base new task branches on (e.g. main, develop).")
                Text("New branches are named task-{short-id}-{slug}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Toggle("Create worktree for new tasks", isOn: $config.createByDefault)
                    .help("When enabled, the New Task dialog will have 'Create Git worktree' checked by default.")
            }

            if config.basePath.isEmpty {
                Section {
                    Label {
                        Text("Set a base directory above to enable worktree creation when adding tasks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                }
            }

            Section {
                HStack {
                    Text("Scan for orphaned worktrees and tmux sessions no longer tied to any task.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await scan() }
                    } label: {
                        if isScanning {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Scanning…")
                            }
                        } else {
                            Label(hasScanned ? "Re-scan" : "Scan", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(isScanning)
                }

                if hasScanned {
                    if cleanupItems.isEmpty {
                        Label("Nothing to clean up.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        ForEach(cleanupItems) { item in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.title)
                                            .font(.callout)
                                            .fontWeight(.medium)
                                        Text(item.tagLabel)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(item.tagColor.opacity(0.15))
                                            .foregroundStyle(item.tagColor)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(item.detail)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("Remove") {
                                    Task { await removeItem(item) }
                                }
                                .controlSize(.small)
                                .disabled(removingIDs.contains(item.id))
                            }
                            .padding(.vertical, 2)
                        }

                        HStack {
                            Text("\(cleanupItems.count) item\(cleanupItems.count == 1 ? "" : "s") found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove All") {
                                Task {
                                    for item in cleanupItems { await removeItem(item) }
                                }
                            }
                            .controlSize(.small)
                            .disabled(!removingIDs.isEmpty)
                        }
                    }
                }
            } header: {
                Text("Cleanup")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Browse

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose the worktree base directory"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            config.basePath = url.path
        }
    }

    // MARK: - Scan

    private func scan() async {
        isScanning = true
        var found: [CleanupItem] = []

        if let tmux = tmuxExecutable(searchPaths: terminalConfig.tmuxSearchPaths) {
            let output = await runProcessOutput(tmux, args: ["list-sessions", "-F", "#{session_name}"])
            let prefix = terminalConfig.tmuxSessionPrefix
            let knownIDs = Set(appDatabase.tasks.lazy.map { $0.id })
            for line in output.components(separatedBy: .newlines) {
                let session = line.trimmingCharacters(in: .whitespaces)
                guard session.hasPrefix(prefix) else { continue }
                let uuidString = String(session.dropFirst(prefix.count))
                guard let uuid = UUID(uuidString: uuidString) else { continue }
                guard !knownIDs.contains(uuid) else { continue }
                found.append(CleanupItem(
                    kind: .orphanedTmuxSession(sessionName: session),
                    title: "Orphaned tmux session",
                    detail: session,
                    reason: "No task with ID \(uuidString.prefix(8))… exists in the database"
                ))
            }
        }

        for task in appDatabase.tasks {
            guard let path = task.worktreePath else { continue }
            if task.isArchived {
                if FileManager.default.fileExists(atPath: path) {
                    found.append(CleanupItem(
                        kind: .archivedTaskWithWorktree(task: task),
                        title: "Archived task with live worktree",
                        detail: path,
                        reason: "Task \"\(task.name)\" is archived but its worktree still exists on disk"
                    ))
                }
            } else {
                if !FileManager.default.fileExists(atPath: path) {
                    found.append(CleanupItem(
                        kind: .staleWorktreeReference(task: task),
                        title: "Stale worktree reference",
                        detail: path,
                        reason: "Task \"\(task.name)\" references a worktree path that no longer exists on disk"
                    ))
                }
            }
        }

        cleanupItems = found
        isScanning = false
        hasScanned = true
    }

    // MARK: - Remove

    private func removeItem(_ item: CleanupItem) async {
        removingIDs.insert(item.id)
        defer {
            removingIDs.remove(item.id)
            cleanupItems.removeAll { $0.id == item.id }
        }

        switch item.kind {
        case .orphanedTmuxSession(let sessionName):
            if let tmux = tmuxExecutable(searchPaths: terminalConfig.tmuxSearchPaths) {
                await terminateSessionProcesses(
                    sessionName: sessionName,
                    tmux: tmux,
                    pkillPath: terminalConfig.pkillPath,
                    sigtermGracePeriodMs: terminalConfig.sigtermGracePeriodMs
                )
                await runProcessOutput(tmux, args: ["kill-session", "-t", sessionName])
            }

        case .archivedTaskWithWorktree(let task):
            guard let path = task.worktreePath, let branch = task.worktreeBranch else { break }
            let repoPath = task.workingDirectory.path(percentEncoded: false)
            let service = WorktreeService(gitExecutablePath: gitExecutablePath)
            await service.removeWorktree(worktreePath: path, repoPath: repoPath, branchName: branch)
            var updated = task
            updated.worktreePath = nil
            updated.worktreeBranch = nil
            appDatabase.updateTask(updated)

        case .staleWorktreeReference(let task):
            var updated = task
            updated.worktreePath = nil
            updated.worktreeBranch = nil
            appDatabase.updateTask(updated)
        }
    }
}

// MARK: - Interface

private struct InterfaceTab: View {
    @Binding var config: UIConfig

    var body: some View {
        Form {
            Section("Project Sidebar") {
                IntRow("Minimum width", value: $config.projectListMinWidth, range: 100...600, step: 10, unit: "pt")
                IntRow("Ideal width", value: $config.projectListIdealWidth, range: 100...600, step: 10, unit: "pt")
            }

            Section("Task Sheets") {
                IntRow("Minimum width", value: $config.taskSheetMinWidth, range: 200...1200, step: 20, unit: "pt")
            }

            Section("Quick Commands") {
                IntRow("Width", value: $config.quickCommandsWidth, range: 200...900, step: 20, unit: "pt")
                IntRow("Minimum height", value: $config.quickCommandsMinHeight, range: 100...900, step: 20, unit: "pt")
                IntRow("Maximum height", value: $config.quickCommandsMaxHeight, range: 100...900, step: 20, unit: "pt")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Data

private struct DataTab: View {
    @Binding var storage: StorageConfig
    @Binding var logging: LoggingConfig

    private var fileSizeMB: Binding<Double> {
        Binding(
            get: { Double(logging.maxFileSizeBytes) / 1_048_576 },
            set: { logging.maxFileSizeBytes = max(1, Int($0 * 1_048_576)) }
        )
    }

    var body: some View {
        Form {
            Section("Database Location") {
                TextField("App support folder", text: $storage.appSupportFolderName)
                    .help("Folder inside ~/Library/Application Support/ where the database is stored.")
                TextField("Database file", text: $storage.databaseFileName)
                    .help("SQLite database file name.")
            }

            Section {
                Label {
                    Text("Changing these paths causes OpenZeus to open a new, empty database on next launch. Existing data is not migrated automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Logs") {
                HStack {
                    TextField("Logs directory", text: $logging.logsDirectory)
                        .help("Path relative to $HOME.")
                    Button("Reveal") { revealLogsFolder() }
                }
                TextField("Log file name", text: $logging.logFileName)
            }

            Section("Log Rotation") {
                HStack {
                    Text("Max file size")
                    Spacer()
                    TextField("", value: fileSizeMB, format: .number.precision(.fractionLength(0)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Text("MB").foregroundStyle(.secondary)
                }

                HStack {
                    Text("Backup files")
                    Spacer()
                    TextField("", value: $logging.maxBackupFiles, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("", value: $logging.maxBackupFiles, in: 1...20)
                        .labelsHidden()
                }
            }

            Section("Log Timestamps") {
                TextField("Format string", text: $logging.timestampFormat)
                    .font(.system(.body, design: .monospaced))
                    .help("DateFormatter format string, e.g. \"yyyy-MM-dd HH:mm:ss.SSS\".")
                Text("Preview: \(formattedNow)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }

    private var formattedNow: String {
        let f = DateFormatter()
        f.dateFormat = logging.timestampFormat
        return f.string(from: Date())
    }

    private func revealLogsFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(logging.logsDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - LLM

private struct LLMTab: View {
    @Binding var config: LLMConfig

    private static let knownProviders = ["anthropic", "openai", "google", "ollama", "openrouter", "custom"]

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $config.provider) {
                    ForEach(Self.knownProviders, id: \.self) { provider in
                        Text(provider.capitalized).tag(provider)
                    }
                }

                TextField("Model", text: $config.model)
            }

            Section("Authentication") {
                TextField("API key env var", text: $config.apiKeyEnvironmentVariable)
                    .help("Environment variable name to read the API key from.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Cleanup

private enum CleanupItemKind {
    case orphanedTmuxSession(sessionName: String)
    case archivedTaskWithWorktree(task: AgentTask)
    case staleWorktreeReference(task: AgentTask)
}

private struct CleanupItem: Identifiable {
    let id = UUID()
    let kind: CleanupItemKind
    let title: String
    let detail: String
    let reason: String
    var tagColor: Color {
        switch kind {
        case .orphanedTmuxSession: .red
        case .archivedTaskWithWorktree: .orange
        case .staleWorktreeReference: .secondary
        }
    }
    var tagLabel: String {
        switch kind {
        case .orphanedTmuxSession: "tmux"
        case .archivedTaskWithWorktree: "worktree"
        case .staleWorktreeReference: "stale ref"
        }
    }
}

// MARK: - Reusable row helpers

private struct DoubleRow: View {
    let label: String
    @Binding var value: Double
    let unit: String

    init(_ label: String, value: Binding<Double>, unit: String) {
        self.label = label
        self._value = value
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private struct IntFieldRow: View {
    let label: String
    @Binding var value: Int
    let unit: String

    init(_ label: String, value: Binding<Int>, unit: String) {
        self.label = label
        self._value = value
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private struct IntRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    init(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text(unit).foregroundStyle(.secondary)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

private struct ArrayField: View {
    let label: String
    @Binding var array: [String]

    init(_ label: String, array: Binding<[String]>) {
        self.label = label
        self._array = array
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { array.joined(separator: "\n") },
            set: { array = $0.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout)
            TextEditor(text: textBinding)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 72, maxHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 1))
            Text("One entry per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
