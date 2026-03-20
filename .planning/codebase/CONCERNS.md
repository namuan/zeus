# Codebase Concerns

**Analysis Date:** 2026-03-17

## Tech Debt

**Concurrency Safety Workarounds:**
- Issue: Multiple uses of `nonisolated(unsafe)` and `@unchecked Sendable` to bypass Swift 6 strict concurrency
- Files: `Sources/OpenZeus/Views/TerminalView.swift` (lines 466-468), `Sources/OpenZeus/Views/TerminalStore.swift` (lines 423-424), `Sources/OpenZeus/Services/FileLogger.swift` (line 9)
- Impact: Potential data races if code evolves without careful review
- Fix approach: Refactor to proper actor isolation or use `@Sendable` closures with proper synchronization

**Mixed Concurrency Patterns:**
- Issue: `TerminalEntryDelegate.processTerminated` uses `DispatchQueue.main.async` (line 408) instead of proper Swift concurrency
- Files: `Sources/OpenZeus/Views/TerminalStore.swift` (line 408)
- Impact: Inconsistent with Swift 6 strict concurrency model; may cause subtle threading bugs
- Fix approach: Use `Task { @MainActor in ... }` pattern

**Error Handling Inconsistency:**
- Issue: Database methods silently discard errors with `try?` in some places, use do/catch with print in others
- Files: `Sources/OpenZeus/Core/AppDatabase.swift` (lines 162-210 vs 244-275)
- Impact: Silent data loss; debugging production issues difficult
- Fix approach: Establish consistent error handling pattern; propagate errors or log explicitly

**Large View Files:**
- Issue: Multiple view files exceed 400 lines, violating single responsibility
- Files: `Sources/OpenZeus/Views/TerminalStore.swift` (671 lines), `Sources/OpenZeus/Views/TerminalView.swift` (602 lines), `Sources/OpenZeus/Views/SettingsView.swift` (502 lines), `Sources/OpenZeus/Views/TaskList.swift` (461 lines)
- Impact: Reduced maintainability; difficult to navigate and test
- Fix approach: Extract sub-views, view models, and helpers into separate files

## Security Considerations

**No Sandboxing (Intentional):**
- Risk: Arbitrary filesystem access; malicious project could access sensitive files
- Files: All services with filesystem access
- Current mitigation: User explicitly adds projects from trusted directories
- Recommendations: Consider scoped access or user confirmation for sensitive operations

**External Process Execution:**
- Risk: Commands executed with user's full permissions; no validation of tmux/git paths
- Files: `Sources/OpenZeus/Views/TerminalStore.swift`, `Sources/OpenZeus/Services/GitService.swift`
- Current mitigation: Paths configurable in settings
- Recommendations: Validate executables exist and are legitimate before execution

**Log File Path Traversal:**
- Risk: Log file location derived from config, could write to unexpected locations
- Files: `Sources/OpenZeus/Services/FileLogger.swift` (lines 28-30)
- Current mitigation: Default path is user's home directory
- Recommendations: Validate paths remain within expected directories

## Performance Bottlenecks

**Polling Interval Overhead:**
- Problem: Default 2-second polling runs 3 tmux commands per active terminal
- Files: `Sources/OpenZeus/Views/TerminalStore.swift` (lines 83-118)
- Cause: `checkActiveProcess()` spawns 3 concurrent processes every poll cycle
- Improvement path: Consider longer default interval or event-driven detection

**ValueObservation Without Error Handling:**
- Problem: Database observation errors are silently ignored
- Files: `Sources/OpenZeus/Core/AppDatabase.swift` (lines 113-158)
- Cause: `onError: { _ in }` handler discards all errors
- Improvement path: Log errors or surface to UI for user awareness

**Large Test File:**
- Problem: Single test file with 979 lines makes test discovery slow
- Files: `Tests/OpenZeusTests/TerminalWindowManagementTests.swift`
- Cause: All terminal-related tests in one file
- Improvement path: Split into focused test files (e.g., TmuxIntegrationTests.swift, TerminalEntryTests.swift)

## Fragile Areas

**Tmux Output Format Dependency:**
- Files: `Sources/OpenZeus/Views/TerminalStore.swift` (`parseWindowState`, lines 120-158)
- Why fragile: Parsing depends on exact pipe-separated format from tmux
- Safe modification: Add unit tests for parsing edge cases; validate output format before parsing
- Test coverage: Partial - integration tests cover happy path

**Shell Detection by Process Name:**
- Files: `Sources/OpenZeus/Core/AppConfig.swift` (`knownShells`, line 127)
- Why fragile: Different shells or versions may report different process names
- Safe modification: Extend `knownShells` list for edge cases; document known working shells
- Test coverage: Unit test exists but limited to static list

**Worktree Cleanup on Deletion:**
- Files: `Sources/OpenZeus/Views/TaskList.swift` (lines 99-111)
- Why fragile: Worktree removal runs asynchronously without confirmation; failure silently ignored
- Safe modification: Add error handling; provide user feedback on cleanup status
- Test coverage: No tests for worktree cleanup

**Font Resolution Fallback:**
- Files: `Sources/OpenZeus/Views/TerminalStore.swift` (lines 650-657)
- Why fragile: Custom font names may not exist on all systems; silent fallback to system font
- Safe modification: Log font resolution failures; validate font availability
- Test coverage: No tests

## Scaling Limits

**TerminalEntry Cache Growth:**
- Current capacity: Entries accumulate as tasks are created
- Limit: No explicit eviction; cache grows with session count
- Scaling path: Add periodic cleanup of stale entries (orphaned tmux session cleanup partially addresses this)

**Database ValueObservation Subscriptions:**
- Current capacity: One subscription per data type
- Limit: Adding new data types requires manual subscription in `startObserving()`
- Scaling path: Consider generic observation pattern or migration to observation builder

## Dependencies at Risk

**SwiftTerm (1.2.0+):**
- Risk: Active development may introduce breaking API changes
- Impact: Terminal rendering would break
- Migration plan: Pin version in Package.swift; monitor releases

**GRDB (6.0.0+):**
- Risk: Database schema changes between major versions
- Impact: Data migration required
- Migration plan: Pin version; maintain migration tests

## Missing Critical Features

**Database Backup/Migration:**
- Problem: No automated backup before schema changes; storage path change loses data
- Blocks: Safe upgrades and configuration changes

**Error Recovery UI:**
- Problem: Errors in process execution or database operations not surfaced to user
- Blocks: User awareness of issues; debugging production problems

**Configuration Validation:**
- Problem: No validation that config values are sensible (e.g., negative timeouts)
- Blocks: Prevents user from entering invalid states

## Test Coverage Gaps

**GitService:**
- What's not tested: All git operations (status, commit, push, revert)
- Files: `Sources/OpenZeus/Services/GitService.swift` (268 lines)
- Risk: Git command failures undetected; edge cases in porcelain parsing
- Priority: High

**WorktreeService:**
- What's not tested: Worktree creation, removal, branch naming
- Files: `Sources/OpenZeus/Services/WorktreeService.swift` (110 lines)
- Risk: Git worktree operations may fail in edge cases
- Priority: Medium

**ActivityNotifier:**
- What's not tested: Notification delivery, sound playback
- Files: `Sources/OpenZeus/Services/ActivityNotifier.swift` (46 lines)
- Risk: User notifications may not appear
- Priority: Low (requires mocking UNUserNotificationCenter)

**AppDatabase Migrations v4-v8:**
- What's not tested: Individual migration steps for savedCommands, projectApps, commandUsage, worktree columns
- Files: `Sources/OpenZeus/Core/AppDatabase.swift` (lines 71-99)
- Risk: Schema changes may corrupt data
- Priority: Medium

**TerminalStore Edge Cases:**
- What's not tested: Concurrent session cleanup, option/shift key monitors, periodic cleanup task lifecycle
- Files: `Sources/OpenZeus/Views/TerminalStore.swift`
- Risk: Memory leaks, missed notifications
- Priority: Medium

---

*Concerns audit: 2026-03-17*
