**Open-Zeus RFC**  
**Title:** Open-Zeus — Open-Source AI Agent Orchestrator for macOS  
**Status:** Draft for Comments  
**Author:** Community Proposal (originating from early SwiftUI prototype)  
**Date:** March 2026  

### Abstract

Open-Zeus is a native macOS application that acts as a visual control plane for orchestrating fleets of AI agents. It presents a clean three-column workspace: Projects (left), Tasks per project (middle), and a full-featured terminal pane (right) powered by SwiftTerm. Each task runs as an independent AI agent process, allowing developers to monitor, interact with, and coordinate multiple specialized agents in real time.  

A **Project** is defined as a reference to a directory on the local filesystem (the source of truth for agent code, scripts, and data). Open-Zeus additionally maintains its own persistent metadata for every project — including the list of tasks and per-task terminal states — so the orchestrator can restore sessions, remember configurations, and survive app restarts without touching the project directory itself.  

The entire codebase follows **strict Swift and SwiftUI best practices**, leverages **modern Swift 6 concurrency** (actors + async/await) to guarantee a completely non-blocking UI, and uses a **pure Swift Package Manager** project structure so the app builds and runs with `swift build` / `swift run` — no Xcode required. Security, credentials, and sandboxing are explicitly **deferred**. The design is modern, clean, and Zeus-themed. Automated testing remains a first-class, non-negotiable foundation.

### 1. Product Overview & Requirements

#### 1.1 Core User Experience
- **Three-column layout** using `NavigationSplitView`:
  - Column 1 (Projects): List of projects, each showing the linked directory name and quick stats.
  - Column 2 (Tasks): Tasks belonging to the selected project. Each task shows name, status badge, and quick controls.
  - Column 3 (Terminal): Full PTY terminal for the selected task using SwiftTerm.
- **Project = Filesystem Directory Reference + Metadata**:
  - User chooses or creates a directory on disk → Open-Zeus stores only the URL reference.
  - All tasks and terminal states live in Open-Zeus’s private metadata store (the project directory itself is never modified by Open-Zeus).
- **Agent-centric workflow**:
  - Tasks point to executables inside (or relative to) the project directory.
  - Terminal states (configuration, last command, scroll position snapshot, etc.) are persisted per task.

#### 1.2 Functional Requirements
- Create a project by selecting any directory on the filesystem.
- Rename/delete projects (metadata only; directory untouched).
- Add/edit/delete tasks tied to a project.
- Persist and restore per-task terminal state on app launch.
- Launch/monitor/terminate agents.
- Basic status indicators and keyboard navigation.

#### 1.3 Non-Functional Requirements
- macOS 15+ (Swift 6+ baseline).
- Offline-first.
- **No credentials, no security enforcement, no App Sandbox**.
- 100 % built and testable via Swift Package Manager only.

### 2. Technical Architecture (Swift & SwiftUI Best Practices)

#### 2.1 Project Structure – Pure Swift Package Manager
(unchanged — same `Package.swift` as previous version; builds with `swift build` / `swift run OpenZeus`)

#### 2.2 Data Layer (Modern Observation + SwiftData)
Projects and tasks are stored exclusively in SwiftData. The project directory is only a reference.

```swift
@Model
final class Project: Observable {
    var id: UUID
    var name: String
    var directoryURL: URL                  // ← reference to filesystem directory
    var tasks: [Task]
    // future: tags, lastOpened
}

@Model
final class Task: Observable {
    var id: UUID
    var name: String
    var command: String                    // relative or absolute path inside project dir
    var environment: [String: String]
    var workingDirectory: URL              // defaults to project.directoryURL
    var status: AgentStatus
    var terminalState: TerminalState?      // ← persisted per-task terminal metadata
}

// Codable struct for terminal state persistence
struct TerminalState: Codable, Equatable {
    var lastCommand: String?
    var scrollOffset: Double?              // approximate saved scroll position
    var customPrompt: String?
    var environmentOverrides: [String: String]
    // future: buffer snapshot hash, etc.
}
```

- On project creation: user picks directory via `FileImporter`, Open-Zeus stores the URL and creates the `Project` record.
- Tasks are automatically scoped to their project; working directory is resolved relative to `project.directoryURL`.
- Terminal state is automatically saved on task termination or app quit and restored when the task is reopened.

#### 2.3 UI Layer – Pure SwiftUI + @MainActor
- All views use `@Observable` and `@MainActor`.
- Project list shows directory basename for clarity.
- When a task is selected, its `terminalState` is passed to the `TerminalViewRepresentable` to restore configuration.

#### 2.4 Concurrency – Proper Actor-Based Orchestration
(unchanged — `@OrchestratorActor` handles all process spawning, I/O, and terminal piping on a background actor. UI remains 100 % responsive. Terminal output streams via `AsyncStream`.)

#### 2.5 Dependencies
- Only SwiftTerm (MIT).
- All Apple frameworks (SwiftUI, SwiftData, Observation).

### 3. Automated Testing Strategy (Core Focus)

(unchanged — remains non-negotiable and fully SwiftPM-compatible)

- Unit tests cover `Project.directoryURL` resolution, `TerminalState` encoding/decoding, and actor lifecycle.
- Integration tests verify that tasks correctly resolve paths relative to the project directory.
- UI tests confirm directory picker → metadata persistence → terminal state restore round-trip.
- Coverage ≥95 %; all tests run with `swift test`.

### 4. Security & Privacy Considerations (Deferred)
- No sandbox, no restrictions — Open-Zeus can read/write only its own SwiftData store and launch whatever the user specifies inside the referenced directory.

### 5. Open-Source & Contribution Model
- MIT license.
- All code must build with `swift build` and pass strict concurrency checks.
- CONTRIBUTING.md requires tests for any new `directoryURL` or `terminalState` logic.

### 6. References
- SwiftData persistence guide
- Swift 6 Concurrency Best Practices
- Observation framework documentation
- Swift Package Manager executable targets for macOS apps
- SwiftTerm repository

This RFC now fully incorporates the filesystem-reference + metadata requirement. Projects remain lightweight directory pointers while Open-Zeus owns all orchestration metadata and terminal state persistence, exactly as specified.

Ready for the next iteration or code implementation. ⚡