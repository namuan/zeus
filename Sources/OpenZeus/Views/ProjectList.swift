import SwiftUI
import SwiftData

struct ProjectList: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var terminalStore: TerminalStore
    let projects: [Project]
    @Binding var selection: Project?
    let activeTask: AgentTask?

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                ProjectRow(
                    project: project,
                    activeTask: activeTask,
                    isSelected: selection == project,
                    hasActiveProcess: project.tasks.contains { terminalStore.activeProcessTaskIDs.contains($0.id) },
                    onRemove: { removeProject(project) }
                )
                .tag(project)
            }
            .onDelete(perform: deleteProjects)
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem {
                Button(action: addProject) {
                    Label("Add Project", systemImage: "plus")
                }
            }
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let project = Project(name: url.lastPathComponent, directoryURL: url)
        modelContext.insert(project)
        selection = project
    }

    private func removeProject(_ project: Project) {
        if selection == project { selection = nil }
        modelContext.delete(project)
    }

    private func deleteProjects(offsets: IndexSet) {
        for index in offsets { removeProject(projects[index]) }
    }
}

private struct ProjectRow: View {
    let project: Project
    let activeTask: AgentTask?
    let isSelected: Bool
    let hasActiveProcess: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                Text(project.name)
                    .font(.headline)
                if hasActiveProcess {
                    Circle()
                        .fill(isSelected ? Color.white : Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            Text(project.directoryURL.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
            if let task = activeTask, project.tasks.contains(where: { $0.id == task.id }) {
                Label(task.name, systemImage: "terminal.fill")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from App", systemImage: "minus.circle")
            }
        }
    }
}
