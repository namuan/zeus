# Codebase Structure

**Analysis Date:** 2026-03-17

## Directory Layout

```
OpenZeus/
├── Sources/
│   └── OpenZeus/
│       ├── Core/          # Infrastructure (DB, Config, Actors)
│       ├── Models/        # Data structures
│       ├── Views/         # UI Components
│       ├── Services/      # Background services
│       ├── Resources/     # Assets (images)
│       └── OpenZeusApp.swift # App entry point
├── Tests/
│   └── OpenZeusTests/     # Unit tests
├── docs/                  # Documentation
├── scripts/               # Build/lint scripts
├── assets/                # Marketing/packaging assets
└── _verify/               # Temporary verification scripts (gitignored)
```

## Directory Purposes

**Sources/OpenZeus/Core/:**
- Purpose: Core application infrastructure.
- Contains: `AppDatabase.swift` (GRDB wrapper), `OrchestratorActor.swift` (process management), `AppConfig.swift` (configuration).
- Key files: `AppDatabase.swift`, `OrchestratorActor.swift`, `AppConfig.swift`.

**Sources/OpenZeus/Models/:**
- Purpose: Plain data models representing the domain.
- Contains: Struct definitions conforming to `Identifiable`, `Equatable`, `Codable`, `FetchableRecord`, `PersistableRecord`.
- Key files: `Project.swift`, `Task.swift` (AgentTask), `SavedCommand.swift`, `ProjectApp.swift`.

**Sources/OpenZeus/Views/:**
- Purpose: SwiftUI views and view models.
- Contains: Main window views, list views, terminal integration, settings.
- Key files: `ContentView.swift` (root), `ProjectList.swift`, `TaskList.swift`, `TerminalView.swift`, `TerminalStore.swift`, `SettingsView.swift`.

**Sources/OpenZeus/Services/:**
- Purpose: Reusable services and utilities.
- Contains: Notification handling, Git operations, Logging.
- Key files: `ActivityNotifier.swift`, `GitService.swift`, `WorktreeService.swift`, `FileLogger.swift`.

**Tests/OpenZeusTests/:**
- Purpose: Unit tests.
- Contains: Test cases using Swift Testing framework.
- Key files: `OpenZeusTests.swift`, `TerminalWindowManagementTests.swift`.

## Key File Locations

**Entry Points:**
- `Sources/OpenZeus/OpenZeusApp.swift`: `@main` struct, WindowGroup setup.
- `Sources/OpenZeus/Views/ContentView.swift`: Root view for the main window.

**Configuration:**
- `Sources/OpenZeus/Core/AppConfig.swift`: Configuration structs and loading logic.
- `Package.swift`: Swift Package Manager manifest (dependencies).

**Core Logic:**
- `Sources/OpenZeus/Core/AppDatabase.swift`: Database queue, migrations, CRUD operations.
- `Sources/OpenZeus/Views/TerminalStore.swift`: Terminal session management, active/attention tracking.

**Testing:**
- `Tests/OpenZeusTests/OpenZeusTests.swift`: Model serialization tests.
- `Tests/OpenZeusTests/TerminalWindowManagementTests.swift`: Terminal view tests.

## Naming Conventions

**Files:**
- PascalCase for types (e.g., `AgentTask.swift`, `TerminalView.swift`).
- Descriptive names matching the primary type defined in the file.

**Directories:**
- PascalCase for `Sources/OpenZeus/` subdirectories.
- `Core`, `Models`, `Views`, `Services` follow standard layer naming.

**Types:**
- PascalCase for structs, classes, enums (e.g., `Project`, `TerminalStore`).
- camelCase for properties and methods (e.g., `insertProject`, `selectedTask`).

## Where to Add New Code

**New Feature:**
- Primary code: `Sources/OpenZeus/Views/` (for UI) or `Sources/OpenZeus/Core/` (for logic).
- Tests: `Tests/OpenZeusTests/`.

**New Component/Module:**
- Implementation: Create a new file in the appropriate directory (`Models`, `Views`, etc.).

**Utilities:**
- Shared helpers: `Sources/OpenZeus/Services/`.

**New Dependency:**
- Add to `Package.swift` under `dependencies` and `targets`.
