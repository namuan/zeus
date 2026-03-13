import SwiftUI
import SwiftData

struct TaskList: View {
    @Environment(\.modelContext) private var modelContext
    let project: Project
    @Binding var selection: AgentTask?
    @State private var showingNewTask = false

    var body: some View {
        List {
            ForEach(project.tasks) { task in
                TaskRow(task: task, isSelected: selection?.id == task.id, onSelect: { selection = task })
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
        .safeAreaInset(edge: .bottom) {
            if let task = selection {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(Color.accentColor)
                    Group {
                        if let projectName = task.project?.name {
                            Text(projectName).bold() + Text("  ›  \(task.name)")
                        } else {
                            Text(task.name)
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
        .navigationTitle(project.name)
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet(project: project) { task in
                selection = task
            }
        }
    }

    private func deleteTasks(offsets: IndexSet) {
        for index in offsets {
            let task = project.tasks[index]
            modelContext.delete(task)
            if selection == task {
                selection = nil
            }
        }
    }
}

struct NewTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let project: Project
    var onCreated: (AgentTask) -> Void = { _ in }

    @State private var description = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Task")
                .font(.title2.bold())

            TextEditor(text: $description)
                .font(.body)
                .frame(minHeight: 120)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Enter task description…")
                            .foregroundStyle(.tertiary)
                            .padding(8)
                    }
                }

            HStack {
                Button("Discard") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
    }

    private func save() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = AgentTask(
            name: trimmed,
            taskDescription: trimmed,
            command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash",
            workingDirectory: project.directoryURL,
            project: project
        )
        modelContext.insert(task)
        dismiss()
        onCreated(task)
    }
}

private struct TaskRow: View {
    let task: AgentTask
    let isSelected: Bool
    let onSelect: () -> Void

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
                StatusBadge(status: task.status)
                Spacer()
                Button(action: onSelect) {
                    Label("Open Terminal", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
