# Coding Conventions

**Analysis Date:** 2026-03-17

## Naming Patterns

**Files:**
- PascalCase for type files matching the primary type: `TaskList.swift`, `TerminalView.swift`, `AppDatabase.swift`
- Single file can contain multiple related views as private structs: `TaskList.swift` contains `TaskList`, `NewTaskSheet`, `EditTaskSheet`, `TaskRow`, `ActiveProcessBadge`, `WorktreeBadge`, `StatusBadge`

**Types:**
- PascalCase for structs, classes, enums: `AgentTask`, `TerminalEntry`, `WatchMode`
- Protocols not heavily used; types conform to standard Swift protocols

**Functions/Properties:**
- camelCase for all functions and properties: `insertTask(_:)`, `isRunning`, `checkActiveProcess()`
- Descriptive names: `cleanupOrphanedSessions(keepingTaskIDs:)`, `startPeriodicCleanup(interval:taskIDsProvider:)`

**Variables:**
- camelCase for variables: `pollTimer`, `activeProcessTaskIDs`
- Avoid underscores in variable names (SwiftLint `identifier_name` disabled, but convention follows)

**Enums:**
- Lowercase case values: `.idle`, `.running`, `.stopped`, `.error` in `AgentStatus`
- RawString enums for Codable: `enum WatchMode: String, Codable`

## Code Style

**Formatting:**
- SwiftLint with `.swiftlint.yml` at repo root
- Disabled rules: `cyclomatic_complexity`, `file_length`, `force_try`, `function_body_length`, `identifier_name`, `line_length`, `multiple_closures_with_trailing_closure`, `trailing_comma`, `type_body_length`, `vertical_whitespace`, `void_function_in_ternary`
- Reporter: xcode
- Source exclusions: `.build` directory

**Linting:**
- Run `./scripts/lint.sh` for SwiftLint
- Run `./scripts/check.sh` for lint + tests combined
- SwiftLint runs with `--strict` flag (warnings treated as errors)

## Import Organization

**Order:**
1. Standard library imports (`Foundation`, `SwiftUI`, `AppKit`)
2. Third-party imports (`GRDB`, `SwiftTerm`, `UserNotifications`)
3. Testable imports for tests: `@testable import OpenZeus`

**No Path Aliases:**
- Direct module imports only

## Error Handling

**Patterns:**
- `try?` for non-critical paths where failure is acceptable: `try? JSONEncoder().encode(status)`, `try? dbQueue.write { ... }`
- `do/catch` with print for recoverable errors:
  ```swift
  do {
      try dbQueue.write { db in try command.insert(db) }
  } catch {
      print("Failed to insert saved command: \(error)")
  }
  ```
- `#require(try?)` pattern in tests for forced unwrapping with test failure:
  ```swift
  let data = try #require(try? JSONEncoder().encode(status))
  ```
- Graceful fallbacks: `?? UUID()`, `?? .idle`, `?? .off`
- Custom decoding with defaults for Codable types using `init(from decoder:)` pattern

## Logging

**Framework:** Custom `FileLogger` at `Sources/OpenZeus/Services/FileLogger.swift`

**Global Functions:**
- `logDebug(_:)` - Debug level
- `logInfo(_:)` - Info level
- `logWarning(_:)` - Warning level
- `logError(_:)` - Error level

**Patterns:**
- Structured format: `[timestamp] [LEVEL] [file:line] function - message`
- File rotation with configurable max size and backup count
- `#file`, `#function`, `#line` parameters auto-populated
- Heavy use in `TerminalStore.swift` for tracing process lifecycle
- Logging used for state transitions, tmux commands, process outputs

## Comments

**When to Comment:**
- Doc comments (`///`) for public APIs and complex behaviors
- `// MARK: -` sections for organizing code blocks
- Inline comments for non-obvious logic: `// (previousValue, currentValue)`, `// Simulate a DB that went through all v1–v10 migrations`

**JSDoc/TSDoc:**
- Swift doc comments (`///`) used for important functions
- Example: `/// Call when a watched task transitions from active → idle.` in `ActivityNotifier`

## Function Design

**Size:**
- Functions tend to be moderate length (20-80 lines)
- Complex logic extracted to private helpers: `parseWindowState(_:)`, `createVerticalPane(using:sessionName:)`
- MARK sections used to group related functions

**Parameters:**
- Named parameters with clear labels: `killSession(for taskID: UUID)`, `cleanupOrphanedSessions(keepingTaskIDs:)`
- Default parameter values used: `config: TerminalConfig = .init()`
- Closure parameters with `@MainActor` annotation: `taskIDsProvider: @escaping @MainActor () -> Set<UUID>`

**Return Values:**
- Functions return typed values or `Void`
- `@discardableResult` used when return value often ignored: `runProcessOutput(_:args:)`

## Module Design

**Exports:**
- Single module `OpenZeus` with `@testable import` for tests
- Private visibility for helper views: `private struct TaskRow: View`
- Internal visibility default (no explicit access modifiers)

**Actor Isolation:**
- `@MainActor` for UI-related classes: `AppDatabase`, `TerminalStore`, `TerminalEntry`, `ActivityNotifier`
- `@globalActor` for process management: `OrchestratorActor`
- `@unchecked Sendable` for delegate classes that need cross-isolation: `TerminalEntryDelegate`

## Concurrency Patterns

**Swift 6 Strict Mode:**
- Package declares `swift-tools-version: 6.0`
- No `DispatchQueue` or `NSLock` - use `async/await` and actors
- `nonisolated(unsafe)` for static monitors and config that cross isolation boundaries
- `Task { @MainActor in ... }` for bridging sync to async on main actor

**State Observation:**
- `@Published` properties for SwiftUI reactive updates
- Combine used for reactive pipelines: `$hasActiveProcess.removeDuplicates().scan(...)`
- GRDB `ValueObservation` for database change streaming

## SwiftUI Patterns

**View Composition:**
- Extract sub-views to separate structs rather than nesting deeply
- Private structs for internal components: `TaskRow`, `StatusBadge`, `ActiveProcessBadge`
- `@ViewBuilder` for computed view properties

**State Management:**
- `@EnvironmentObject` for shared services: `AppDatabase`, `TerminalStore`
- `@Environment(\.appConfig)` for configuration injection
- `@State` for local view state
- `@AppStorage` for UserDefaults persistence
- `@Binding` for parent-child state sharing

**Layout:**
- `NavigationSplitView` for three-column layout
- `confirmationDialog` for destructive action confirmation
- `sheet` for modal presentations

---

*Convention analysis: 2026-03-17*
