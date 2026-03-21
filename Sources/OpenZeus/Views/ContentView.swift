import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @EnvironmentObject var terminalStore: TerminalStore
    @Environment(\.appConfig) private var appConfig
    @State private var selectedProject: Project?
    @State private var selectedTask: AgentTask?
    @AppStorage("lastSelectedProjectID") private var lastSelectedProjectID = ""

    var body: some View {
        splitView
            .task {
                restoreSelection()
                terminalStore.startPeriodicCleanup(interval: appConfig.terminal.orphanCleanupIntervalSeconds) {
                    Set(appDatabase.tasks.filter { !$0.isArchived }.map { $0.id }
                        + appDatabase.projects.filter { !$0.isDeleted }.map { $0.id })
                }
            }
            .onChange(of: selectedTask) { _, newTask in
                saveTaskSelection(newTask)
            }
            .onChange(of: selectedProject) { oldProject, newProject in
                switchProject(from: oldProject, to: newProject)
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

    private var splitView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ProjectList(selection: $selectedProject, activeTask: selectedTask)
                .navigationSplitViewColumnWidth(
                    min: CGFloat(appConfig.ui.projectListMinWidth),
                    ideal: CGFloat(appConfig.ui.projectListIdealWidth)
                )
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
                TerminalPane(
                    task: task,
                    projectDirectory: selectedProject?.directoryURL.path(percentEncoded: false) ?? task.workingDirectory.path(percentEncoded: false)
                )
            } else if let project = selectedProject {
                NoTaskDetailPane(project: project)
            } else {
                ContentUnavailableView("No Task Selected",
                                       systemImage: "terminal",
                                       description: Text("Select a task to open its terminal."))
            }
        }
    }

    // MARK: - Per-project task memory

    private var lastTaskPerProject: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "lastTaskPerProject") as? [String: String] ?? [:] }
        set { UserDefaults.standard.setValue(newValue, forKey: "lastTaskPerProject") }
    }

    private func saveTaskSelection(_ task: AgentTask?) {
        guard let projectID = selectedProject?.id.uuidString else { return }
        var map = lastTaskPerProject
        map[projectID] = task?.id.uuidString ?? ""
        UserDefaults.standard.setValue(map, forKey: "lastTaskPerProject")
    }

    private func switchProject(from old: Project?, to new: Project?) {
        guard old?.id != new?.id else { return }
        UserDefaults.standard.setValue(new?.id.uuidString ?? "", forKey: "lastSelectedProjectID")
        if let projectID = new?.id.uuidString,
           let taskIDString = lastTaskPerProject[projectID],
           let taskID = UUID(uuidString: taskIDString),
           let task = appDatabase.task(id: taskID) {
            selectedTask = task
        } else {
            selectedTask = nil
        }
    }

    private func restoreSelection() {
        guard let projectID = UUID(uuidString: lastSelectedProjectID),
              let project = appDatabase.projects.first(where: { $0.id == projectID }) else { return }
        selectedProject = project
        if let taskIDString = lastTaskPerProject[lastSelectedProjectID],
           let taskID = UUID(uuidString: taskIDString),
           let task = appDatabase.task(id: taskID) {
            selectedTask = task
        }
    }
}
