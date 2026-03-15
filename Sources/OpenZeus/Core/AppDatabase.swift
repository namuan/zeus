import Combine
import Foundation
import GRDB

@MainActor
final class AppDatabase: ObservableObject {
    private let dbQueue: DatabaseQueue
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tasks: [AgentTask] = []
    @Published private(set) var savedCommands: [SavedCommand] = []
    @Published private(set) var projectApps: [ProjectApp] = []

    private var cancellables: [AnyDatabaseCancellable] = []

    convenience init(storage: StorageConfig = StorageConfig()) throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent(storage.appSupportFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try self.init(path: folder.appendingPathComponent(storage.databaseFileName).path)
    }

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrate(dbQueue)
        startObserving()
    }

    convenience init(inMemory: Void) throws {
        try self.init(path: ":memory:")
    }

    init(databaseQueue: DatabaseQueue) throws {
        dbQueue = databaseQueue
        try Self.migrate(dbQueue)
        startObserving()
    }

    // MARK: - Schema

    private static func migrate(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "projects") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("directoryURL", .text).notNull()
            }
            try db.create(table: "tasks") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).references("projects", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("taskDescription", .text)
                t.column("command", .text).notNull()
                t.column("environment", .text).notNull().defaults(to: "{}")
                t.column("workingDirectory", .text).notNull()
                t.column("status", .text).notNull().defaults(to: "idle")
                t.column("terminalState", .text)
            }
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "watchMode", .text).notNull().defaults(to: "off")
            }
        }
        migrator.registerMigration("v3") { db in
            try db.alter(table: "tasks") { t in
                t.add(column: "isArchived", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v4") { db in
            try db.create(table: "savedCommands") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).references("projects", onDelete: .cascade)
                t.column("command", .text).notNull()
            }
        }
        migrator.registerMigration("v5") { db in
            let savedCommandColumns = try db.columns(in: "savedCommands").map(\.name)
            guard savedCommandColumns.contains("name") else { return }

            try db.create(table: "savedCommands_v2") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).references("projects", onDelete: .cascade)
                t.column("command", .text).notNull()
            }
            try db.execute(sql: """
                INSERT INTO savedCommands_v2 (id, projectId, command)
                SELECT id, projectId, command
                FROM savedCommands
                """)
            try db.drop(table: "savedCommands")
            try db.rename(table: "savedCommands_v2", to: "savedCommands")
        }
        migrator.registerMigration("v6") { db in
            try db.create(table: "projectApps") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).references("projects", onDelete: .cascade)
                t.column("appPath", .text).notNull()
                t.column("displayName", .text).notNull()
            }
        }
        try migrator.migrate(db)
    }

    // MARK: - Observation

    private func startObserving() {
        cancellables.append(
            ValueObservation
                .tracking { db in try Project.order(Column("name")).fetchAll(db) }
                .start(in: dbQueue, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] in
                    self?.projects = $0
                })
        )
        cancellables.append(
            ValueObservation
                .tracking { db in try AgentTask.fetchAll(db) }
                .start(in: dbQueue, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] in
                    self?.tasks = $0
                })
        )
        cancellables.append(
            ValueObservation
                .tracking { db in try SavedCommand.fetchAll(db) }
                .start(in: dbQueue, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] in
                    self?.savedCommands = $0
                })
        )
        cancellables.append(
            ValueObservation
                .tracking { db in try ProjectApp.fetchAll(db) }
                .start(in: dbQueue, scheduling: .immediate, onError: { _ in }, onChange: { [weak self] in
                    self?.projectApps = $0
                })
        )
    }

    // MARK: - Projects

    func insertProject(_ project: Project) {
        try? dbQueue.write { db in try project.insert(db) }
    }

    func deleteProject(id: UUID) {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM projects WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Tasks

    func tasks(for projectID: UUID) -> [AgentTask] {
        tasks.filter { $0.projectID == projectID }
    }

    func task(id: UUID) -> AgentTask? {
        tasks.first { $0.id == id }
    }

    func insertTask(_ task: AgentTask) {
        try? dbQueue.write { db in try task.insert(db) }
    }

    func updateTask(_ task: AgentTask) {
        try? dbQueue.write { db in try task.update(db) }
    }

    func deleteTask(id: UUID) {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Project Apps

    func projectApps(for projectID: UUID) -> [ProjectApp] {
        projectApps.filter { $0.projectID == projectID }
    }

    func insertProjectApp(_ app: ProjectApp) {
        try? dbQueue.write { db in try app.insert(db) }
    }

    func deleteProjectApp(id: UUID) {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM projectApps WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Saved Commands

    func savedCommands(for projectID: UUID) -> [SavedCommand] {
        savedCommands.filter { $0.projectID == projectID || $0.isGlobal }
    }

    func promoteToGlobal(id: UUID) {
        guard let cmd = savedCommands.first(where: { $0.id == id }) else { return }
        updateSavedCommand(SavedCommand(id: cmd.id, projectID: nil, command: cmd.command))
    }

    func demoteToProject(id: UUID, projectID: UUID) {
        guard let cmd = savedCommands.first(where: { $0.id == id }) else { return }
        updateSavedCommand(SavedCommand(id: cmd.id, projectID: projectID, command: cmd.command))
    }

    func insertSavedCommand(_ command: SavedCommand) {
        do {
            try dbQueue.write { db in try command.insert(db) }
            if !savedCommands.contains(where: { $0.id == command.id }) {
                savedCommands.append(command)
            }
        } catch {
            print("Failed to insert saved command: \(error)")
        }
    }

    func updateSavedCommand(_ command: SavedCommand) {
        do {
            try dbQueue.write { db in try command.update(db) }
            if let idx = savedCommands.firstIndex(where: { $0.id == command.id }) {
                savedCommands[idx] = command
            }
        } catch {
            print("Failed to update saved command: \(error)")
        }
    }

    func deleteSavedCommand(id: UUID) {
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM savedCommands WHERE id = ?", arguments: [id.uuidString])
            }
            savedCommands.removeAll { $0.id == id }
        } catch {
            print("Failed to delete saved command: \(error)")
        }
    }
}
