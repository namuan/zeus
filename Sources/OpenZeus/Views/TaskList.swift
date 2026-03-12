import SwiftUI
import SwiftData

struct TaskList: View {
    @Environment(\.modelContext) private var modelContext
    let project: Project
    @Binding var selection: AgentTask?
    @State private var showingNewTask = false

    var body: some View {
        List(selection: $selection) {
            ForEach(project.tasks) { task in
                TaskRow(task: task)
                    .tag(task)
            }
            .onDelete(perform: deleteTasks)
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem {
                Button(action: { showingNewTask = true }) {
                    Label("Add Task", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskSheet(project: project)
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
    }
}

private struct TaskRow: View {
    let task: AgentTask

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.taskDescription ?? task.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            StatusBadge(status: task.status)
        }
        .padding(.vertical, 2)
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
