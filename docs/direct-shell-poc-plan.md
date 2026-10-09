# Direct-Shell POC Plan

## Scope

Replace tmux with direct shells attached to Open-Zeus’s terminal view. Each task can have one shell or a single app-managed split containing two shells. Keep shells alive while the app is running, including while another task is selected. When Open-Zeus quits, task shells and their running commands may stop. Tmux windows and cross-app session attachment remain out of scope.

## Task list

1. **Define lifecycle and ownership**
   - Specify when task shells start and stop, including task deletion, terminal closing, and app termination.
   - Keep a task’s terminal process alive while navigating between tasks.
   - Ensure shell termination also handles child processes appropriately.

2. **Replace tmux startup with direct shell startup**
   - Launch the configured shell directly in the task’s effective working directory.
   - Preserve startup commands, shell selection, and environment behavior.
   - Remove tmux executable discovery, session naming, tmux launch arguments, and settle-delay configuration.

3. **Refactor terminal session management**
   - Update `TerminalStore` and terminal view setup so each task owns one direct shell process and PTY.
   - Remove tmux session creation, attachment, polling, cleanup, and kill-session handling.
   - Retain per-task terminal caching for the life of the app.

4. **Simplify terminal controls**
   - Remove tmux window navigation and pane-management dependencies.
   - Keep core terminal functionality such as input, scrolling, theme, and font controls.
   - Provide one app-managed split per task, with a distinct direct shell in each pane and close support.
   - Remove “Pop Out to Terminal.app”; a direct shell cannot attach the same running session.
   - Replace tmux-based worktree directory switching. Ensure switching is safe when a command is running, or disable it while busy.

5. **Adapt process and activity tracking**
   - Use direct process lifecycle callbacks for shell start/exit state.
   - Inspect the direct shell’s process tree for the task “active” indicator.
   - Remove tmux polling and session refresh logic.

6. **Adapt transcript recording**
   - Capture direct PTY output through SwiftTerm’s host-output callback and sanitize it for transcripts.
   - Preserve transcript storage and display behavior, with one transcript file per task shell session.

7. **Remove tmux maintenance and settings**
   - Remove tmux settings and explanatory UI, including executable search paths, session prefix, settle delay, and orphan-session cleanup.
   - Keep worktree cleanup that does not depend on tmux.
   - Update warnings and help text that refer to tmux availability or persistence.

8. **Update tests and verify**
   - Replace tmux startup and window-management tests with tests for direct shell startup, per-task isolation, working directory, and process termination.
   - Adapt transcript and activity tests to the direct-process model.
   - Run `swift test`, `./scripts/lint.sh`, and `./scripts/check.sh`.
   - Verify on macOS: multiple tasks, switching between tasks, startup commands, task deletion, app quit, scrolling, and retained terminal controls.

## Acceptance criteria

- Each task opens a direct shell in its effective working directory; a user can create one split pane with a second shell.
- Clicking a pane focuses it for input, quick commands, and worktree operations.
- Switching tasks does not terminate another task’s shells while Open-Zeus remains running.
- Quitting Open-Zeus ends its task shells and running commands, as agreed for this POC.
- No user-facing feature requires tmux to be installed.
- Tmux-only windows, attachment, and orphan cleanup are removed; split panes are managed by Open-Zeus.
- Tests and lint/check commands pass, with any deferred transcript or activity behavior documented.
