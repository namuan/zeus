import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var selectedTask: AgentTask?

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
    }
}
