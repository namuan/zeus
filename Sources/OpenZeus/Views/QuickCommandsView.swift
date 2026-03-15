import SwiftUI

struct QuickCommandsPopover: View {
    let projectID: UUID
    let onRun: (String) -> Void
    @EnvironmentObject var db: AppDatabase
    @Environment(\.appConfig) private var appConfig
    @State private var newCommand = ""
    @FocusState private var addFieldFocused: Bool

    var allCommands: [SavedCommand] { db.savedCommands(for: projectID) }
    var projectCommands: [SavedCommand] { allCommands.filter { $0.projectID == projectID } }
    var globalCommands: [SavedCommand] { allCommands.filter { $0.isGlobal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Commands")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if allCommands.isEmpty {
                Text("No saved commands yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !projectCommands.isEmpty {
                            SectionHeader("This Project")
                            ForEach(projectCommands) { cmd in
                                CommandRow(
                                    command: cmd,
                                    onRun: { run(cmd) },
                                    onSave: { db.updateSavedCommand($0) },
                                    onDelete: { db.deleteSavedCommand(id: cmd.id) },
                                    scopeAction: .promote { db.promoteToGlobal(id: cmd.id) }
                                )
                                Divider()
                            }
                        }

                        if !globalCommands.isEmpty {
                            SectionHeader("Global")
                            ForEach(globalCommands) { cmd in
                                CommandRow(
                                    command: cmd,
                                    onRun: { run(cmd) },
                                    onSave: { db.updateSavedCommand($0) },
                                    onDelete: { db.deleteSavedCommand(id: cmd.id) },
                                    scopeAction: .demote { db.demoteToProject(id: cmd.id, projectID: projectID) }
                                )
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: CGFloat(appConfig.ui.quickCommandsMaxHeight))
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Add command", text: $newCommand)
                    .textFieldStyle(.roundedBorder)
                    .fontDesign(.monospaced)
                    .focused($addFieldFocused)
                    .onSubmit { save() }

                Button(action: save) {
                    Image(systemName: "plus")
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Add command (project-specific)")
            }
            .padding(10)
        }
        .frame(width: CGFloat(appConfig.ui.quickCommandsWidth))
        .frame(minHeight: CGFloat(appConfig.ui.quickCommandsMinHeight))
        .onAppear {
            addFieldFocused = allCommands.isEmpty
        }
    }

    private func run(_ cmd: SavedCommand) {
        db.recordCommandUsage(commandID: cmd.id, projectID: projectID)
        onRun(cmd.command)
    }

    private func save() {
        let trimmed = newCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        db.insertSavedCommand(SavedCommand(id: UUID(), projectID: projectID, command: trimmed))
        newCommand = ""
        addFieldFocused = true
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

private enum ScopeAction {
    case promote(() -> Void)
    case demote(() -> Void)

    var icon: String {
        switch self {
        case .promote: "globe"
        case .demote: "folder"
        }
    }

    var help: String {
        switch self {
        case .promote: "Make global (available in all projects)"
        case .demote: "Move to this project only"
        }
    }

    func callAsFunction() {
        switch self {
        case .promote(let action), .demote(let action): action()
        }
    }
}

private struct CommandRow: View {
    let command: SavedCommand
    let onRun: () -> Void
    let onSave: (SavedCommand) -> Void
    let onDelete: () -> Void
    let scopeAction: ScopeAction

    @State private var isEditing = false
    @State private var isHovered = false
    @State private var draft: String
    @FocusState private var editFieldFocused: Bool

    init(command: SavedCommand, onRun: @escaping () -> Void, onSave: @escaping (SavedCommand) -> Void, onDelete: @escaping () -> Void, scopeAction: ScopeAction) {
        self.command = command
        self.onRun = onRun
        self.onSave = onSave
        self.onDelete = onDelete
        self.scopeAction = scopeAction
        _draft = State(initialValue: command.command)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedDraft != command.command
    }

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("Command", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .fontDesign(.monospaced)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($editFieldFocused)
                    .onSubmit(save)

                Button(action: save) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusEffectDisabled()
                .disabled(!hasChanges || trimmedDraft.isEmpty)
                .help("Save")

                Button(action: cancelEditing) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusEffectDisabled()
                .help("Cancel")
            } else {
                Button(action: startEditing) {
                    HStack(spacing: 8) {
                        Text(command.command)
                            .font(.callout)
                            .fontDesign(.monospaced)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(isHovered ? 1 : 0.5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { hovering in
                    isHovered = hovering
                }
                .help("Click to edit")
            }

            Button(action: scopeAction.callAsFunction) {
                Image(systemName: scopeAction.icon)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .focusEffectDisabled()
            .help(scopeAction.help)

            Button(action: onRun) {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .focusEffectDisabled()
            .help("Run")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .focusEffectDisabled()
            .help("Delete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onChange(of: command.command) { _, newValue in
            if !isEditing {
                draft = newValue
            }
        }
        .onChange(of: isEditing) { _, newValue in
            editFieldFocused = newValue
        }
    }

    private func startEditing() {
        draft = command.command
        isEditing = true
    }

    private func cancelEditing() {
        draft = command.command
        isEditing = false
    }

    private func save() {
        guard !trimmedDraft.isEmpty, hasChanges else { return }
        onSave(SavedCommand(id: command.id, projectID: command.projectID, command: trimmedDraft))
        isEditing = false
    }
}
