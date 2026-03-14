# Application Configuration

## Context

OpenZeus has numerous hardcoded values scattered across the codebase — polling intervals, file paths, executable search paths, font settings, notification content, and UI dimensions. Introducing a centralized configuration system will:

- Allow users to tune behavior without recompiling
- Make defaults discoverable and documented in one place
- Reduce magic numbers scattered across source files
- Enable future preferences UI to bind directly to config keys

## Approach

Introduce a new `AppConfig` struct loaded from a JSON file at `~/Library/Application Support/OpenZeus/config.json`. Config is loaded once at app startup and injected into the SwiftUI environment. Sensible defaults are embedded in the struct so the app works identically if no config file exists.

**Why JSON over UserDefaults?** UserDefaults is already used for UI state (last selected project/task). Configuration should be a separate concern — a file users can hand-edit, back up, and version control. JSON is human-readable and has no framework dependency.

## New Files

### `Sources/OpenZeus/Core/AppConfig.swift`

Single file containing:

```swift
struct AppConfig: Codable, Sendable {
    let terminal: TerminalConfig
    let logging: LoggingConfig
    let notifications: NotificationConfig
    let storage: StorageConfig
    let git: GitConfig
    let ui: UIConfig

    static let defaults: AppConfig = { ... }()

    static func load() -> AppConfig { ... }
}
```

Each section is a nested struct with `Codable` conformance. Every property has a default value so partial configs work (only override what you want).

### `docs/config.example.json`

Annotated example config file showing every key with its default and a comment explaining what it controls.

## Configuration Schema

### `terminal` — Process and terminal behavior

| Key | Type | Default | Current location |
|-----|------|---------|-----------------|
| `pollIntervalSeconds` | Double | `2.0` | `TerminalStore.swift:70` |
| `tmuxSettleDelayMs` | Int | `200` | `TerminalStore.swift:184` (and 6 others) |
| `orphanCleanupIntervalSeconds` | Double | `300.0` | `TerminalStore.swift:562` |
| `sigtermGracePeriodMs` | Int | `300` | `TerminalStore.swift:594` |
| `scrollTimerIntervalSeconds` | Double | `0.05` | `TerminalView.swift:499` |
| `mouseModeDelayMs` | Int | `300` | `TerminalView.swift:551` |
| `defaultShell` | String | `"$SHELL"` or `"/bin/bash"` | `TerminalView.swift:561`, `TaskList.swift:143` |
| `fontFamily` | String | `"monospacedSystemFont"` | `TerminalStore.swift:56` |
| `fontSize` | Int | `13` | `TerminalStore.swift:56` |
| `fontWeight` | String | `"regular"` | `TerminalStore.swift:56` |
| `tmuxSearchPaths` | [String] | `["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]` | `TerminalStore.swift:598` |
| `pkillPath` | String | `"/usr/bin/pkill"` | `TerminalStore.swift:591` |
| `tmuxSessionPrefix` | String | `"zeus-"` | `TerminalStore.swift:84` (and 11 others) |
| `knownShells` | [String] | `["zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login", "tmux", "tmux: server"]` | `TerminalStore.swift:47` |

### `logging` — File logger settings

| Key | Type | Default | Current location |
|-----|------|---------|-----------------|
| `logsDirectory` | String | `"Library/Logs/OpenZeus"` | `FileLogger.swift:24` |
| `logFileName` | String | `"openzeus.log"` | `FileLogger.swift:25` |
| `maxFileSizeBytes` | Int | `5242880` (5 MB) | `FileLogger.swift:10` |
| `maxBackupFiles` | Int | `5` | `FileLogger.swift:11` |
| `timestampFormat` | String | `"yyyy-MM-dd HH:mm:ss.SSS"` | `FileLogger.swift:104` |

### `notifications` — Watch mode alerts

| Key | Type | Default | Current location |
|-----|------|---------|-----------------|
| `soundName` | String | `"Tink"` | `ActivityNotifier.swift:7` |
| `notificationTitle` | String | `"Agent finished"` | `ActivityNotifier.swift:27` |
| `notificationBodyTemplate` | String | `"{taskName} has completed its task"` | `ActivityNotifier.swift:28` |

### `storage` — Database and data paths

| Key | Type | Default | Current location |
|-----|------|---------|-----------------|
| `appSupportFolderName` | String | `"OpenZeus"` | `AppDatabase.swift:17` |
| `databaseFileName` | String | `"app.db"` | `AppDatabase.swift:19` |

### `git` — Git integration

| Key | Type | Default | Current location |
|-----|------|---------|-----------------|
| `executablePath` | String | `"/usr/bin/git"` | `GitService.swift:202` |

### `ui` — Interface dimensions

| Key | Type | Default | Current location |
|-----|------|---------|-----------------|
| `projectListMinWidth` | Int | `200` | `ContentView.swift:39` |
| `projectListIdealWidth` | Int | `220` | `ContentView.swift:39` |
| `taskSheetMinWidth` | Int | `400` | `TaskList.swift:132` |
| `quickCommandsWidth` | Int | `440` | `QuickCommandsView.swift:85` |
| `quickCommandsMinHeight` | Int | `420` | `QuickCommandsView.swift:86` |
| `quickCommandsMaxHeight` | Int | `520` | `QuickCommandsView.swift:62` |

## Loading Strategy

1. On app launch, `AppConfig.load()` looks for `~/Library/Application Support/OpenZeus/config.json`
2. If file exists, parse it; merge with defaults (any missing key uses the default)
3. If file doesn't exist, use `AppConfig.defaults`
4. If parsing fails, log a warning and fall back to defaults
5. Inject via `.environmentObject` or a simple `@Environment` key in `OpenZeusApp.swift`

**Config is loaded once.** Changes require app restart. No hot-reload — keeps the model simple and avoids complexity around re-initializing running processes.

## Wiring Changes

### `OpenZeusApp.swift`
- Create `AppConfig` at startup
- Inject into SwiftUI environment via a custom `EnvironmentKey`

### Each consuming file
- Accept `AppConfig` (or the relevant section) from environment
- Replace hardcoded values with config properties
- Files affected: `AppDatabase.swift`, `OrchestratorActor.swift`, `ActivityNotifier.swift`, `FileLogger.swift`, `GitService.swift`, `TerminalStore.swift`, `TerminalView.swift`, `ContentView.swift`, `TaskList.swift`, `QuickCommandsView.swift`

### `AppDatabase.swift`
- The convenience `init()` currently hardcodes the path. Accept an optional `StorageConfig` parameter to override.

### `FileLogger.swift`
- Currently a singleton with hardcoded values. Accept `LoggingConfig` in the private initializer, or make it non-singleton and pass config from the app entry point.

### `GitService.swift`
- Accept `GitConfig` in init, use `config.executablePath` instead of hardcoded `"/usr/bin/git"`.

## Testing

- Add tests in `Tests/OpenZeusTests/` for:
  - `AppConfig` decoding from full JSON → all values correct
  - `AppConfig` decoding from partial JSON → missing keys use defaults
  - `AppConfig` decoding from invalid JSON → falls back to defaults
  - `AppConfig` decoding from empty object → all defaults
- These are pure value tests, no infrastructure needed.

## Migration

No migration needed. The app works identically with no config file present. Users opt in by creating the file.

## File list

| File | Action |
|------|--------|
| `Sources/OpenZeus/Core/AppConfig.swift` | **Create** — config structs + loader |
| `docs/config.example.json` | **Create** — documented example |
| `Sources/OpenZeus/OpenZeusApp.swift` | **Edit** — load config, inject via environment |
| `Sources/OpenZeus/Core/AppDatabase.swift` | **Edit** — accept `StorageConfig` |
| `Sources/OpenZeus/Core/OrchestratorActor.swift` | No change needed (uses `task.command` directly) |
| `Sources/OpenZeus/Services/ActivityNotifier.swift` | **Edit** — accept `NotificationConfig` |
| `Sources/OpenZeus/Services/FileLogger.swift` | **Edit** — accept `LoggingConfig` |
| `Sources/OpenZeus/Services/GitService.swift` | **Edit** — accept `GitConfig` |
| `Sources/OpenZeus/Views/TerminalStore.swift` | **Edit** — accept `TerminalConfig` |
| `Sources/OpenZeus/Views/TerminalView.swift` | **Edit** — read config from environment |
| `Sources/OpenZeus/Views/ContentView.swift` | **Edit** — read UI config from environment |
| `Sources/OpenZeus/Views/TaskList.swift` | **Edit** — read config for default command |
| `Tests/OpenZeusTests/OpenZeusTests.swift` | **Edit** — add config tests |

## Out of scope

- Preferences UI (a follow-up task that would bind a settings window to `AppConfig`)
- Hot-reload of config changes
- Per-project configuration overrides
- CLI flag overrides
