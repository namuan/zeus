# Technology Stack

**Analysis Date:** 2026-03-17

## Languages

**Primary:**
- Swift 6 - 100% of application code

**Secondary:**
- Shell (Bash) - Build scripts in `scripts/`
- SQL - GRDB migrations in `Sources/OpenZeus/Core/AppDatabase.swift`

## Runtime

**Environment:**
- macOS 15+ (Sequoia) native application
- Swift 6 strict concurrency enabled (`swift-tools-version: 6.0`)

**Package Manager:**
- Swift Package Manager (SPM)
- Lockfile: `Package.resolved` (version 3 format)

## Frameworks

**Core:**
- SwiftUI - All UI views (`Sources/OpenZeus/Views/`)
- AppKit - macOS-specific APIs (`NSWorkspace`, `NSEvent`, `NSFont`, `NSSound`)
- Foundation - Core types and process management
- Combine - Reactive data binding in `TerminalStore`, `AppDatabase`
- UserNotifications - macOS push notifications (`UNUserNotificationCenter`)

**Terminal:**
- SwiftTerm 1.12.0 - PTY-based terminal emulation via `LocalProcessTerminalView`

**Persistence:**
- GRDB 6.29.3 - SQLite ORM with `DatabaseQueue`, migrations, `ValueObservation`

**Testing:**
- Swift Testing (not XCTest) - `@Test`, `#expect()`, `#require()` in `Tests/OpenZeusTests/`

**Build/Dev:**
- SwiftLint - Linting configured via `.swiftlint.yml`
- Custom shell scripts - `scripts/lint.sh`, `scripts/check.sh`

## Key Dependencies

**Critical:**
- SwiftTerm (1.2.0+) - Terminal emulation engine; provides `LocalProcessTerminalView`, `LocalProcessTerminalViewDelegate`
  - Source: `https://github.com/migueldeicaza/SwiftTerm`
  - Used in: `Sources/OpenZeus/Views/TerminalView.swift`, `Sources/OpenZeus/Views/TerminalStore.swift`

- GRDB.swift (6.0.0+) - SQLite persistence layer
  - Source: `https://github.com/groue/GRDB.swift`
  - Used in: `Sources/OpenZeus/Core/AppDatabase.swift`, all `Models/` files

**Transitive:**
- swift-argument-parser 1.7.0 - Dependency of GRDB

## Configuration

**Environment:**
- `ZEUS_APP_DIR` - Override Application Support folder name (defaults to "OpenZeus")
- `SHELL` - User's default shell for terminal sessions
- Config file: `~/Library/Application Support/OpenZeus/config.json` (JSON)
- Config structure: `Sources/OpenZeus/Core/AppConfig.swift` (`AppConfig`, `TerminalConfig`, `LoggingConfig`, `NotificationConfig`, `StorageConfig`, `GitConfig`, `UIConfig`, `WorktreeConfig`)

**Build:**
- `Package.swift` - SPM manifest
- `Package.resolved` - Dependency lockfile
- `.swiftlint.yml` - Linting rules (excludes cyclomatic_complexity, file_length, etc.)

**Linting:**
- SwiftLint via `scripts/lint.sh`
- Combined lint + test via `scripts/check.sh`
- Git hooks in `.githooks/` (install via `scripts/install-hooks.sh`)

## Platform Requirements

**Development:**
- macOS 15+ (Sequoia)
- Swift 6 toolchain
- Optional: Homebrew (for SwiftLint, tmux)

**Production:**
- macOS 15+ (Sequoia)
- No sandboxing (explicit filesystem access)
- tmux (optional, for session persistence)
- `/usr/bin/git` (configurable path)

## Build Commands

```bash
swift build                    # Development build
swift run OpenZeus             # Run in development
swift test                     # Run tests
./scripts/lint.sh              # SwiftLint only
./scripts/check.sh             # Lint + tests
./install.command              # Build release + install to ~/Applications/OpenZeus.app
```

---

*Stack analysis: 2026-03-17*
