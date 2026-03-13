# CLAUDE.md

## Project Overview

**Open-Zeus** is a native macOS AI agent orchestrator. It provides a three-column SwiftUI interface (Projects | Tasks | Terminal) for managing, monitoring, and interacting with multiple agent processes running against local filesystem directories.

- **Language:** Swift 6
- **Platform:** macOS 15+ (Sequoia)
- **Build System:** Swift Package Manager
- **License:** MIT

## Common Commands

```bash
# Build
swift build

# Run (development)
swift run OpenZeus

# Test
swift test

# Build release + install to ~/Applications/OpenZeus.app
./install.command
```

## Architecture

### Key Files

| File | Purpose |
|------|---------|
| `Sources/OpenZeus/OpenZeusApp.swift` | `@main` entry point, WindowGroup, environment setup |
| `Sources/OpenZeus/Views/ContentView.swift` | Root three-column NavigationSplitView |
| `Sources/OpenZeus/Core/AppDatabase.swift` | GRDB queue, migrations, `@Published` data streams |
| `Sources/OpenZeus/Core/OrchestratorActor.swift` | Process lifecycle — launch, terminate, isRunning |
| `Sources/OpenZeus/Views/TerminalStore.swift` | Cached `TerminalEntry` objects, active/attention tracking |
| `Sources/OpenZeus/Views/TerminalView.swift` | SwiftTerm NSViewRepresentable + tmux session management |
| `Sources/OpenZeus/Views/ProjectList.swift` | Project CRUD, NSOpenPanel for directory selection |
| `Sources/OpenZeus/Views/TaskList.swift` | Task CRUD, archiving, watch mode toggle |

### Layer Summary

- **Models** (`Models/`): Plain structs — `Project`, `AgentTask`, `AgentStatus`, `WatchMode`, `TerminalState`
- **Core** (`Core/`): `AppDatabase` (GRDB, SQLite at `~/Library/Application Support/OpenZeus/app.db`) and `OrchestratorActor` (`@globalActor` for process management)
- **Views** (`Views/`): SwiftUI views following loose MVVM; `TerminalStore` and `TerminalEntry` are the main view-models
- **Services** (`Services/`): `ActivityNotifier` — macOS UserNotifications + `NSSound`

### Concurrency Model

Swift 6 strict concurrency throughout:
- `OrchestratorActor` — `@globalActor` isolates all process-spawning work
- `AppDatabase`, `TerminalStore` — `@MainActor`
- `TerminalEntry` — `@unchecked Sendable` (SwiftTerm delegate pattern)
- All async operations use `async/await`; no DispatchQueue or locks

### Persistence

GRDB (SQLite) with versioned migrations:
- **v1:** `projects` and `tasks` tables
- **v2:** `watchMode` column on tasks
- **v3:** `isArchived` column on tasks

All models implement `FetchableRecord` & `PersistableRecord`.

### Terminal Integration

- **Engine:** SwiftTerm (`LocalProcessTerminalView`)
- **Session persistence:** tmux (keyed by task UUID); falls back to direct shell
- **Process detection:** 2-second polling interval

### Watch Mode

Per-task enum on `AgentTask.watchMode`:
- `.off` — no alerting
- `.on` — sound (`NSSound(named: "Tink")`) + macOS notification
- `.silent` — notification only

Triggers when a task transitions from active → idle.

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.2.0+ | PTY-based terminal emulation |
| [GRDB](https://github.com/groue/GRDB.swift) | 6.0.0+ | SQLite persistence |

No Homebrew or CocoaPods required. `swift build` fetches all dependencies automatically.

## Testing

Framework: **Swift Testing** (not XCTest)

```bash
swift test
```

Tests live in `Tests/OpenZeusTests/OpenZeusTests.swift`. Use `@Test`, `#expect()`, and `#require()` for new tests. Add `@testable import OpenZeus` for internal access.

Current tests cover model serialization (`AgentStatus`, `TerminalState`). New tests should cover model round-trips, GRDB persistence, and process lifecycle logic.

## Code Conventions

- **Types:** PascalCase structs/classes/enums; camelCase functions and properties
- **Models:** Value types (structs), `Identifiable`, `Equatable`, `Hashable`, `Codable` where appropriate
- **Views:** Compositional — extract sub-views to separate structs rather than nesting deeply
- **Error handling:** `try?` for non-critical paths; propagate errors at system boundaries
- **No sandboxing:** App has direct filesystem access; security hardening is explicitly deferred

## What to Avoid

- Do not introduce DispatchQueue, NSLock, or Combine `sink` — use `async/await` and actors
- Do not use SwiftData — the project migrated to GRDB; keep all persistence in `AppDatabase`
- Do not add Xcode `.xcodeproj` files — this is a pure SPM project
