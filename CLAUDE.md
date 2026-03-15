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

# Lint
./scripts/lint.sh

# Lint + tests
./scripts/check.sh

# Install repo Git hooks
./scripts/install-hooks.sh

# Setup Git notes sharing (once per clone)
./scripts/setup-git-notes.sh

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

Homebrew is not required for app dependencies, but local linting uses SwiftLint from `$PATH` (for example `brew install swiftlint`). `swift build` fetches Swift package dependencies automatically.

## Testing

Framework: **Swift Testing** (not XCTest)

```bash
swift test
./scripts/lint.sh
./scripts/check.sh
```

Tests live in `Tests/OpenZeusTests/OpenZeusTests.swift`. Use `@Test`, `#expect()`, and `#require()` for new tests. Add `@testable import OpenZeus` for internal access.

Git hooks live in `.githooks/`. Run `./scripts/install-hooks.sh` once per clone to install them:
- **pre-commit:** Executes `./scripts/check.sh` (lint + tests) before each commit
- **pre-push:** Rejects pushes containing commits without a Git note

Setup Git notes sharing once per clone with `./scripts/setup-git-notes.sh`. Before pushing, add a note to each commit: `git notes add -m 'Your summary here'`

Current tests cover model serialization (`AgentStatus`, `TerminalState`). New tests should cover model round-trips, GRDB persistence, and process lifecycle logic.

## Code Conventions

- **Types:** PascalCase structs/classes/enums; camelCase functions and properties
- **Models:** Value types (structs), `Identifiable`, `Equatable`, `Hashable`, `Codable` where appropriate
- **Views:** Compositional — extract sub-views to separate structs rather than nesting deeply
- **Error handling:** `try?` for non-critical paths; propagate errors at system boundaries
- **No sandboxing:** App has direct filesystem access; security hardening is explicitly deferred

## Automated Visual Verification

For UI/layout work, use `ImageRenderer` to render SwiftUI views headlessly and verify pixel positions programmatically — no manual app launching required.

**Pattern:**
1. Write a standalone `swift` script (e.g., `./_verify/check_layout.swift`) that:
   - Defines a minimal mock view replicating only the relevant layout (hardcode data, skip DB/actors)
   - Renders it via `ImageRenderer` inside a minimal `NSApplication` bootstrap
   - Reads back the `NSBitmapImageRep` and checks pixel positions/colors against expected values
   - Exits `0` on pass, `1` on fail with a descriptive message
2. Run it with `swift ./_verify/check_layout.swift`
3. Keep iterating until it passes before considering the UI task done

**Key techniques used:**
- `NSApplication.shared` + `app.setActivationPolicy(.prohibited)` + `Task { @MainActor in ... }` + `app.run()` to bootstrap SwiftUI rendering
- `ImageRenderer(content:).nsImage` → `NSBitmapImageRep` → `colorAt(x:y:)` for pixel inspection
- Use solid, distinguishable colors (e.g., `.blue`, `.red`) in mock views so pixels are easy to identify
- `ScrollView` does not render inside `ImageRenderer` headlessly — substitute a plain `HStack` to verify layout logic
- Check rightmost/leftmost content pixel as a fraction of total width; assert it falls within expected range

**Use automated verification as much as possible** for any SwiftUI layout change — it catches issues (like `Spacer` + `ScrollView` flex-space competition) that are invisible from code review alone.

## Temporary Files

When writing verification scripts or other temporary files, create them in a local `_verify/` folder inside the project root (not `/tmp`):

```bash
mkdir -p _verify
# write scripts to _verify/
swift _verify/check_something.swift
```

`_verify/` is gitignored. **If the task completes successfully, delete it:**

```bash
rm -rf _verify/
```

If the task fails or is interrupted, tell the user: "You can delete the `_verify/` folder — it contains only temporary verification scripts."

## What to Avoid

- Do not introduce DispatchQueue, NSLock, or Combine `sink` — use `async/await` and actors
- Do not use SwiftData — the project migrated to GRDB; keep all persistence in `AppDatabase`
- Do not add Xcode `.xcodeproj` files — this is a pure SPM project
