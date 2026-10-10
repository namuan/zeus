# Terminal Activity Detection

This document describes the current process-activity model for direct task shells.

## Activity state

- `isRunning` tracks whether a shell process is alive.
- `hasActiveProcess` indicates that a non-shell foreground command is running in the shell's process tree.
- Each pane is checked independently; a task is active while any open pane has an active process.
- Watch-mode attention and notifications are based on an active-to-idle transition.

## Detection

`TerminalEntry` polls the direct shell's process tree at the configured terminal polling interval. Process snapshots are used to identify the deepest foreground descendant. Known shells are treated as idle; a non-shell command at the foreground leaf marks the pane active.

The process tree is obtained using the shell PID and the system process listing. This does not depend on tmux or tmux session state.

## Output and transcripts

Process activity is separate from terminal output activity. Direct PTY output is captured for sanitized text transcripts, but new output does not independently trigger watch-mode notifications or a visual unread-output indicator.

## Limitations

- Commands that detach from the shell's process tree may not be reflected in the active state.
- A process waiting for input remains active even when it produces no output.
- The app does not track output activity per task or pane.
