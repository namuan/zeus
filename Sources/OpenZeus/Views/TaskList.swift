import AppKit
import SwiftUI

struct TaskList: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @EnvironmentObject var terminalStore: TerminalStore
    @Environment(\.appConfig) private var appConfig
    let project: Project
    @Binding var selection: AgentTask?
    @State private var showingNewTask = false
    @State private var showArchived = false
    @State private var taskToDelete: AgentTask?

    private var projectTasks: [AgentTask] {
        let all = appDatabase.tasks(for: project.id)
        return showArchived ? all : all.filter { !$0.isArchived }
    }

    private var archivedTaskCount: Int {
        appDatabase.tasks(for: project.id).filter { $0.isArchived }.count
    }

    var body: some View {
        List {
            ForEach(projectTasks) { task in
                TaskRow(
                    task: task,
                    projectName: project.name,
                    isSelected: selection?.id == task.id,
                    onSelect: { selection = task },
                    onArchive: { archiveTask(task) },
                    onDelete: { taskToDelete = task }
                )
            }
            .onDelete(perform: deleteTasks)

            HStack(spacing: 0) {
                Button(action: { showingNewTask = true }) {
                    Label("New Task", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Button(action: createQuickTask) {
                    Label("Quick Task", systemImage: "bolt.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if archivedTaskCount > 0 {
                Button(action: { showArchived.toggle() }) {
                    HStack(spacing: 6) {
                        Label(
                            showArchived ? "Hide Archived" : "Show Archived",
                            systemImage: showArchived ? "archivebox.fill" : "archivebox"
                        )
                        if !showArchived {
                            Text("\(archivedTaskCount)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { navigateTask(by: -1); return .handled }
        .onKeyPress(.downArrow) { navigateTask(by: 1); return .handled }
        .navigationTitle(project.name)
        .confirmationDialog(
            "Delete \"\(taskToDelete?.name ?? "Task")\"?",
            isPresented: Binding(get: { taskToDelete != nil }, set: { if !$0 { taskToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let task = taskToDelete { deleteTask(task) }
            }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet(
                project: project,
                onCreated: projectTasks.isEmpty ? { newTask in
                    selection = newTask
                } : nil
            )
        }
    }

    private func navigateTask(by delta: Int) {
        let tasks = appDatabase.tasks(for: project.id).filter { !$0.isArchived }
        guard !tasks.isEmpty else { return }
        if let current = selection, let idx = tasks.firstIndex(where: { $0.id == current.id }) {
            selection = tasks[max(0, min(tasks.count - 1, idx + delta))]
        } else {
            selection = delta > 0 ? tasks.first : tasks.last
        }
    }

    private func archiveTask(_ task: AgentTask) {
        if selection == task { selection = nil }
        if !task.isArchived {
            terminalStore.killSession(for: task.id)
            removeWorktreeIfNeeded(for: task)
        }
        var updated = task
        updated.isArchived = !task.isArchived
        appDatabase.updateTask(updated)
    }

    private func deleteTask(_ task: AgentTask) {
        if selection == task { selection = nil }
        terminalStore.killSession(for: task.id)
        removeWorktreeIfNeeded(for: task)
        appDatabase.deleteTask(id: task.id)
    }

    private func removeWorktreeIfNeeded(for task: AgentTask) {
        guard let worktreePath = task.worktreePath,
              let worktreeBranch = task.worktreeBranch else { return }
        let repoPath = project.directoryURL.path(percentEncoded: false)
        let service = WorktreeService(gitExecutablePath: appConfig.git.executablePath)
        Task {
            await service.removeWorktree(
                worktreePath: worktreePath,
                repoPath: repoPath,
                branchName: worktreeBranch,
                deleteBranch: task.worktreeBranchIsOwned
            )
        }
    }

    private func deleteTasks(offsets: IndexSet) {
        for index in offsets { deleteTask(projectTasks[index]) }
    }

    private func defaultQuickTaskName() -> String {
        "Untitled Task \(Self.dateFormatter.string(from: Date()))"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private func createQuickTask() {
        let name = defaultQuickTaskName()
        let task = AgentTask(
            id: UUID(),
            projectID: project.id,
            name: name,
            taskDescription: name,
            command: appConfig.terminal.resolvedShell,
            environment: [:],
            workingDirectory: project.directoryURL,
            status: .idle
        )
        appDatabase.insertTask(task)
        selection = task
    }
}

struct NewTaskSheet: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var appConfig
    let project: Project
    var onCreated: ((AgentTask) -> Void)?

    @State private var taskID = UUID()
    @State private var text = ""
    @State private var createWorktree = false
    @State private var branchNameOverride = ""
    @State private var isCreatingWorktree = false
    @State private var worktreeErrorMessage: String?
    @State private var useExistingBranch = false
    @State private var branchOptions: [WorktreeBranchOption] = []
    @State private var selectedBranchID = ""
    @State private var branchesLoading = false
    @State private var branchesError: String?

    private static let placeholder = "Task title…\n\nTask description…"

    private var worktreeConfigured: Bool { !appConfig.worktree.resolvedBasePath.isEmpty }

    private var derivedTitle: String { text.firstLineTitle }

    private var branchPlaceholder: String {
        "Auto: \(WorktreeService.branchName(for: taskID, taskName: derivedTitle))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("New Task")
                .font(.title2.bold())

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 120)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(Self.placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }

            Toggle(isOn: $createWorktree) {
                HStack(spacing: 6) {
                    Text("Create Git worktree")
                    if worktreeConfigured {
                        Text(appConfig.worktree.resolvedBasePath)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text("(configure path in Settings > Worktree)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .disabled(!worktreeConfigured)
            .frame(maxWidth: .infinity, alignment: .leading)

            if createWorktree && worktreeConfigured {
                Picker("Branch", selection: $useExistingBranch) {
                    Text("New").tag(false)
                    Text("Existing").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                if useExistingBranch {
                    if branchesLoading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading branches...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let error = branchesError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if branchOptions.isEmpty {
                        Text("No available branches found in repository.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Select branch")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    Task { await refreshBranches() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Refresh")
                                    }
                                    .font(.caption)
                                }
                                .disabled(branchesLoading)
                            }
                            List(branchOptions, id: \.id, selection: $selectedBranchID) { option in
                                BranchRow(option: option)
                                    .tag(option.id)
                            }
                            .frame(height: 160)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    TextField(branchPlaceholder, text: $branchNameOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
            }

            if let errorMessage = worktreeErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Discard") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreatingWorktree)
                Spacer()
                if isCreatingWorktree {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: CGFloat(appConfig.ui.taskSheetMinWidth))
        .onAppear {
            createWorktree = worktreeConfigured && appConfig.worktree.createByDefault
        }
        .task(id: createWorktree && useExistingBranch) {
            guard createWorktree && useExistingBranch else { return }
            await loadBranches()
        }
    }

    private var canSave: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isCreatingWorktree else {
            return false
        }
        guard createWorktree && useExistingBranch else { return true }
        guard !branchesLoading, branchesError == nil else { return false }
        guard let opt = branchOptions.first(where: { $0.id == selectedBranchID }) else { return false }
        return opt.isAvailable
    }

    private func loadBranches() async {
        branchesLoading = true
        branchesError = nil
        let repoPath = project.directoryURL.path(percentEncoded: false)
        let service = WorktreeService(gitExecutablePath: appConfig.git.executablePath)
        do {
            let options = try await service.listBranchOptions(repoPath: repoPath)
            let defaultBase = appConfig.worktree.defaultBaseBranch
            branchOptions = options.filter { opt in
                opt.kind != .remote || opt.localName != defaultBase
            }
            if selectedBranchID.isEmpty || !branchOptions.contains(where: { $0.id == selectedBranchID && $0.isAvailable }),
               let first = branchOptions.first(where: \.isAvailable) {
                selectedBranchID = first.id
            }
        } catch {
            branchesError = error.localizedDescription
            branchOptions = []
        }
        branchesLoading = false
    }

    private func refreshBranches() async {
        branchesLoading = true
        branchesError = nil
        let repoPath = project.directoryURL.path(percentEncoded: false)
        let service = WorktreeService(gitExecutablePath: appConfig.git.executablePath)
        do {
            try await service.fetchRemotes(repoPath: repoPath)
        } catch {
            branchesError = error.localizedDescription
            branchesLoading = false
            return
        }
        await loadBranches()
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var task = AgentTask(
            id: taskID,
            projectID: project.id,
            name: derivedTitle.isEmpty ? trimmed : derivedTitle,
            taskDescription: trimmed,
            command: appConfig.terminal.resolvedShell,
            environment: [:],
            workingDirectory: project.directoryURL,
            status: .idle
        )
        appDatabase.insertTask(task)

        guard createWorktree else {
            dismiss()
            onCreated?(task)
            return
        }

        worktreeErrorMessage = nil
        isCreatingWorktree = true
        let worktreeRequest = WorktreeRequest(
            taskID: task.id,
            taskName: task.name,
            repoPath: project.directoryURL.path(percentEncoded: false),
            projectSlug: WorktreeService.projectSlug(from: project.name)
        )
        let worktreeConfig = appConfig.worktree
        let service = WorktreeService(gitExecutablePath: appConfig.git.executablePath)
        let branchOverride = branchNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchSource: WorktreeBranchSource
        let branchIsOwned: Bool
        if useExistingBranch {
            guard let opt = branchOptions.first(where: { $0.id == selectedBranchID }) else { return }
            switch opt.kind {
            case .local, .remote where opt.presentLocally:
                branchSource = .existingBranch(opt.localName)
                branchIsOwned = false
            case .remote:
                branchSource = .remoteBranch(ref: opt.name, localName: opt.localName, presentLocally: false)
                branchIsOwned = true
            }
        } else {
            branchSource = .newBranch(name: branchOverride)
            branchIsOwned = true
        }
        Task { @MainActor in
            do {
                let result = try await service.createWorktree(
                    request: worktreeRequest,
                    config: worktreeConfig,
                    branchSource: branchSource
                )
                if var updated = appDatabase.task(id: task.id) {
                    updated.worktreePath = result.path
                    updated.worktreeBranch = result.branch
                    updated.worktreeBranchIsOwned = branchIsOwned
                    appDatabase.updateTask(updated)
                    task = updated
                }
                dismiss()
                onCreated?(task)
            } catch {
                isCreatingWorktree = false
                worktreeErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct BranchRow: View {
    let option: WorktreeBranchOption

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: option.kind == .local ? "arrow.triangle.branch" : "cloud")
                .foregroundStyle(option.kind == .remote ? .blue : .primary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(option.name)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
            }
        }
        .opacity(option.isAvailable ? 1 : 0.5)
    }

    private var subtitle: String {
        switch option.kind {
        case .local: return "local"
        case .remote where option.presentLocally: return "remote · local copy exists"
        case .remote: return "remote · creates local branch"
        }
    }

    private var subtitleColor: Color {
        option.kind == .remote && !option.presentLocally ? .orange : .secondary
    }
}

private struct TaskRow: View {
    let task: AgentTask
    let projectName: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var terminalStore: TerminalStore
    @EnvironmentObject var appDatabase: AppDatabase
    @State private var showingEdit = false
    @State private var showingNotes = false
    @State private var notesText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                descriptionText
                Spacer()
                Image(systemName: task.isArchived ? "archivebox.fill" : "terminal.fill")
                    .font(.caption)
                    .foregroundStyle(task.isArchived ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .opacity(task.isArchived || isSelected ? 1 : 0)
                    .padding(.top, 2)
            }

            HStack {
                if task.status != .idle {
                    StatusBadge(status: task.status)
                }
                if terminalStore.activeProcessTaskIDs.contains(task.id) {
                    ActiveProcessBadge()
                }
                if task.worktreePath != nil {
                    WorktreeBadge(branch: task.worktreeBranch)
                }
                if terminalStore.attentionTaskIDs.contains(task.id) {
                    Image(systemName: "bell.badge.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if !task.isArchived {
                    Button {
                        var updated = task
                        updated.watchMode = task.watchMode.next
                        appDatabase.updateTask(updated)
                        terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: updated.watchMode, projectName: projectName)
                    } label: {
                        Image(systemName: task.watchMode.systemImage)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(task.watchMode == .off ? .secondary : Color.orange)
                    .help(task.watchMode.label)
                    Button {
                        let text = task.taskDescription ?? task.name
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))
                if !task.isArchived {
                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button {
                        notesText = task.notes ?? ""
                        showingNotes = true
                    } label: {
                        Image(systemName: "note.text")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle((task.notes?.isEmpty == false) ? Color.accentColor : .secondary)
                    .help("Task Notes")
                    .popover(isPresented: $showingNotes, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            TextEditor(text: $notesText)
                                .font(.body)
                                .frame(width: 300, height: 200)
                        }
                        .padding()
                    }
                }
                Button(action: onArchive) {
                    Image(systemName: task.isArchived ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(task.isArchived ? Color.accentColor : .secondary)
                .help(task.isArchived ? "Unarchive Task" : "Complete & Archive")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .opacity(task.isArchived ? 0.5 : 1.0)
        .background(isSelected && !task.isArchived ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { if !task.isArchived { onSelect() } }
        .onChange(of: showingNotes) { _, isShowing in
            if !isShowing {
                var updated = task
                updated.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesText
                appDatabase.updateTask(updated)
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditTaskSheet(task: task)
        }
        .contextMenu {
            transcriptMenu
        }
    }

    @ViewBuilder
    private var transcriptMenu: some View {
        let directories = terminalStore.transcriptDirectories(for: task.id)
        if directories.isEmpty {
            Button("Open Transcript in Finder") {}
                .disabled(true)
        } else if directories.count == 1, let directory = directories.first {
            Button("Open Transcript in Finder") {
                NSWorkspace.shared.open(directory)
            }
        } else {
            Menu("Open Transcript in Finder") {
                ForEach(Array(directories.enumerated()), id: \.offset) { _, directory in
                    Button(Self.transcriptLabel(for: directory)) {
                        NSWorkspace.shared.open(directory)
                    }
                }
            }
        }
    }

    private static func transcriptLabel(for url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return "Session · \(Self.transcriptDateFormatter.string(from: date))"
    }

    private static let transcriptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    @ViewBuilder
    private var descriptionText: some View {
        let description = task.taskDescription ?? task.name
        let lines = description.components(separatedBy: "\n")
        if lines.count > 1, let first = lines.first {
            VStack(alignment: .leading, spacing: 2) {
                Text(first)
                    .font(.headline)
                    .strikethrough(task.isArchived)
                Text(lines.dropFirst().joined(separator: "\n"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(description)
                .font(.headline)
                .strikethrough(task.isArchived)
        }
    }
}

private struct EditTaskSheet: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var appConfig
    let task: AgentTask

    @State private var description: String

    init(task: AgentTask) {
        self.task = task
        self._description = State(initialValue: task.taskDescription ?? task.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Task")
                .font(.title2.bold())

            TextEditor(text: $description)
                .font(.body)
                .frame(minHeight: 120)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                )

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: CGFloat(appConfig.ui.taskSheetMinWidth))
    }

    private func save() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = task
        updated.name = description.firstLineTitle
        updated.taskDescription = trimmed
        appDatabase.updateTask(updated)
        dismiss()
    }
}

private extension String {
    /// Returns the first non-empty line, trimmed of surrounding whitespace.
    var firstLineTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
    }
}

private struct ActiveProcessBadge: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 6, height: 6)
    }
}

private struct WorktreeBadge: View {
    let branch: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "square.split.2x1")
                .font(.caption2)
            if let branch {
                Text(branch)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.purple.opacity(0.12))
        .clipShape(Capsule())
        .help(branch.map { "Worktree branch: \($0)" } ?? "Worktree active")
    }
}

private struct StatusBadge: View {
    let status: AgentStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .idle: .gray
        case .running: .green
        case .stopped: .orange
        case .error: .red
        }
    }
}
