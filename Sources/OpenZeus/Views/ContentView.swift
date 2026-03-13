import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var selectedTask: AgentTask?
    @AppStorage("lastSelectedTaskID") private var lastSelectedTaskID = ""

    var body: some View {
        NavigationSplitView {
            ProjectList(projects: projects, selection: $selectedProject, activeTask: selectedTask)
        } content: {
            if let project = selectedProject {
                TaskList(project: project, selection: $selectedTask)
            } else {
                ContentUnavailableView("No Project Selected",
                                       systemImage: "folder",
                                       description: Text("Select a project to view tasks."))
            }
        } detail: {
            if let task = selectedTask {
                TerminalPane(task: task)
            } else {
                ContentUnavailableView("No Task Selected",
                                       systemImage: "terminal",
                                       description: Text("Select a task to open its terminal."))
            }
        }
        .task {
            restoreSelection()
        }
        .onChange(of: selectedTask) { _, task in
            lastSelectedTaskID = task?.id.uuidString ?? ""
        }
    }

    private func restoreSelection() {
        guard let id = UUID(uuidString: lastSelectedTaskID) else { return }
        let descriptor = FetchDescriptor<AgentTask>(predicate: #Predicate { $0.id == id })
        guard let task = try? modelContext.fetch(descriptor).first else { return }
        selectedTask = task
        selectedProject = task.project
    }
}
