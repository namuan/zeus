# Task Terminal and Pane Management

This document describes the current direct-shell terminal model in Open-Zeus.

## Terminal ownership

- Each task has one cached terminal entry while Open-Zeus is running.
- A terminal entry owns one primary shell and can own one secondary shell.
- Each shell is a direct local process attached to its own SwiftTerm view and PTY.
- Switching between tasks keeps their shells alive while Open-Zeus remains open.
- Quitting Open-Zeus terminates its task shells and running commands; terminal sessions cannot be attached to Terminal.app.

## Pane behavior

- A task can have at most two panes.
- Horizontal and vertical split controls create a secondary shell using the focused pane's working directory.
- Focusing a pane targets keyboard input, quick commands, and worktree actions to that pane.
- Close Active Pane closes the focused shell. Closing the primary pane expands the remaining pane; closing the secondary pane returns to the primary pane.
- If the primary pane was closed, creating another split starts a fresh primary shell alongside the remaining pane.
- Pane rotation, pane zoom, additional terminal windows, and Terminal.app pop-out are not supported.

## Terminal controls

- Split Pane Horizontally and Split Pane Vertically create the app-managed secondary pane.
- Close Active Pane is enabled while a secondary pane exists and closes the focused pane.
- Legacy New Window, Previous Window, and Next Window controls remain visible but disabled.
- Controls for pane rotation, pane zoom, and Terminal.app pop-out are not shown.

## Input and process activity

- Keyboard input and quick commands go to the focused pane.
- Terminal output is recorded per shell session for task transcripts.
- Process activity is detected from each shell's process tree rather than tmux polling.
- SwiftTerm handles scrollback directly; Open-Zeus forwards scroll events to the focused terminal view.

## Lifecycle

- Closing a pane terminates its shell and child processes.
- Removing a task terminal clears its cached terminal entry and terminates its shells.
- App termination closes all task shells; shell persistence across app restarts is not provided.

## Files involved

- `Sources/OpenZeus/Views/TerminalStore.swift`
- `Sources/OpenZeus/Views/TerminalView.swift`
- `Sources/OpenZeus/Views/TaskList.swift`
- `Sources/OpenZeus/Views/QuickCommandsView.swift`
- `Sources/OpenZeus/Services/ActivityNotifier.swift`
