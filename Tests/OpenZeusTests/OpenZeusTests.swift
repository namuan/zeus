import Foundation
import GRDB
import Testing
@testable import OpenZeus

// MARK: - AppConfig tests

@Test func appConfigDecodesFullJSON() throws {
    let json = """
    {
        "terminal": { "pollIntervalSeconds": 5.0, "tmuxSessionPrefix": "test-" },
        "logging": { "maxFileSizeBytes": 1048576 },
        "notifications": { "soundName": "Glass" },
        "storage": { "databaseFileName": "custom.db" },
        "git": { "executablePath": "/usr/local/bin/git" },
        "ui": { "projectListMinWidth": 250 }
    }
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.terminal.pollIntervalSeconds == 5.0)
    #expect(config.terminal.tmuxSessionPrefix == "test-")
    #expect(config.logging.maxFileSizeBytes == 1_048_576)
    #expect(config.notifications.soundName == "Glass")
    #expect(config.storage.databaseFileName == "custom.db")
    #expect(config.git.executablePath == "/usr/local/bin/git")
    #expect(config.ui.projectListMinWidth == 250)
}

@Test func appConfigUsesDefaultsForMissingKeys() throws {
    let json = """
    { "terminal": { "pollIntervalSeconds": 3.0 } }
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.terminal.pollIntervalSeconds == 3.0)
    // Missing keys within terminal section fall back to defaults
    #expect(config.terminal.tmuxSettleDelayMs == 200)
    #expect(config.terminal.tmuxSessionPrefix == "zeus-")
    // Entirely missing sections fall back to defaults
    #expect(config.logging.maxFileSizeBytes == 5_242_880)
    #expect(config.notifications.soundName == "Tink")
    #expect(config.storage.appSupportFolderName == "OpenZeus")
    #expect(config.git.executablePath == "/usr/bin/git")
    #expect(config.ui.projectListMinWidth == 200)
}

@Test func appConfigFallsBackToDefaultsOnInvalidJSON() {
    let badData = Data("not valid json {{{".utf8)
    let result = (try? JSONDecoder().decode(AppConfig.self, from: badData))
    #expect(result == nil)  // decoder throws; load() would return .defaults
    // Verify defaults are sensible
    let defaults = AppConfig.defaults
    #expect(defaults.terminal.pollIntervalSeconds == 2.0)
    #expect(defaults.logging.logFileName == "openzeus.log")
}

@Test func appConfigDecodesEmptyObject() throws {
    let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
    #expect(config.terminal.pollIntervalSeconds == 2.0)
    #expect(config.terminal.tmuxSessionPrefix == "zeus-")
    #expect(config.logging.logsDirectory == "Library/Logs/OpenZeus")
    #expect(config.notifications.notificationTitle == "Agent finished")
    #expect(config.storage.databaseFileName == "app.db")
    #expect(config.git.executablePath == "/usr/bin/git")
    #expect(config.ui.quickCommandsWidth == 440)
}

@Test func agentStatusCodable() throws {
    let statuses: [AgentStatus] = [.idle, .running, .stopped, .error]
    for status in statuses {
        let data = try #require(try? JSONEncoder().encode(status))
        let decoded = try #require(try? JSONDecoder().decode(AgentStatus.self, from: data))
        #expect(decoded == status)
    }
}

@Test func terminalStateRoundTrip() throws {
    let state = TerminalState(
        lastCommand: "swift build",
        scrollOffset: 42.0,
        customPrompt: "> ",
        environmentOverrides: ["KEY": "VALUE"]
    )
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(TerminalState.self, from: data)
    #expect(decoded == state)
}

@Test func terminalStateEquality() {
    let a = TerminalState(lastCommand: nil, scrollOffset: nil, customPrompt: nil, environmentOverrides: [:])
    let b = TerminalState(lastCommand: nil, scrollOffset: nil, customPrompt: nil, environmentOverrides: [:])
    #expect(a == b)
}

@Test @MainActor func savedCommandInsertAndFetch() throws {
    let db = try AppDatabase(inMemory: ())
    let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/tmp"))
    db.insertProject(project)
    let cmd = SavedCommand(id: UUID(), projectID: project.id, command: "swift build")
    db.insertSavedCommand(cmd)
    // Allow ValueObservation to fire
    let fetched = db.savedCommands(for: project.id)
    #expect(fetched.count == 1)
    #expect(fetched.first?.command == "swift build")
    #expect(fetched.first?.projectID == project.id)
}

@Test @MainActor func savedCommandDeleteWorks() throws {
    let db = try AppDatabase(inMemory: ())
    let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/tmp"))
    db.insertProject(project)
    let cmd = SavedCommand(id: UUID(), projectID: project.id, command: "echo hello")
    db.insertSavedCommand(cmd)
    db.deleteSavedCommand(id: cmd.id)
    let fetched = db.savedCommands(for: project.id)
    #expect(fetched.isEmpty)
}

@Test @MainActor func staleMigrationRecordsAreRemovedOnOpen() throws {
    let fileManager = FileManager.default
    let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: folder) }

    let path = folder.appendingPathComponent("app.db").path
    let queue = try DatabaseQueue(path: path)

    // Simulate a DB that went through all v1–v10 migrations (the abandoned-branch path).
    try queue.write { db in
        try db.create(table: "grdb_migrations") { t in
            t.primaryKey("identifier", .text)
        }
        for version in ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10"] {
            try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES (?)", arguments: [version])
        }
        try db.create(table: "projects") { t in
            t.primaryKey("id", .text)
            t.column("name", .text).notNull()
            t.column("directoryURL", .text).notNull()
        }
        try db.create(table: "tasks") { t in
            t.primaryKey("id", .text)
            t.column("projectId", .text)
            t.column("name", .text).notNull()
            t.column("taskDescription", .text)
            t.column("command", .text).notNull()
            t.column("environment", .text).notNull().defaults(to: "{}")
            t.column("workingDirectory", .text).notNull()
            t.column("status", .text).notNull().defaults(to: "idle")
            t.column("terminalState", .text)
            t.column("watchMode", .text).notNull().defaults(to: "off")
            t.column("isArchived", .integer).notNull().defaults(to: 0)
            t.column("worktreePath", .text)
            t.column("worktreeBranch", .text)
        }
        try db.create(table: "savedCommands") { t in
            t.primaryKey("id", .text)
            t.column("projectId", .text)
            t.column("command", .text).notNull()
        }
        try db.create(table: "projectApps") { t in
            t.primaryKey("id", .text)
            t.column("projectId", .text)
            t.column("appPath", .text).notNull()
            t.column("displayName", .text).notNull()
        }
        try db.create(table: "commandUsage") { t in
            t.column("commandId", .text).notNull()
            t.column("projectId", .text).notNull()
            t.column("count", .integer).notNull().defaults(to: 0)
            t.primaryKey(["commandId", "projectId"])
        }
    }

    _ = try AppDatabase(path: path)

    let applied = try queue.read { db in
        try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
    }
    #expect(!applied.contains("v5"))
    #expect(!applied.contains("v9"))
    #expect(!applied.contains("v10"))
    #expect(applied.contains("v1"))
    #expect(applied.contains("v8"))
}

@Test @MainActor func savedCommandsPersistAcrossDatabaseRestart() throws {
    let fileManager = FileManager.default
    let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: folder) }

    let path = folder.appendingPathComponent("app.db").path

    do {
        let db = try AppDatabase(path: path)
        let project = Project(id: UUID(), name: "Persisted", directoryURL: folder)
        db.insertProject(project)
        db.insertSavedCommand(SavedCommand(id: UUID(), projectID: project.id, command: "swift run OpenZeus"))
    }

    let queue = try DatabaseQueue(path: path)
    let rows = try queue.read { db in
        try Row.fetchAll(db, sql: "SELECT projectId, command FROM savedCommands")
    }
    #expect(rows.count == 1)
    #expect((rows.first?["command"] as String?) == "swift run OpenZeus")

    let reopened = try AppDatabase(path: path)
    let reopenedProject = try #require(reopened.projects.first)
    let fetched = reopened.savedCommands(for: reopenedProject.id)
    #expect(fetched.count == 1)
    #expect(fetched.first?.command == "swift run OpenZeus")
}
