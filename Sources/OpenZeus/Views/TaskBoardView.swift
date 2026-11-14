import SwiftUI

private struct BoardProject: Identifiable {
    let project: Project
    let openTasks: [AgentTask]
    let runningTasks: [AgentTask]

    var id: UUID { project.id }
}

struct TaskBoardView: View {
    @EnvironmentObject private var appDatabase: AppDatabase
    @EnvironmentObject private var terminalStore: TerminalStore
    let onSelectTask: (AgentTask, Project) -> Void

    private var boardProjects: [BoardProject] {
        appDatabase.projects.compactMap { project in
            let projectTasks = appDatabase.tasks(for: project.id).filter { !$0.isArchived }
            let runningTasks = projectTasks.filter { terminalStore.activeProcessTaskIDs.contains($0.id) }
            guard !runningTasks.isEmpty else { return nil }
            return BoardProject(
                project: project,
                openTasks: projectTasks.filter { $0.status == .idle && !terminalStore.activeProcessTaskIDs.contains($0.id) },
                runningTasks: runningTasks
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Board")
                        .font(.title2.weight(.semibold))
                    Text("Open and in-progress tasks across active projects")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(boardProjects.reduce(0) { $0 + $1.openTasks.count + $1.runningTasks.count }) tasks")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if boardProjects.isEmpty {
                ContentUnavailableView(
                    "No In-Progress Tasks",
                    systemImage: "rectangle.split.2x2",
                    description: Text("Projects appear here when they have at least one running task.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    boardColumn(title: "Open", systemImage: "circle", count: boardProjects.reduce(0) { $0 + $1.openTasks.count }, tasks: \.openTasks, color: .secondary)
                    boardColumn(title: "In Progress", systemImage: "circle.inset.filled", count: boardProjects.reduce(0) { $0 + $1.runningTasks.count }, tasks: \.runningTasks, color: .green)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: logBoardContents)
        .onChange(of: appDatabase.tasks) { _, _ in logBoardContents() }
        .onChange(of: appDatabase.projects) { _, _ in logBoardContents() }
        .onChange(of: terminalStore.activeProcessTaskIDs) { _, _ in logBoardContents() }
    }

    private func logBoardContents() {
        let visibleTasks = appDatabase.tasks.filter { !$0.isArchived }
        let openCount = visibleTasks.filter { $0.status == .idle }.count
        let activeCount = visibleTasks.filter { terminalStore.activeProcessTaskIDs.contains($0.id) }.count
        let includedOpenCount = boardProjects.reduce(0) { $0 + $1.openTasks.count }
        let includedActiveCount = boardProjects.reduce(0) { $0 + $1.runningTasks.count }
        logInfo("TaskBoard: projects=\(appDatabase.projects.count), tasks=\(visibleTasks.count), open=\(openCount), active=\(activeCount), displayedProjects=\(boardProjects.count), displayedOpen=\(includedOpenCount), displayedActive=\(includedActiveCount)")
    }

    private func boardColumn(
        title: String,
        systemImage: String,
        count: Int,
        tasks: KeyPath<BoardProject, [AgentTask]>,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(boardProjects) { item in
                        let projectTasks = item[keyPath: tasks]
                        if !projectTasks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.project.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)

                                ForEach(projectTasks) { task in
                                    Button {
                                        onSelectTask(task, item.project)
                                    } label: {
                                        TaskBoardCard(task: task, color: color)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open \(task.name) in \(item.project.name)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TaskBoardCard: View {
    let task: AgentTask
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                Text(task.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let description = task.taskDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
