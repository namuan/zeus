import SwiftUI

struct QuickCommandsPopover: View {
    let projectID: UUID
    let onRun: (String) -> Void
    @EnvironmentObject var db: AppDatabase
    @State private var newCommand = ""
    @FocusState private var addFieldFocused: Bool

    var commands: [SavedCommand] { db.savedCommands(for: projectID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Commands")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if commands.isEmpty {
                Text("No saved commands yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(commands) { cmd in
                            CommandRow(command: cmd, onRun: {
                                onRun(cmd.command)
                            }, onSave: { updated in
                                db.updateSavedCommand(updated)
                            }, onDelete: {
                                db.deleteSavedCommand(id: cmd.id)
                            })
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 520)
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
                .help("Add command")
            }
            .padding(10)
        }
        .frame(width: 440)
        .frame(minHeight: 420)
        .onAppear {
            addFieldFocused = commands.isEmpty
        }
    }

    private func save() {
        let trimmed = newCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        db.insertSavedCommand(SavedCommand(id: UUID(), projectID: projectID, command: trimmed))
        newCommand = ""
        addFieldFocused = true
    }
}

private struct CommandRow: View {
    let command: SavedCommand
    let onRun: () -> Void
    let onSave: (SavedCommand) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var isHovered = false
    @State private var draft: String
    @FocusState private var editFieldFocused: Bool

    init(command: SavedCommand, onRun: @escaping () -> Void, onSave: @escaping (SavedCommand) -> Void, onDelete: @escaping () -> Void) {
        self.command = command
        self.onRun = onRun
        self.onSave = onSave
        self.onDelete = onDelete
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
                .disabled(!hasChanges || trimmedDraft.isEmpty)
                .help("Save")

                Button(action: cancelEditing) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                .onHover { hovering in
                    isHovered = hovering
                }
                .help("Click to edit")
            }

            Button(action: onRun) {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Run")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
