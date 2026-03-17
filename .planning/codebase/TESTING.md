# Testing Patterns

**Analysis Date:** 2026-03-17

## Test Framework

**Runner:**
- Swift Testing (not XCTest)
- Framework: `import Testing`
- Config: `Package.swift` test target at `Tests/OpenZeusTests`

**Assertion Library:**
- `#expect()` for assertions (replaces `XCTAssert*`)
- `#require()` for forced unwrapping with test failure
- No XCTAssert usage

**Run Commands:**
```bash
swift test                    # Run all tests
swift test --filter OpenZeusTests  # Run specific test target
./scripts/check.sh            # Lint + tests combined
./scripts/lint.sh             # SwiftLint only
```

## Test File Organization

**Location:**
- `Tests/OpenZeusTests/` directory
- Co-located with source in same package

**Naming:**
- `OpenZeusTests.swift` - Core model and database tests
- `TerminalWindowManagementTests.swift` - Terminal and tmux integration tests
- Files named descriptively by feature area

**Structure:**
```
Tests/OpenZeusTests/
├── OpenZeusTests.swift                  # AppConfig, models, database tests
└── TerminalWindowManagementTests.swift  # TerminalEntry, TerminalStore, tmux tests
```

## Test Structure

**Suite Organization:**
- No `@Suite` annotations used
- Top-level `@Test` functions directly
- `// MARK: -` sections to organize test groups

```swift
import Foundation
import Testing
@testable import OpenZeus

// MARK: - AppConfig tests

@Test func appConfigDecodesFullJSON() throws {
    let json = """
    { "terminal": { "pollIntervalSeconds": 5.0 } }
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    #expect(config.terminal.pollIntervalSeconds == 5.0)
}

@Test @MainActor func savedCommandInsertAndFetch() throws {
    let db = try AppDatabase(inMemory: ())
    let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/tmp"))
    db.insertProject(project)
    let cmd = SavedCommand(id: UUID(), projectID: project.id, command: "swift build")
    db.insertSavedCommand(cmd)
    let fetched = db.savedCommands(for: project.id)
    #expect(fetched.count == 1)
}
```

**Patterns:**
- `throws` function signature for tests that can throw
- `@MainActor` on tests that interact with `@MainActor` types
- `async` tests for async operations
- Inline test data creation (no shared fixtures)

## Mocking

**Framework:**
- No mocking framework (no Mocktail, Cuckoo, or similar)
- Manual test doubles when needed

**Patterns:**
- In-memory database via `AppDatabase(inMemory: ())`:
  ```swift
  let db = try AppDatabase(inMemory: ())
  ```
- Real filesystem operations with temp directories:
  ```swift
  let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? fileManager.removeItem(at: folder) }
  ```
- Skip tests when tmux not available:
  ```swift
  guard let tmux = tmuxExecutable() else {
      return  // Skip if tmux not installed
  }
  ```

**What to Mock:**
- Not applicable - tests use real dependencies with controlled state

**What NOT to Mock:**
- Database (use in-memory GRDB)
- File system (use temp directories)
- Process execution (run real processes)

## Fixtures and Factories

**Test Data:**
- Inline creation with UUID() for unique IDs:
  ```swift
  let project = Project(id: UUID(), name: "Test", directoryURL: URL(fileURLWithPath: "/tmp"))
  let task = AgentTask(id: UUID(), projectID: project.id, name: "Test Task", ...)
  ```
- JSON strings for Codable testing:
  ```swift
  let json = """
  {
      "terminal": { "pollIntervalSeconds": 5.0, "tmuxSessionPrefix": "test-" },
      "logging": { "maxFileSizeBytes": 1048576 }
  }
  """
  ```

**Location:**
- No shared fixtures directory
- Test data created inline per test

## Coverage

**Requirements:**
- No formal coverage requirement or threshold enforced
- Tests focus on model serialization, database operations, and process lifecycle

**View Coverage:**
```bash
swift test --enable-code-coverage
```

**View Report:**
- Code coverage not actively tracked in CI
- Focus on critical paths: models, database, process management

## Test Types

**Unit Tests:**
- Model serialization/deserialization (`AgentStatusCodable`, `terminalStateRoundTrip`)
- Database CRUD operations (`savedCommandInsertAndFetch`, `savedCommandDeleteWorks`)
- Configuration decoding with defaults
- Equality and comparison operations

**Integration Tests:**
- tmux session management (skip if tmux not installed)
- Process execution (`runProcessOutputEchoTest`, `runProcessOutputPwdTest`)
- Database persistence across restarts (`savedCommandsPersistAcrossDatabaseRestart`)
- Window navigation with real tmux sessions

**E2E Tests:**
- Not used - manual testing for UI flows
- Automated visual verification via `ImageRenderer` for layout (per AGENTS.md)

## Common Patterns

**Async Testing:**
```swift
@Test func runProcessOutputEchoTest() async {
    let output = await runProcessOutput("/bin/echo", args: ["hello", "world"])
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
}

@Test @MainActor func tmuxSessionCreationAndListTest() async {
    guard let tmux = tmuxExecutable() else { return }
    let sessionName = "zeus-test-session-\(UUID().uuidString.prefix(8))"
    _ = await runProcessOutput(tmux, args: ["new-session", "-d", "-s", sessionName, "/bin/bash"])
    let listOutput = await runProcessOutput(tmux, args: ["list-sessions", "-F", "#{session_name}"])
    #expect(listOutput.contains(sessionName))
    killTmuxSessionSync(tmux, sessionName: sessionName)
}
```

**Error Testing:**
```swift
@Test func appConfigFallsBackToDefaultsOnInvalidJSON() {
    let badData = Data("not valid json {{{".utf8)
    let result = (try? JSONDecoder().decode(AppConfig.self, from: badData))
    #expect(result == nil)
    let defaults = AppConfig.defaults
    #expect(defaults.terminal.pollIntervalSeconds == 2.0)
}
```

**Database Testing:**
```swift
@Test @MainActor func staleMigrationRecordsAreRemovedOnOpen() throws {
    let path = folder.appendingPathComponent("app.db").path
    let queue = try DatabaseQueue(path: path)
    // Set up schema manually
    try queue.write { db in ... }
    // Trigger migration cleanup
    _ = try AppDatabase(path: path)
    // Verify cleanup occurred
    #expect(!applied.contains("v5"))
}
```

**Cleanup Pattern:**
```swift
// Always cleanup tmux sessions in defer
defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

// Always cleanup temp directories in defer
defer { try? fileManager.removeItem(at: folder) }
```

## Test Naming

**Convention:**
- Descriptive function names ending in `Test`: `tmuxWindowEqualityTest()`
- Test behavior being verified: `appConfigUsesDefaultsForMissingKeys()`
- Sync suffix when testing synchronous code: `terminalEntryInitialStateTest()`
- Async tests do not add suffix

**Example Names:**
- `appConfigDecodesFullJSON()` - JSON decoding happy path
- `savedCommandDeleteWorks()` - CRUD delete operation
- `tmuxWindowNavigationTest()` - tmux window control
- `terminalStoreMultipleKillSessionTest()` - Edge case handling

---

*Testing analysis: 2026-03-17*
