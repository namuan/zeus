import AppKit
import SwiftUI

struct ProjectList: View {
    @EnvironmentObject private var appDatabase: AppDatabase
    @EnvironmentObject private var terminalStore: TerminalStore
    @Binding var selection: Project?
    let activeTask: AgentTask?

    @State private var projectToDelete: Project?

    var body: some View {
        List {
            ForEach(appDatabase.projects) { project in
                    ProjectRow(
                        project: project,
                        activeTask: activeTask,
                        isSelected: selection == project,
                        runningTaskCount: runningTaskCount(for: project),
                        openTaskCount: openTaskCount(for: project),
                        onSelect: { selection = project },
                        onRemove: { projectToDelete = project },
                        onOpenInFinder: { openInFinder(project) },
                        onOpenInTerminal: { openInTerminal(project) }
                    )
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
        .confirmationDialog(
            "Delete \"\(projectToDelete?.name ?? "Project")\"?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete { removeProject(project) }
            }
        } message: {
            Text("All tasks for this project will also be deleted. This cannot be undone.")
        }
    }

    private func runningTaskCount(for project: Project) -> Int {
        appDatabase.tasks(for: project.id)
            .filter { terminalStore.activeProcessTaskIDs.contains($0.id) }
            .count
    }

    private func openTaskCount(for project: Project) -> Int {
        appDatabase.tasks(for: project.id)
            .filter { !$0.isArchived && $0.status == .idle }
            .count
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

    private func openInFinder(_ project: Project) {
        NSWorkspace.shared.open(project.directoryURL)
    }

    private static let terminalAppURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.Terminal"
    )

    private func openInTerminal(_ project: Project) {
        guard let terminalURL = Self.terminalAppURL else { return }
        NSWorkspace.shared.open(
            [project.directoryURL],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct ProjectRow: View {
    let project: Project
    let activeTask: AgentTask?
    let isSelected: Bool
    let runningTaskCount: Int
    let openTaskCount: Int
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onOpenInFinder: () -> Void
    let onOpenInTerminal: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            projectIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(project.directoryURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                let taskForProject = activeTask.flatMap { $0.projectID == project.id ? $0 : nil }
                activeTaskLabel(taskForProject)
                    .opacity(taskForProject != nil ? 1 : 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if openTaskCount > 0 {
                    openTasksBadge
                }

                if runningTaskCount > 0 {
                    runningBadge
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: onOpenInFinder) {
                Label("Open in Finder", systemImage: "folder")
            }
            Button(action: onOpenInTerminal) {
                Label("Open in Terminal", systemImage: "terminal")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Delete Project", systemImage: "trash")
            }
        }
    }

    private var projectIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 32, height: 32)

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Delete Project")
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var runningBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)

            if runningTaskCount > 1 {
                Text("\(runningTaskCount)")
                    .font(.caption2.monospacedDigit())
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(Color.green.opacity(0.12))
        }
    }

    private var openTasksBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.orange)
                .frame(width: 5, height: 5)

            Text("\(openTaskCount)")
                .font(.caption2.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(Color.orange.opacity(0.12))
        }
    }

    private func activeTaskLabel(_ task: AgentTask?) -> some View {
        Label(task?.name ?? "", systemImage: "terminal.fill")
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.top, 1)
    }
}
