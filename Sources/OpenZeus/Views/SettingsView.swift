import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var savedConfig: AppConfig
    @State private var saveTask: Task<Void, Never>?

    init() {
        let loaded = AppConfig.load()
        _config = State(initialValue: loaded)
        _savedConfig = State(initialValue: loaded)
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

                InterfaceTab(config: $config.ui)
                    .tabItem { Label("Interface", systemImage: "sidebar.left") }

                StorageTab(config: $config.storage)
                    .tabItem { Label("Storage", systemImage: "externaldrive") }

                LoggingTab(config: $config.logging)
                    .tabItem { Label("Logging", systemImage: "doc.text") }
            }
            .frame(width: 500, height: 480)

            if config != savedConfig {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Changes will take effect after restarting OpenZeus.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .onChange(of: config) { _, newConfig in
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                newConfig.save()
                savedConfig = newConfig
            }
        }
        .onDisappear {
            saveTask?.cancel()
            config.save()
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

// MARK: - Storage

private struct StorageTab: View {
    @Binding var config: StorageConfig

    var body: some View {
        Form {
            Section("Database Location") {
                TextField("App support folder", text: $config.appSupportFolderName)
                    .help("Folder inside ~/Library/Application Support/ where the database is stored.")
                TextField("Database file", text: $config.databaseFileName)
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Logging

private struct LoggingTab: View {
    @Binding var config: LoggingConfig

    private var fileSizeMB: Binding<Double> {
        Binding(
            get: { Double(config.maxFileSizeBytes) / 1_048_576 },
            set: { config.maxFileSizeBytes = max(1, Int($0 * 1_048_576)) }
        )
    }

    var body: some View {
        Form {
            Section("Paths") {
                HStack {
                    TextField("Logs directory", text: $config.logsDirectory)
                        .help("Path relative to $HOME.")
                    Button("Reveal") { revealLogsFolder() }
                }
                TextField("Log file name", text: $config.logFileName)
            }

            Section("Rotation") {
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
                    TextField("", value: $config.maxBackupFiles, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("", value: $config.maxBackupFiles, in: 1...20)
                        .labelsHidden()
                }
            }

            Section("Timestamp Format") {
                TextField("Format string", text: $config.timestampFormat)
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
        f.dateFormat = config.timestampFormat
        return f.string(from: Date())
    }

    private func revealLogsFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(config.logsDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
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
