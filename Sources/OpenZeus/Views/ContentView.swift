import AppKit
import SwiftUI

private enum FocusedPanel: Hashable {
    case projects, tasks
}

private extension Notification.Name {
    static let focusProjectsPanel = Notification.Name("OpenZeus.focusProjectsPanel")
    static let focusTasksPanel = Notification.Name("OpenZeus.focusTasksPanel")
}

struct ContentView: View {
    @EnvironmentObject var appDatabase: AppDatabase
    @EnvironmentObject var terminalStore: TerminalStore
    @Environment(\.appConfig) private var appConfig
    @State private var selectedProject: Project?
    @State private var selectedTask: AgentTask?
    @AppStorage("lastSelectedProjectID") private var lastSelectedProjectID = ""
    @FocusState private var focusedPanel: FocusedPanel?
    @State private var keyMonitor: Any?

    var body: some View {
        splitView
            .background {
                Button("", action: { focusedPanel = .projects })
                    .keyboardShortcut("1", modifiers: .command)
                    .accessibilityHidden(true)
                Button("", action: { focusedPanel = .tasks })
                    .keyboardShortcut("2", modifiers: .command)
                    .accessibilityHidden(true)
            }
            .task {
                restoreSelection()
                terminalStore.startPeriodicCleanup(interval: appConfig.terminal.orphanCleanupIntervalSeconds) {
                    Set(appDatabase.tasks.filter { !$0.isArchived }.map { $0.id }
                        + appDatabase.projects.filter { !$0.isDeleted }.map { $0.id })
                }
            }
            .onChange(of: selectedTask) { _, newTask in
                saveTaskSelection(newTask)
                terminalStore.selectedTaskID = newTask?.id
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
            .onAppear { setupKeyMonitor() }
            .onDisappear { tearDownKeyMonitor() }
            .onReceive(NotificationCenter.default.publisher(for: .focusProjectsPanel)) { _ in
                focusedPanel = .projects
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusTasksPanel)) { _ in
                focusedPanel = .tasks
            }
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else {
                return event
            }
            switch event.charactersIgnoringModifiers {
            case "1":
                NotificationCenter.default.post(name: .focusProjectsPanel, object: nil)
                return nil
            case "2":
                NotificationCenter.default.post(name: .focusTasksPanel, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func tearDownKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ProjectList(selection: $selectedProject, activeTask: selectedTask)
                .focused($focusedPanel, equals: .projects)
                .navigationSplitViewColumnWidth(
                    min: CGFloat(appConfig.ui.projectListMinWidth),
                    ideal: CGFloat(appConfig.ui.projectListIdealWidth)
                )
        } content: {
            if let project = selectedProject {
                TaskList(project: project, selection: $selectedTask)
                    .focused($focusedPanel, equals: .tasks)
            } else {
                ContentUnavailableView("No Project Selected",
                                       systemImage: "folder",
                                       description: Text("Select a project to view tasks."))
            }
        } detail: {
            if let task = selectedTask {
                TerminalPane(
                    task: task,
                    projectDirectory: selectedProject?.directoryURL.path(percentEncoded: false) ?? task.workingDirectory.path(percentEncoded: false),
                    projectName: selectedProject?.name ?? ""
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
