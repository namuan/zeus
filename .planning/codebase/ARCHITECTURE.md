# Architecture

**Analysis Date:** 2026-03-17

## Pattern Overview

**Overall:** Loosely-coupled MVVM with Actor-based concurrency (Swift 6).

**Key Characteristics:**
- SwiftUI views observe data from `AppDatabase` and `TerminalStore` via `@EnvironmentObject`.
- State is persisted in SQLite via GRDB, with `ValueObservation` driving UI updates.
- Process execution is isolated to `OrchestratorActor` (`@globalActor`).
- Terminal emulation uses SwiftTerm (`LocalProcessTerminalView`) wrapped in `NSViewRepresentable`.
- Configuration is centralized in `AppConfig` (JSON-based) and injected via SwiftUI Environment.

## Layers

**Models:**
- Purpose: Pure data structures representing domain entities.
- Location: `Sources/OpenZeus/Models/`
- Contains: `Project`, `AgentTask`, `AgentStatus`, `TerminalState`, `WatchMode`, `SavedCommand`, `ProjectApp`.
- Depends on: `GRDB` (for `FetchableRecord`, `PersistableRecord`).
- Used by: `Core` (database), `Views` (display).

**Core:**
- Purpose: Application infrastructure, data persistence, concurrency management.
- Location: `Sources/OpenZeus/Core/`
- Contains: `AppDatabase`, `OrchestratorActor`, `AppConfig`.
- Depends on: `GRDB`, `SwiftUI`.
- Used by: `Views` (data access), `Models`.

**Views:**
- Purpose: User interface and view logic.
- Location: `Sources/OpenZeus/Views/`
- Contains: `ContentView`, `ProjectList`, `TaskList`, `TerminalView`, `SettingsView`, `QuickCommandsView`, `TerminalStore`.
- Depends on: `Models`, `Core`, `SwiftTerm`.
- Used by: `OpenZeusApp` (entry point).

**Services:**
- Purpose: Specialized background tasks and system integrations.
- Location: `Sources/OpenZeus/Services/`
- Contains: `ActivityNotifier` (notifications), `GitService` (git operations), `WorktreeService` (git worktrees), `FileLogger` (logging).
- Depends on: `Foundation`, `AppKit`.
- Used by: `Views` (TerminalView uses GitService/WorktreeService), `Core` (AppConfig uses FileLogger).

## Data Flow

**Database to UI:**
1. `AppDatabase` initializes GRDB `DatabaseQueue` and sets up `ValueObservation` for each table.
2. Changes in SQLite automatically trigger observations, updating `@Published` properties (`projects`, `tasks`, `savedCommands`).
3. SwiftUI views observe these properties via `@EnvironmentObject var appDatabase: AppDatabase`.
4. Views call methods on `appDatabase` (e.g., `insertTask`, `updateTask`) to persist changes.

**Terminal Interaction:**
1. `ContentView` passes `AgentTask` to `TerminalPane`.
2. `TerminalPane` gets a `TerminalEntry` from `TerminalStore` (keyed by task ID).
3. `TerminalEntry` manages a `LocalProcessTerminalView` (SwiftTerm) and polls tmux session state.
4. User actions (typing, commands) go through `TerminalEntry` methods (`sendCommand`, `splitHorizontal`, etc.).
5. `TerminalEntry` executes shell commands via `runProcessOutput` or `tmux send-keys`.

**Process Execution:**
1. `OrchestratorActor.launch(task:)` spawns a `Process` (system process) and stores it in `runningProcesses`.
2. (Note: `OrchestratorActor` is present but currently less used than the direct PTY/tmux approach in `TerminalEntry`).

## Key Abstractions

**AppDatabase:**
- Purpose: Central data access layer and observation source.
- Examples: `Sources/OpenZeus/Core/AppDatabase.swift`
- Pattern: Singleton-like (injected as EnvironmentObject), `@MainActor`, `ObservableObject`.

**OrchestratorActor:**
- Purpose: Global actor isolating process management.
- Examples: `Sources/OpenZeus/Core/OrchestratorActor.swift`
- Pattern: `@globalActor`, singleton.

**TerminalStore:**
- Purpose: Caches `TerminalEntry` instances and tracks active/attention states.
- Examples: `Sources/OpenZeus/Views/TerminalStore.swift`
- Pattern: `@MainActor`, `ObservableObject`.

**TerminalEntry:**
- Purpose: Represents a single terminal session for a task.
- Examples: `Sources/OpenZeus/Views/TerminalStore.swift` (inside)
- Pattern: `@MainActor`, `ObservableObject`, manages `LocalProcessTerminalView`.

## Entry Points

**App Entry:**
- Location: `Sources/OpenZeus/OpenZeusApp.swift`
- Triggers: System launch (`@main`).
- Responsibilities: Initializes `AppConfig`, `TerminalStore`, `AppDatabase`; sets up `WindowGroup`.

**Main View:**
- Location: `Sources/OpenZeus/Views/ContentView.swift`
- Triggers: `WindowGroup` body.
- Responsibilities: Three-column layout (`NavigationSplitView`), project/task selection, state persistence.

## Error Handling

**Strategy:** Mixed. Critical paths (DB init) use `try!` or `try?`. Non-critical paths (logging, user actions) use `try?` or ignore errors.

**Patterns:**
- `try? dbQueue.write { ... }` for DB operations in `AppDatabase`.
- `do { ... } catch { print(...) }` in `WorktreeService` and `GitService`.
- Force try `try! AppDatabase(storage: config.storage)` in app init (crashes on DB failure).

## Cross-Cutting Concerns

**Logging:** `FileLogger` (custom implementation) with rolling files. Global functions `logDebug`, `logInfo`, etc.
**Validation:** Minimal. mostly implicitly handled by models and database constraints.
**Authentication:** Not applicable (local app).
