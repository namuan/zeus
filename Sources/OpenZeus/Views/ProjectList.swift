import SwiftUI
import SwiftData

struct ProjectList: View {
    @Environment(\.modelContext) private var modelContext
    let projects: [Project]
    @Binding var selection: Project?

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                ProjectRow(project: project)
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

    var body: some View {
        VStack(alignment: .leading) {
            Text(project.name)
                .font(.headline)
            Text(project.directoryURL.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
