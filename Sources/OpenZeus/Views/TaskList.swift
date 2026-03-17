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
                    isSelected: selection?.id == task.id,
                    onSelect: { selection = task },
                    onArchive: { archiveTask(task) },
                    onDelete: { taskToDelete = task }
                )
            }
            .onDelete(perform: deleteTasks)

            Button(action: { showingNewTask = true }) {
                Label("New Task", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

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
            NewTaskSheet(project: project)
        }
    }

    private func archiveTask(_ task: AgentTask) {
        if selection == task { selection = nil }
        if !task.isArchived { terminalStore.killSession(for: task.id) }
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
                branchName: worktreeBranch
            )
        }
    }

    private func deleteTasks(offsets: IndexSet) {
        for index in offsets { deleteTask(projectTasks[index]) }
    }
}

struct NewTaskSheet: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appConfig) private var appConfig
    let project: Project
    var onCreated: (AgentTask) -> Void = { _ in }

    @State private var text = ""
    @State private var createWorktree = false

    private static let placeholder = "Task title…\n\nTask description…"

    private var worktreeConfigured: Bool { !appConfig.worktree.resolvedBasePath.isEmpty }

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
                    if !worktreeConfigured {
                        Text("(configure path in Settings > Worktree)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .disabled(!worktreeConfigured)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Discard") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: CGFloat(appConfig.ui.taskSheetMinWidth))
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let task = AgentTask(
            id: UUID(),
            projectID: project.id,
            name: title.isEmpty ? trimmed : title,
            taskDescription: trimmed,
            command: appConfig.terminal.resolvedShell,
            environment: [:],
            workingDirectory: project.directoryURL,
            status: .idle
        )
        appDatabase.insertTask(task)
        dismiss()
        onCreated(task)

        if createWorktree {
            let taskID = task.id
            let taskName = task.name
            let repoPath = project.directoryURL.path(percentEncoded: false)
            let projectSlug = WorktreeService.projectSlug(from: project.name)
            let worktreeConfig = appConfig.worktree
            let service = WorktreeService(gitExecutablePath: appConfig.git.executablePath)
            Task { @MainActor in
                do {
                    let result = try await service.createWorktree(
                        taskID: taskID,
                        taskName: taskName,
                        repoPath: repoPath,
                        projectSlug: projectSlug,
                        config: worktreeConfig
                    )
                    if var updated = appDatabase.task(id: taskID) {
                        updated.worktreePath = result.path
                        updated.worktreeBranch = result.branch
                        appDatabase.updateTask(updated)
                    }
                } catch {
                    print("[WorktreeService] Failed to create worktree: \(error.localizedDescription)")
                }
            }
        }
    }
}

private struct TaskRow: View {
    let task: AgentTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var terminalStore: TerminalStore
    @EnvironmentObject var appDatabase: AppDatabase
    @State private var showingEdit = false

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
                        terminalStore.updateTaskMetadata(taskID: task.id, name: task.name, watchMode: updated.watchMode)
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
        .sheet(isPresented: $showingEdit) {
            EditTaskSheet(task: task)
        }
    }

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
        updated.name = trimmed.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        updated.taskDescription = trimmed
        appDatabase.updateTask(updated)
        dismiss()
    }
}

private struct ActiveProcessBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Active")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.green.opacity(0.12))
        .clipShape(Capsule())
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
