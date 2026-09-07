import SwiftUI

struct ProjectSettingsSheet: View {
    let project: Project
    @EnvironmentObject private var appDatabase: AppDatabase
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCommandID: UUID?
    @State private var errorMessage: String?

    init(project: Project) {
        self.project = project
        _selectedCommandID = State(initialValue: project.startupCommandID)
    }

    private var commands: [SavedCommand] {
        appDatabase.savedCommands(for: project.id).filter { TaskStartupCommand.isValid($0.command) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Settings")
                .font(.title2.bold())
            Text(project.name)
                .font(.headline)

            Picker("New task command", selection: $selectedCommandID) {
                Text("None").tag(nil as UUID?)
                Section("This Project") {
                    ForEach(commands.filter { !$0.isGlobal }) { command in
                        Text(command.command).tag(Optional(command.id))
                    }
                }
                Section("Global") {
                    ForEach(commands.filter(\.isGlobal)) { command in
                        Text(command.command).tag(Optional(command.id))
                    }
                }
            }
            .pickerStyle(.menu)

            Text("Runs once when a task created with New Task first opens its terminal. Uses the task’s worktree when available. Quick Task is not affected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Manage single-line commands in Quick Commands. Changes apply to tasks saved after this setting is updated. Choose None to disable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { validateSelection() }
        .onChange(of: commands) { _, _ in validateSelection() }
    }

    private func validateSelection() {
        if let selectedCommandID, !commands.contains(where: { $0.id == selectedCommandID }) {
            self.selectedCommandID = nil
        }
    }

    private func save() {
        do {
            try appDatabase.setStartupCommand(selectedCommandID, for: project.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
