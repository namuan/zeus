import Foundation
import SwiftUI

// MARK: - Root

struct AppConfig: Codable, Equatable, Sendable {
    var terminal: TerminalConfig
    var llm: LLMConfig
    var logging: LoggingConfig
    var notifications: NotificationConfig
    var storage: StorageConfig
    var git: GitConfig
    var ui: UIConfig
    var worktree: WorktreeConfig

    init(
        terminal: TerminalConfig = .init(),
        llm: LLMConfig = .init(),
        logging: LoggingConfig = .init(),
        notifications: NotificationConfig = .init(),
        storage: StorageConfig = .init(),
        git: GitConfig = .init(),
        ui: UIConfig = .init(),
        worktree: WorktreeConfig = .init()
    ) {
        self.terminal = terminal
        self.llm = llm
        self.logging = logging
        self.notifications = notifications
        self.storage = storage
        self.git = git
        self.ui = ui
        self.worktree = worktree
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terminal      = (try? c.decode(TerminalConfig.self, forKey: .terminal))      ?? .init()
        llm           = (try? c.decode(LLMConfig.self, forKey: .llm))           ?? .init()
        logging       = (try? c.decode(LoggingConfig.self, forKey: .logging))       ?? .init()
        notifications = (try? c.decode(NotificationConfig.self, forKey: .notifications)) ?? .init()
        storage       = (try? c.decode(StorageConfig.self, forKey: .storage))       ?? .init()
        git           = (try? c.decode(GitConfig.self, forKey: .git))           ?? .init()
        ui            = (try? c.decode(UIConfig.self, forKey: .ui))            ?? .init()
        worktree      = (try? c.decode(WorktreeConfig.self, forKey: .worktree))      ?? .init()
    }

    static let defaults = AppConfig()

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent(StorageConfig().appSupportFolderName, isDirectory: true)
            .appendingPathComponent("config.json")
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.configURL)
        }
    }

    static func load() -> AppConfig {
        let url = configURL
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            AppConfig.defaults.save()
            return .defaults
        }

        guard let data = try? Data(contentsOf: url) else { return .defaults }
        guard let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            print("[AppConfig] Warning: failed to parse config.json, using defaults")
            return .defaults
        }
        return config
    }
}

// MARK: - SwiftUI Environment

private struct AppConfigKey: EnvironmentKey {
    static let defaultValue = AppConfig.defaults
}

extension EnvironmentValues {
    var appConfig: AppConfig {
        get { self[AppConfigKey.self] }
        set { self[AppConfigKey.self] = newValue }
    }
}

extension Notification.Name {
    static let appConfigChanged = Notification.Name("AppConfigChanged")
}

// MARK: - LLM

struct LLMConfig: Codable, Equatable, Sendable {
    var provider: String
    var model: String
    var apiKeyEnvironmentVariable: String

    init(
        provider: String = "anthropic",
        model: String = "claude-sonnet-4-20250514",
        apiKeyEnvironmentVariable: String = "ANTHROPIC_API_KEY"
    ) {
        self.provider = provider
        self.model = model
        self.apiKeyEnvironmentVariable = apiKeyEnvironmentVariable
    }

    init(from decoder: Decoder) throws {
        let d = LLMConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = (try? c.decode(String.self, forKey: .provider)) ?? d.provider
        model = (try? c.decode(String.self, forKey: .model)) ?? d.model
        apiKeyEnvironmentVariable = (try? c.decode(String.self, forKey: .apiKeyEnvironmentVariable)) ?? d.apiKeyEnvironmentVariable
    }
}

// MARK: - Terminal

struct TerminalConfig: Codable, Equatable, Sendable {
    var pollIntervalSeconds: Double
    var tmuxSettleDelayMs: Int
    var orphanCleanupIntervalSeconds: Double
    var sigtermGracePeriodMs: Int
    var scrollTimerIntervalSeconds: Double
    var mouseModeDelayMs: Int
    var defaultShell: String
    var fontFamily: String
    var fontSize: Int
    var fontWeight: String
    var tmuxSearchPaths: [String]
    var pkillPath: String
    var tmuxSessionPrefix: String
    var knownShells: [String]

    init(
        pollIntervalSeconds: Double = 2.0,
        tmuxSettleDelayMs: Int = 200,
        orphanCleanupIntervalSeconds: Double = 300.0,
        sigtermGracePeriodMs: Int = 300,
        scrollTimerIntervalSeconds: Double = 0.05,
        mouseModeDelayMs: Int = 300,
        defaultShell: String = "",
        fontFamily: String = "monospacedSystemFont",
        fontSize: Int = 13,
        fontWeight: String = "regular",
        tmuxSearchPaths: [String] = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"],
        pkillPath: String = "/usr/bin/pkill",
        tmuxSessionPrefix: String = "zeus-",
        knownShells: [String] = ["zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login", "tmux", "tmux: server"]
    ) {
        self.pollIntervalSeconds = pollIntervalSeconds
        self.tmuxSettleDelayMs = tmuxSettleDelayMs
        self.orphanCleanupIntervalSeconds = orphanCleanupIntervalSeconds
        self.sigtermGracePeriodMs = sigtermGracePeriodMs
        self.scrollTimerIntervalSeconds = scrollTimerIntervalSeconds
        self.mouseModeDelayMs = mouseModeDelayMs
        self.defaultShell = defaultShell
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.tmuxSearchPaths = tmuxSearchPaths
        self.pkillPath = pkillPath
        self.tmuxSessionPrefix = tmuxSessionPrefix
        self.knownShells = knownShells
    }

    init(from decoder: Decoder) throws {
        let d = TerminalConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollIntervalSeconds        = (try? c.decode(Double.self, forKey: .pollIntervalSeconds))        ?? d.pollIntervalSeconds
        tmuxSettleDelayMs          = (try? c.decode(Int.self, forKey: .tmuxSettleDelayMs))          ?? d.tmuxSettleDelayMs
        orphanCleanupIntervalSeconds = (try? c.decode(Double.self, forKey: .orphanCleanupIntervalSeconds)) ?? d.orphanCleanupIntervalSeconds
        sigtermGracePeriodMs       = (try? c.decode(Int.self, forKey: .sigtermGracePeriodMs))       ?? d.sigtermGracePeriodMs
        scrollTimerIntervalSeconds = (try? c.decode(Double.self, forKey: .scrollTimerIntervalSeconds)) ?? d.scrollTimerIntervalSeconds
        mouseModeDelayMs           = (try? c.decode(Int.self, forKey: .mouseModeDelayMs))           ?? d.mouseModeDelayMs
        defaultShell               = (try? c.decode(String.self, forKey: .defaultShell))               ?? d.defaultShell
        fontFamily                 = (try? c.decode(String.self, forKey: .fontFamily))                 ?? d.fontFamily
        fontSize                   = (try? c.decode(Int.self, forKey: .fontSize))                   ?? d.fontSize
        fontWeight                 = (try? c.decode(String.self, forKey: .fontWeight))                 ?? d.fontWeight
        tmuxSearchPaths            = (try? c.decode([String].self, forKey: .tmuxSearchPaths))            ?? d.tmuxSearchPaths
        pkillPath                  = (try? c.decode(String.self, forKey: .pkillPath))                  ?? d.pkillPath
        tmuxSessionPrefix          = (try? c.decode(String.self, forKey: .tmuxSessionPrefix))          ?? d.tmuxSessionPrefix
        knownShells                = (try? c.decode([String].self, forKey: .knownShells))                ?? d.knownShells
    }

    var resolvedShell: String {
        let s = defaultShell.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash") : s
    }
}

// MARK: - Logging

struct LoggingConfig: Codable, Equatable, Sendable {
    var logsDirectory: String
    var logFileName: String
    var maxFileSizeBytes: Int
    var maxBackupFiles: Int
    var timestampFormat: String

    init(
        logsDirectory: String = "Library/Logs/OpenZeus",
        logFileName: String = "openzeus.log",
        maxFileSizeBytes: Int = 5_242_880,
        maxBackupFiles: Int = 5,
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss.SSS"
    ) {
        self.logsDirectory = logsDirectory
        self.logFileName = logFileName
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxBackupFiles = maxBackupFiles
        self.timestampFormat = timestampFormat
    }

    init(from decoder: Decoder) throws {
        let d = LoggingConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logsDirectory    = (try? c.decode(String.self, forKey: .logsDirectory))    ?? d.logsDirectory
        logFileName      = (try? c.decode(String.self, forKey: .logFileName))      ?? d.logFileName
        maxFileSizeBytes = (try? c.decode(Int.self, forKey: .maxFileSizeBytes)) ?? d.maxFileSizeBytes
        maxBackupFiles   = (try? c.decode(Int.self, forKey: .maxBackupFiles))   ?? d.maxBackupFiles
        timestampFormat  = (try? c.decode(String.self, forKey: .timestampFormat))  ?? d.timestampFormat
    }
}

// MARK: - Notifications

struct NotificationConfig: Codable, Equatable, Sendable {
    var soundName: String
    var notificationTitle: String
    var notificationBodyTemplate: String

    init(
        soundName: String = "Tink",
        notificationTitle: String = "Agent finished",
        notificationBodyTemplate: String = "{taskName} has completed its task"
    ) {
        self.soundName = soundName
        self.notificationTitle = notificationTitle
        self.notificationBodyTemplate = notificationBodyTemplate
    }

    init(from decoder: Decoder) throws {
        let d = NotificationConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundName                = (try? c.decode(String.self, forKey: .soundName))                ?? d.soundName
        notificationTitle        = (try? c.decode(String.self, forKey: .notificationTitle))        ?? d.notificationTitle
        notificationBodyTemplate = (try? c.decode(String.self, forKey: .notificationBodyTemplate)) ?? d.notificationBodyTemplate
    }

    func body(taskName: String) -> String {
        notificationBodyTemplate.replacingOccurrences(of: "{taskName}", with: taskName)
    }
}

// MARK: - Storage

struct StorageConfig: Codable, Equatable, Sendable {
    var appSupportFolderName: String
    var databaseFileName: String

    static let appDirEnvKey = "ZEUS_APP_DIR"

    init(
        appSupportFolderName: String = ProcessInfo.processInfo.environment[appDirEnvKey] ?? "OpenZeus",
        databaseFileName: String = "app.db"
    ) {
        self.appSupportFolderName = appSupportFolderName
        self.databaseFileName = databaseFileName
    }

    init(from decoder: Decoder) throws {
        let d = StorageConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appSupportFolderName = (try? c.decode(String.self, forKey: .appSupportFolderName)) ?? d.appSupportFolderName
        databaseFileName     = (try? c.decode(String.self, forKey: .databaseFileName))     ?? d.databaseFileName
    }
}

// MARK: - Git

struct GitConfig: Codable, Equatable, Sendable {
    var executablePath: String
    var statusDebounceMs: Int
    var statusPollIntervalSeconds: Int

    init(
        executablePath: String = "/usr/bin/git",
        statusDebounceMs: Int = 300,
        statusPollIntervalSeconds: Int = 30
    ) {
        self.executablePath = executablePath
        self.statusDebounceMs = statusDebounceMs
        self.statusPollIntervalSeconds = statusPollIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let d = GitConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        executablePath          = (try? c.decode(String.self, forKey: .executablePath))          ?? d.executablePath
        statusDebounceMs        = (try? c.decode(Int.self, forKey: .statusDebounceMs))        ?? d.statusDebounceMs
        statusPollIntervalSeconds = (try? c.decode(Int.self, forKey: .statusPollIntervalSeconds)) ?? d.statusPollIntervalSeconds
    }
}

// MARK: - Worktree

struct WorktreeConfig: Codable, Equatable, Sendable {
    var basePath: String
    var defaultBaseBranch: String
    var createByDefault: Bool

    init(
        basePath: String = "",
        defaultBaseBranch: String = "main",
        createByDefault: Bool = true
    ) {
        self.basePath = basePath
        self.defaultBaseBranch = defaultBaseBranch
        self.createByDefault = createByDefault
    }

    init(from decoder: Decoder) throws {
        let d = WorktreeConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        basePath           = (try? c.decode(String.self, forKey: .basePath))           ?? d.basePath
        defaultBaseBranch  = (try? c.decode(String.self, forKey: .defaultBaseBranch))  ?? d.defaultBaseBranch
        createByDefault    = (try? c.decode(Bool.self, forKey: .createByDefault))      ?? d.createByDefault
    }

    /// Expands a leading `~` to the user's home directory.
    var resolvedBasePath: String {
        (basePath as NSString).expandingTildeInPath
    }
}

// MARK: - UI

struct UIConfig: Codable, Equatable, Sendable {
    var projectListMinWidth: Int
    var projectListIdealWidth: Int
    var taskSheetMinWidth: Int
    var quickCommandsWidth: Int
    var quickCommandsMinHeight: Int
    var quickCommandsMaxHeight: Int

    init(
        projectListMinWidth: Int = 200,
        projectListIdealWidth: Int = 220,
        taskSheetMinWidth: Int = 400,
        quickCommandsWidth: Int = 440,
        quickCommandsMinHeight: Int = 420,
        quickCommandsMaxHeight: Int = 520
    ) {
        self.projectListMinWidth = projectListMinWidth
        self.projectListIdealWidth = projectListIdealWidth
        self.taskSheetMinWidth = taskSheetMinWidth
        self.quickCommandsWidth = quickCommandsWidth
        self.quickCommandsMinHeight = quickCommandsMinHeight
        self.quickCommandsMaxHeight = quickCommandsMaxHeight
    }

    init(from decoder: Decoder) throws {
        let d = UIConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectListMinWidth   = (try? c.decode(Int.self, forKey: .projectListMinWidth))   ?? d.projectListMinWidth
        projectListIdealWidth = (try? c.decode(Int.self, forKey: .projectListIdealWidth)) ?? d.projectListIdealWidth
        taskSheetMinWidth     = (try? c.decode(Int.self, forKey: .taskSheetMinWidth))     ?? d.taskSheetMinWidth
        quickCommandsWidth    = (try? c.decode(Int.self, forKey: .quickCommandsWidth))    ?? d.quickCommandsWidth
        quickCommandsMinHeight = (try? c.decode(Int.self, forKey: .quickCommandsMinHeight)) ?? d.quickCommandsMinHeight
        quickCommandsMaxHeight = (try? c.decode(Int.self, forKey: .quickCommandsMaxHeight)) ?? d.quickCommandsMaxHeight
    }
}
