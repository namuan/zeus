# External Integrations

**Analysis Date:** 2026-03-17

## APIs & External Services

**None detected.** OpenZeus is a native macOS application with no external API integrations. All functionality is local.

## Data Storage

**Databases:**
- SQLite via GRDB.swift
  - Location: `~/Library/Application Support/OpenZeus/app.db`
  - Client: `DatabaseQueue` from GRDB
  - Migrations: `Sources/OpenZeus/Core/AppDatabase.swift` (v1-v8)
  - Tables: `projects`, `tasks`, `savedCommands`, `projectApps`, `commandUsage`

**File Storage:**
- Application Support directory for database and config (`~/Library/Application Support/OpenZeus/`)
- Log files to `~/Library/Logs/OpenZeus/openzeus.log` (rolling, max 5MB, 5 backups)
- Config file: `config.json` in Application Support

**Caching:**
- In-memory terminal session cache in `TerminalStore.entries` (`Sources/OpenZeus/Views/TerminalStore.swift`)

## Authentication & Identity

**Auth Provider:**
- Not applicable - local desktop application with no user authentication

## Monitoring & Observability

**Error Tracking:**
- None - no external error tracking service integrated

**Logs:**
- File-based logging via `FileLogger` (`Sources/OpenZeus/Services/FileLogger.swift`)
- Log location: `~/Library/Logs/OpenZeus/openzeus.log`
- Levels: DEBUG, INFO, WARN, ERROR
- Rolling file rotation (configurable via `LoggingConfig`)

## CI/CD & Deployment

**Hosting:**
- Local macOS application
- Installation script: `install.command` → `~/Applications/OpenZeus.app`

**CI Pipeline:**
- None detected in repository

**Git Hooks:**
- Pre-commit: Runs `scripts/check.sh` (lint + tests)
- Pre-push: Validates Git notes are present on commits
- Install: `scripts/install-hooks.sh`

## Environment Configuration

**Required env vars:**
- None required

**Optional env vars:**
- `ZEUS_APP_DIR` - Override Application Support folder name (default: "OpenZeus")
- `SHELL` - User's default shell (used by terminal sessions)

**Secrets location:**
- Not applicable - no external service credentials

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## System Integrations

**Git:**
- Shell command integration via `/usr/bin/git` (configurable path in `GitConfig.executablePath`)
- Services: `Sources/OpenZeus/Services/GitService.swift`, `Sources/OpenZeus/Services/WorktreeService.swift`
- Operations: status, add, commit, push, worktree create/remove, branch management
- Porcelain output parsing for UI display

**tmux:**
- Terminal multiplexer for session persistence
- Search paths: `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, `/usr/bin/tmux`
- Session naming: `zeus-{taskUUID}`
- Controls: new-window, split-window, kill-session, send-keys, copy-mode
- Fallback: Direct shell process when tmux not found

**Shell:**
- Default shell from `$SHELL` environment variable or configurable via `TerminalConfig.defaultShell`
- Supported shells: zsh, bash, sh, fish, dash, csh, tcsh, login, tmux

**macOS System:**
- `UserNotifications` - Push notifications via `UNUserNotificationCenter`
- `NSSound` - Attention sounds (default: "Tink")
- `NSWorkspace` - Launch applications with project directories
- `NSOpenPanel` - File/directory selection dialogs
- `NSEvent` - Global key event monitoring (Option key, Shift+Return)

**Process Management:**
- `Process` (Foundation) - Spawn agent processes, git commands, tmux operations
- `pkill` - Send SIGTERM to child processes (`/usr/bin/pkill`, configurable)

---

*Integration audit: 2026-03-17*
