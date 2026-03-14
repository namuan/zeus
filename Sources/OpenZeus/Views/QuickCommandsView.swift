import SwiftUI

struct QuickCommandsPopover: View {
    let projectID: UUID
    let onRun: (String) -> Void
    @EnvironmentObject var db: AppDatabase
    @State private var showingAdd = false
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

            if commands.isEmpty && !showingAdd {
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
                            }, onDelete: {
                                db.deleteSavedCommand(id: cmd.id)
                            })
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider()

            if showingAdd {
                HStack(spacing: 6) {
                    TextField("Command", text: $newCommand)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .focused($addFieldFocused)
                        .onSubmit { save() }
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") {
                        showingAdd = false
                        newCommand = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
            } else {
                Button {
                    showingAdd = true
                } label: {
                    Label("New Command", systemImage: "plus")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 320)
        .onChange(of: showingAdd) { _, newValue in
            if newValue { addFieldFocused = true }
        }
    }

    private func save() {
        let trimmed = newCommand.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        db.insertSavedCommand(SavedCommand(id: UUID(), projectID: projectID, command: trimmed))
        newCommand = ""
        showingAdd = false
    }
}

private struct CommandRow: View {
    let command: SavedCommand
    let onRun: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(command.command)
                .font(.callout)
                .fontDesign(.monospaced)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRun) {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Run")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
