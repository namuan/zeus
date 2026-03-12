import SwiftUI
import SwiftData

struct TaskList: View {
    @Environment(\.modelContext) private var modelContext
    let project: Project
    @Binding var selection: AgentTask?

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
                Button(action: addTask) {
                    Label("Add Task", systemImage: "plus")
                }
            }
        }
    }

    private func addTask() {
        let task = AgentTask(
            name: "New Task",
            command: "/bin/sh",
            workingDirectory: project.directoryURL,
            project: project
        )
        modelContext.insert(task)
        selection = task
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

private struct TaskRow: View {
    let task: AgentTask

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.name)
                    .font(.headline)
                Text(task.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
