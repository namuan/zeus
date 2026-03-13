import SwiftUI

struct TaskList: View {
    @EnvironmentObject var appDatabase: AppDatabase
    let project: Project
    @Binding var selection: AgentTask?
    @State private var showingNewTask = false

    private var projectTasks: [AgentTask] {
        appDatabase.tasks(for: project.id)
    }

    var body: some View {
        List {
            ForEach(projectTasks) { task in
                TaskRow(
                    task: task,
                    isSelected: selection?.id == task.id,
                    onSelect: { selection = task },
                    onDelete: { deleteTask(task) }
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
        }
        .navigationTitle(project.name)
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet(project: project) { task in
                selection = task
            }
        }
    }

    private func deleteTask(_ task: AgentTask) {
        if selection == task { selection = nil }
        appDatabase.deleteTask(id: task.id)
    }

    private func deleteTasks(offsets: IndexSet) {
        for index in offsets { deleteTask(projectTasks[index]) }
    }
}

struct NewTaskSheet: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @Environment(\.dismiss) private var dismiss
    let project: Project
    var onCreated: (AgentTask) -> Void = { _ in }

    @State private var text = ""

    private static let placeholder = "Task title…\n\nTask description…"

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

            HStack {
                Button("Discard") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let task = AgentTask(
            id: UUID(),
            projectID: project.id,
            name: title.isEmpty ? trimmed : title,
            taskDescription: trimmed,
            command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash",
            environment: [:],
            workingDirectory: project.directoryURL,
            status: .idle
        )
        appDatabase.insertTask(task)
        dismiss()
        onCreated(task)
    }
}

private struct TaskRow: View {
    let task: AgentTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var terminalStore: TerminalStore
    @State private var showingEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                descriptionText
                Spacer()
                if isSelected {
                    Image(systemName: "terminal.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
            }

            HStack {
                if task.status != .idle {
                    StatusBadge(status: task.status)
                }
                if terminalStore.activeProcessTaskIDs.contains(task.id) {
                    ActiveProcessBadge()
                }
                Spacer()
                Button {
                    let text = task.taskDescription ?? task.name
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))
                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button(action: onSelect) {
                    Label("Open Terminal", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
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
                Text(lines.dropFirst().joined(separator: "\n"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(description)
                .font(.headline)
        }
    }
}

private struct EditTaskSheet: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @Environment(\.dismiss) private var dismiss
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
                    .keyboardShortcut(.defaultAction)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
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
