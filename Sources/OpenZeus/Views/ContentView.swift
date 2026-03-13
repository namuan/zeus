import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @State private var selectedProject: Project?
    @State private var selectedTask: AgentTask?
    @AppStorage("lastSelectedTaskID") private var lastSelectedTaskID = ""

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ProjectList(selection: $selectedProject, activeTask: selectedTask)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
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
        .onChange(of: appDatabase.tasks) { _, tasks in
            if let current = selectedTask {
                selectedTask = tasks.first { $0.id == current.id }
            }
        }
        .onChange(of: appDatabase.projects) { _, projects in
            if let current = selectedProject {
                selectedProject = projects.first { $0.id == current.id }
            }
        }
    }

    private func restoreSelection() {
        guard let id = UUID(uuidString: lastSelectedTaskID),
              let task = appDatabase.task(id: id) else { return }
        selectedTask = task
        selectedProject = appDatabase.projects.first { $0.id == task.projectID }
    }
}
