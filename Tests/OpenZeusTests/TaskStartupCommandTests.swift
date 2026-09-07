import AppKit
import Foundation
import GRDB
import Testing
@testable import OpenZeus

@MainActor
private struct StartupFixture {
    let database: AppDatabase
    let project: Project
    let command: SavedCommand

    init(global: Bool = false, commandText: String = "npm i && cd mocks && npm i && cd ..") throws {
        database = try AppDatabase(inMemory: ())
        project = Project(id: UUID(), name: "Startup", directoryURL: URL(fileURLWithPath: "/project"))
        command = SavedCommand(id: UUID(), projectID: global ? nil : project.id, command: commandText)
        database.insertProject(project)
        database.insertSavedCommand(command)
        try database.setStartupCommand(command.id, for: project.id)
    }

    func task() -> AgentTask {
        AgentTask(
            id: UUID(), projectID: project.id, name: "Task", command: "/bin/bash",
            environment: [:], workingDirectory: project.directoryURL, status: .idle
        )
    }
}

private func startupTestDirectory() throws -> URL {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent("_verify/startup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test(arguments: [false, true])
@MainActor func startupCommandSnapshotsProjectAndGlobalCommands(global: Bool) throws {
    let fixture = try StartupFixture(global: global)
    let task = fixture.task()
    try fixture.database.insertNewTask(task)
    fixture.database.updateSavedCommand(SavedCommand(
        id: fixture.command.id, projectID: fixture.command.projectID, command: "different command"
    ))
    try fixture.database.setStartupCommand(nil, for: fixture.project.id)

    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == fixture.command.command)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test @MainActor func startupCommandIsNotScheduledForQuickOrExistingTasks() throws {
    let fixture = try StartupFixture()
    let quickTask = fixture.task()
    fixture.database.insertTask(quickTask)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: quickTask.id) == nil)

    try fixture.database.setStartupCommand(nil, for: fixture.project.id)
    let disabledTask = fixture.task()
    try fixture.database.insertNewTask(disabledTask)
    try fixture.database.setStartupCommand(fixture.command.id, for: fixture.project.id)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: disabledTask.id) == nil)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: quickTask.id) == nil)
}

@Test @MainActor func startupCommandRejectsCommandsOutsideProjectScope() throws {
    let fixture = try StartupFixture()
    let otherProject = Project(id: UUID(), name: "Other", directoryURL: fixture.project.directoryURL)
    fixture.database.insertProject(otherProject)
    #expect(throws: TaskStartupCommand.ConfigurationError.self) {
        try fixture.database.setStartupCommand(fixture.command.id, for: otherProject.id)
    }
    #expect(throws: TaskStartupCommand.ConfigurationError.self) {
        try fixture.database.setStartupCommand(UUID(), for: fixture.project.id)
    }
}

@Test @MainActor func startupCommandDeletionDisablesFutureTasksButPreservesSnapshots() throws {
    let fixture = try StartupFixture()
    let pendingTask = fixture.task()
    try fixture.database.insertNewTask(pendingTask)
    fixture.database.deleteSavedCommand(id: fixture.command.id)
    let nextTask = fixture.task()
    try fixture.database.insertNewTask(nextTask)

    #expect(try fixture.database.takeTaskStartupCommand(taskID: pendingTask.id) == fixture.command.command)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: nextTask.id) == nil)
    #expect(fixture.database.projects.first?.startupCommandID == nil)
}

@Test @MainActor func startupCommandMovedToAnotherProjectIsNotScheduled() throws {
    let fixture = try StartupFixture(global: true)
    let otherProject = Project(id: UUID(), name: "Other", directoryURL: fixture.project.directoryURL)
    fixture.database.insertProject(otherProject)
    fixture.database.demoteToProject(id: fixture.command.id, projectID: otherProject.id)
    let task = fixture.task()
    try fixture.database.insertNewTask(task)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test(arguments: ["", "   ", "echo first\necho second", "echo first\recho second", "echo \u{1b}[A"])
@MainActor func startupCommandRejectsInvalidCommandLines(commandText: String) throws {
    let database = try AppDatabase(inMemory: ())
    let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/project"))
    let command = SavedCommand(id: UUID(), projectID: project.id, command: commandText)
    database.insertProject(project)
    database.insertSavedCommand(command)
    #expect(!TaskStartupCommand.isValid(commandText))
    #expect(throws: TaskStartupCommand.ConfigurationError.self) {
        try database.setStartupCommand(command.id, for: project.id)
    }
}

@Test @MainActor func startupCommandInvalidatedAfterConfigurationIsNotScheduled() throws {
    let fixture = try StartupFixture()
    fixture.database.updateSavedCommand(SavedCommand(
        id: fixture.command.id, projectID: fixture.project.id, command: "echo first\necho second"
    ))
    let task = fixture.task()
    try fixture.database.insertNewTask(task)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test @MainActor func startupCommandRemainsConsumedAfterTaskMetadataChanges() throws {
    let fixture = try StartupFixture()
    var task = fixture.task()
    try fixture.database.insertNewTask(task)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) != nil)
    task.name = "Renamed"
    task.notes = "Updated notes"
    fixture.database.updateTask(task)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test @MainActor func startupCommandIsRemovedWithTaskAndNotTakenWhileArchived() throws {
    let fixture = try StartupFixture()
    var task = fixture.task()
    try fixture.database.insertNewTask(task)
    task.isArchived = true
    fixture.database.updateTask(task)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == nil)
    fixture.database.deleteTask(id: task.id)
    task.isArchived = false
    fixture.database.insertTask(task)
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test @MainActor func startupCommandAndConsumptionPersistAcrossDatabaseRestarts() throws {
    let directory = try startupTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("app.db").path
    let project = Project(id: UUID(), name: "Persisted", directoryURL: directory)
    let command = SavedCommand(id: UUID(), projectID: nil, command: "echo persisted")
    let task = AgentTask(
        id: UUID(), projectID: project.id, name: "Task", command: "/bin/bash",
        environment: [:], workingDirectory: directory, status: .idle
    )
    do {
        let database = try AppDatabase(path: path)
        database.insertProject(project)
        database.insertSavedCommand(command)
        try database.setStartupCommand(command.id, for: project.id)
        try database.insertNewTask(task)
    }
    do {
        let database = try AppDatabase(path: path)
        #expect(database.projects.first?.startupCommandID == command.id)
        #expect(try database.takeTaskStartupCommand(taskID: task.id) == command.command)
    }
    let database = try AppDatabase(path: path)
    #expect(try database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test @MainActor func startupCommandInsertFailureDoesNotReplacePendingCommand() throws {
    let fixture = try StartupFixture()
    let task = fixture.task()
    try fixture.database.insertNewTask(task)
    #expect(throws: (any Error).self) {
        try fixture.database.insertNewTask(task)
    }
    #expect(try fixture.database.takeTaskStartupCommand(taskID: task.id) == fixture.command.command)
}

@Test @MainActor func startupCommandMigrationPreservesExistingProjectsAndTasks() throws {
    let directory = try startupTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("app.db").path
    let queue = try DatabaseQueue(path: path)
    let project = Project(id: UUID(), name: "Legacy", directoryURL: directory)
    let task = AgentTask(
        id: UUID(), projectID: project.id, name: "Existing", command: "/bin/bash",
        environment: [:], workingDirectory: directory, status: .idle
    )
    do {
        let database = try AppDatabase(databaseQueue: queue)
        database.insertProject(project)
        database.insertTask(task)
    }
    try queue.write { db in
        try db.execute(sql: "DROP TABLE taskStartupCommands")
        try db.execute(sql: "ALTER TABLE projects DROP COLUMN startupCommandId")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v15'")
    }
    let database = try AppDatabase(path: path)
    #expect(database.projects.first?.name == project.name)
    #expect(database.projects.first?.startupCommandID == nil)
    #expect(database.task(id: task.id)?.name == task.name)
    #expect(try database.takeTaskStartupCommand(taskID: task.id) == nil)
}

@Test func startupCommandTmuxLaunchQueuesLiteralInputAfterSessionCreation() {
    let arguments = TaskStartupCommand.tmuxLaunchArguments(
        sessionName: "test", shell: "/bin/bash", workingDirectory: "/worktree with spaces",
        startupCommand: "npm i && cd mocks && npm i && cd ..;"
    )
    #expect(arguments == [
        "new-session", "-A", "-c", "/worktree with spaces", "-s", "test", "/bin/bash", "-l",
        ";", "send-keys", "-t", "test", "-l", "--", "npm i && cd mocks && npm i && cd ..\\;",
        ";", "send-keys", "-t", "test", "Enter"
    ])
    let reopened = TaskStartupCommand.tmuxLaunchArguments(
        sessionName: "test", shell: "/bin/bash", workingDirectory: "/project", startupCommand: nil
    )
    #expect(!reopened.contains("send-keys"))
}

private func runStartupTestProcess(_ executable: String, arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

private func waitForStartupOutput(_ url: URL, expected: String) async throws {
    for _ in 0..<200 {
        if (try? String(contentsOf: url, encoding: .utf8)) == expected { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(try String(contentsOf: url, encoding: .utf8) == expected)
}

@Test(arguments: ["/bin/bash", "/bin/zsh"])
@MainActor func startupCommandRunsOnceInWorktreeWithTmux(shell: String) async throws {
    guard let tmux = tmuxExecutable() else { return }
    let directory = try startupTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let worktree = directory.appendingPathComponent("worktree with spaces")
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    try "sleep 0.2\n".write(to: directory.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)
    try "sleep 0.2\n".write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
    let socket = "zeus-startup-test-\(UUID().uuidString)"
    let prefix = ["-L", socket, "-f", "/dev/null"]
    defer { _ = try? runStartupTestProcess(tmux, arguments: prefix + ["kill-server"]) }
    let commandText = "pwd >> output && mkdir mocks && cd mocks && pwd >> ../output && cd .. && printf 'done\\n' >> output;"
    let fixture = try StartupFixture(commandText: commandText)
    var task = fixture.task()
    task.worktreePath = worktree.path
    try fixture.database.insertNewTask(task)
    let command = try fixture.database.takeTaskStartupCommand(taskID: task.id)
    var arguments = TaskStartupCommand.tmuxLaunchArguments(
        sessionName: "task", shell: shell, workingDirectory: task.effectiveWorkingDirectory, startupCommand: command
    )
    arguments.insert(contentsOf: ["-e", "HOME=\(directory.path)", "-e", "ZDOTDIR=\(directory.path)"], at: 1)
    let entry = TerminalEntry(taskID: task.id)
    entry.terminalView.startProcess(
        executable: tmux, args: prefix + arguments,
        environment: ["HOME=\(directory.path)", "PATH=/usr/bin:/bin", "TERM=xterm-256color"],
        currentDirectory: task.effectiveWorkingDirectory
    )
    defer { entry.terminalView.process?.terminate() }
    #expect(entry.terminalView.process?.running == true)
    let expected = "\(worktree.path)\n\(worktree.path)/mocks\ndone\n"
    let output = worktree.appendingPathComponent("output")
    try await waitForStartupOutput(output, expected: expected)

    let reopenedCommand = try fixture.database.takeTaskStartupCommand(taskID: task.id)
    #expect(reopenedCommand == nil)
    var reopenedArguments = TaskStartupCommand.tmuxLaunchArguments(
        sessionName: "task", shell: shell, workingDirectory: task.effectiveWorkingDirectory, startupCommand: reopenedCommand
    )
    reopenedArguments.insert("-d", at: 1)
    _ = try runStartupTestProcess(tmux, arguments: prefix + reopenedArguments)
    #expect(try runStartupTestProcess(tmux, arguments: prefix + ["new-window", "-d", "-t", "task", shell]) == 0)
    #expect(try runStartupTestProcess(tmux, arguments: prefix + ["split-window", "-d", "-t", "task", shell]) == 0)
    try await Task.sleep(for: .milliseconds(100))
    #expect(try String(contentsOf: output, encoding: .utf8) == expected)
}

@Test(arguments: ["/bin/bash", "/bin/zsh"])
@MainActor func startupCommandRunsInDirectTerminal(shell: String) async throws {
    let directory = try startupTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let entry = TerminalEntry(taskID: UUID())
    entry.terminalView.startProcess(
        executable: shell, args: ["-l"],
        environment: ["HOME=\(directory.path)", "ZDOTDIR=\(directory.path)", "PATH=/usr/bin:/bin", "TERM=xterm-256color"],
        currentDirectory: directory.path
    )
    defer { entry.terminalView.process?.terminate() }
    #expect(entry.terminalView.process?.running == true)
    let bytes = Array("printf 'first\\n' >> output && printf 'second\\n' >> output\n".utf8)
    entry.terminalView.send(data: bytes[...])
    try await waitForStartupOutput(directory.appendingPathComponent("output"), expected: "first\nsecond\n")
}
