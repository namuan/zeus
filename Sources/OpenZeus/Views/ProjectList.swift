import SwiftUI

struct ProjectList: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @EnvironmentObject var terminalStore: TerminalStore
    @Binding var selection: Project?
    let activeTask: AgentTask?

    var body: some View {
        List(selection: $selection) {
            ForEach(appDatabase.projects) { project in
                ProjectRow(
                    project: project,
                    activeTask: activeTask,
                    isSelected: selection == project,
                    hasActiveProcess: appDatabase.tasks(for: project.id)
                        .contains { terminalStore.activeProcessTaskIDs.contains($0.id) },
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
        let project = Project(id: UUID(), name: url.lastPathComponent, directoryURL: url)
        appDatabase.insertProject(project)
        selection = project
    }

    private func removeProject(_ project: Project) {
        if selection == project { selection = nil }
        for task in appDatabase.tasks(for: project.id) {
            terminalStore.killSession(for: task.id)
        }
        appDatabase.deleteProject(id: project.id)
    }

    private func deleteProjects(offsets: IndexSet) {
        for index in offsets { removeProject(appDatabase.projects[index]) }
    }
}

private struct ProjectRow: View {
    let project: Project
    let activeTask: AgentTask?
    let isSelected: Bool
    let hasActiveProcess: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

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
            if let task = activeTask, task.projectID == project.id {
                Label(task.name, systemImage: "terminal.fill")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .overlay(alignment: .trailing) {
            if isHovered {
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 22, height: 22)
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .help("Delete Project")
            }
        }
        .onHover { isHovered = $0 }
    }
}
