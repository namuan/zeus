import SwiftUI
import SwiftData

struct ProjectList: View {
    @Environment(\.modelContext) private var modelContext
    let projects: [Project]
    @Binding var selection: Project?
    let activeTask: AgentTask?

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                ProjectRow(project: project, activeTask: activeTask, isSelected: selection == project)
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

    private func deleteProjects(offsets: IndexSet) {
        for index in offsets {
            let project = projects[index]
            modelContext.delete(project)
            if selection == project {
                selection = nil
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let activeTask: AgentTask?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.headline)
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
    }
}
