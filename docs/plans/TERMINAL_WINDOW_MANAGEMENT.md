# Terminal Window Management

This document describes the terminal window and pane management behavior currently implemented in Open-Zeus.

## Scope

- Applies to the terminal area shown for a selected task.
- Behavior is primarily implemented in `Sources/OpenZeus/Views/TerminalStore.swift` and `Sources/OpenZeus/Views/TerminalView.swift`.
- Each task gets its own terminal entry and, when available, its own tmux session named `zeus-<task UUID>`.

## Core Model

### Per-task terminal entry

Each task has a cached `TerminalEntry` that owns:

- One embedded `LocalProcessTerminalView`.
- Running state (`isRunning`).
- Active child-process detection (`hasActiveProcess`).
- tmux availability state (`tmuxUnavailable`).
- Current tmux windows list (`windows`).
- Current active tmux window index (`currentWindowIndex`).
- Current pane count (`paneCount`).
- Working directory used for new windows/panes and initial launch.

### Session naming

- tmux sessions are keyed by task ID as `zeus-<task UUID>`.
- Session identity is stable across reopen/restart attempts for the same task.

## Startup Behavior

### Automatic startup

- Opening a task terminal view auto-starts a terminal once per entry lifecycle.
- Startup is guarded by `shouldAutoStart` to avoid repeated launches during SwiftUI updates.

### With tmux installed

- The terminal starts `tmux new-session -A -s <session> <shell> -l`.
- This attaches to an existing per-task session if one already exists, otherwise creates it.
- After launch, mouse mode is disabled in tmux.

### Without tmux installed

- The terminal starts the task command directly as a login shell process.
- A warning banner is shown: `tmux not found - sessions won't persist`.
- Window/pane persistence features are effectively unavailable.

## Window Management Features

### Create new window

Toolbar button: `+`

- If the current tmux session is alive, creates a new tmux window in the task session.
- New windows inherit the task working directory when available.
- If the UI is open but the session/process is stale, the terminal resets and starts a fresh session instead.
- If the task terminal is fully closed, the same button is intended to start a fresh terminal session again.

### Select a specific window

- The control bar shows one tab-like button per tmux window.
- Each tab displays the tmux window name.
- Clicking a tab runs `select-window` for that tmux window index.
- The active window is highlighted using accent color.

### Previous / next window

Toolbar buttons: left and right chevrons

- Enabled only when more than one tmux window is known.
- Navigation is currently derived from the cached `windows` array.
- Previous/next wrap around cyclically.
- Both actions ultimately route through `select-window`.

### Close window

Toolbar button: `xmark`

- Enabled whenever the entry is marked running.
- If multiple tmux windows exist, closes the active tmux window.
- If the current window is the last remaining window, the app terminates the embedded terminal process and kills the whole tmux session.
- Closing the last window is intended to leave the task ready for a fresh reopen.

## Pane Management Features

### Split horizontally

Toolbar button: `rectangle.split.2x1`

- Calls tmux `split-window -h`.
- The new pane inherits the task working directory when available.

### Split vertically

Toolbar button: `rectangle.split.1x2`

- Calls tmux `split-window -v`.
- The new pane inherits the task working directory when available.

### Rotate/select pane

Toolbar button: `rectangle.2.swap`

- Uses tmux `select-pane -t <session>:.+`.
- Intended as a pane rotation/focus-cycle control.
- Disabled when only one pane is known.

### Pane count tracking

- Pane count is refreshed via `tmux list-panes`.
- UI enables/disables pane rotation based on this count.

## Command Injection Features

### Quick Commands popover

Toolbar button: `bolt.fill`

- Opens a saved-commands popover for the current project.
- Selecting a quick command sends it into the terminal.
- Quick commands are sent into a new vertical pane when tmux is available.

### Direct command send

- Commands are sent with `tmux send-keys ... Enter` when tmux is available.
- When tmux is unavailable, commands are written directly into the terminal PTY.

### Auto-create pane for quick commands

- For quick commands in new-pane mode, the app creates a pane using `split-window -h -P -F #{pane_id}`.
- The returned tmux pane ID is then used as the command target.

## State Refresh and Detection

### Polling

- While a terminal is running, the app polls every 2 seconds.
- An immediate poll also occurs when running starts.

### Active process detection

- Uses tmux `display-message -p #{pane_current_command}`.
- Known shells are treated as idle.
- Non-shell foreground commands mark the task as having an active process.

### Window state refresh

- Uses tmux `list-windows -F "#{window_index}\t#{window_name}\t#{window_active}"`.
- Parsed data updates the visible window tabs and active-window index.

### Pane state refresh

- Uses tmux `list-panes`.
- Count of returned panes becomes `paneCount`.

## Exit, Restart, and Recovery Behavior

### Process termination callback

- When SwiftTerm reports process termination, the entry:
  - marks `isRunning = false`
  - clears cached windows
  - resets `currentWindowIndex`
  - clears pane count state
  - rebuilds the underlying `LocalProcessTerminalView`

### Rebuild terminal view on termination

- A fresh `LocalProcessTerminalView` is created after process termination.
- This is intended to avoid stale SwiftTerm process/view reuse issues after `exit` or close.

### Reopen behavior

- `openWindow(command:)` tries to distinguish between:
  - a live tmux session that should get a new tmux window, and
  - a dead/stale session that should restart from scratch.
- It checks for a live tmux session using `list-windows` before deciding.

## Scrollback Behavior

### Custom mouse-wheel scroll handling

- The terminal container intercepts scroll events instead of letting SwiftTerm consume them directly.
- When tmux is active, scrolling enters tmux copy mode and sends scroll-up/scroll-down commands.
- Scroll input is batched briefly to reduce command spam.

### Mouse interaction forwarding

- Mouse clicks and drags are forwarded to the embedded terminal view.
- Keyboard focus stays with the terminal subview.

## Attention / Watch Features Related to Terminal State

### Active-to-idle notification

- `TerminalStore` watches `hasActiveProcess` transitions.
- If a task goes from active to idle and watch mode is enabled, the task is marked for attention and a notification/sound may fire.

### Clear attention on open

- Opening a task terminal clears any attention marker for that task.

### Task metadata cache

- Terminal state uses cached task name, watch mode, and working directory.
- Metadata is refreshed when the terminal appears and when task name/watch mode changes.

## Session Cleanup Features

### Remove terminal entry for a task

`killSession(for:)` in `TerminalStore`:

- Marks the entry as not running.
- Removes the cached terminal entry.
- Kills the associated tmux session if tmux exists.
- Clears active-process and attention state for the task.

## Current UX Surface

The current terminal control bar exposes:

- New window
- Previous window
- Next window
- Split pane horizontally
- Split pane vertically
- Rotate/select next pane
- Close window/session
- Quick commands popover
- Window tab strip showing all known tmux windows

## Important Current Characteristics / Constraints

- Window management is built directly on tmux commands, not an app-owned window model.
- There is only one embedded terminal view per task entry at a time.
- The UI state is partly optimistic and partly poll-driven.
- Restart/recovery behavior currently mixes session management, process lifecycle, and view reset logic in `TerminalEntry`.
- The non-tmux path is much simpler and does not provide persistent multi-window behavior.
- Several controls depend on periodically refreshed tmux state, so timing/race issues are possible.

## Files Involved

- `Sources/OpenZeus/Views/TerminalStore.swift`
- `Sources/OpenZeus/Views/TerminalView.swift`
- `Sources/OpenZeus/Views/TaskList.swift`
- `Sources/OpenZeus/Views/QuickCommandsView.swift`
- `Sources/OpenZeus/Services/ActivityNotifier.swift`
