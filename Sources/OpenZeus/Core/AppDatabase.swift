import Combine
import Foundation
import GRDB

@MainActor
final class AppDatabase: ObservableObject {
    private let dbQueue: DatabaseQueue
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tasks: [AgentTask] = []

    private var cancellables: [AnyDatabaseCancellable] = []

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("OpenZeus", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: folder.appendingPathComponent("app.db").path)
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
}
