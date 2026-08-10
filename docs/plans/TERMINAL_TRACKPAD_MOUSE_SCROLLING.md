# Terminal Trackpad and Mouse Scrolling Plan

## Goal

Provide responsive, native-feeling terminal scrolling with both a Mac trackpad and a mouse wheel while preserving tmux pane targeting, terminal text selection, and the direct-shell fallback.

## Current Problem

`TerminalContainerView.scrollWheel(with:)` currently intercepts every scroll event and batches it with a short timer before running tmux commands.

This causes several problems:

- A trackpad emits a continuous stream of precise and momentum events. Resetting the timer for every event delays visible scrolling until the gesture pauses or finishes.
- Combining events into one net delta loses intermediate direction changes and momentum behavior.
- Trackpad pixel deltas and discrete mouse-wheel ticks are treated identically.
- Each batch launches separate `tmux copy-mode` and `tmux send-keys` processes, adding latency and allowing asynchronous batches to complete out of order.
- The fixed delta-to-step conversion makes small movements jump and larger gestures feel inconsistent.

## Proposed Event Flow

Use the existing native event path instead of translating scroll gestures into tmux CLI commands:

1. AppKit delivers the trackpad or mouse-wheel `NSEvent` to `TerminalContainerView`.
2. The container immediately forwards the unchanged event to SwiftTerm's `LocalProcessTerminalView`.
3. SwiftTerm distinguishes precise trackpad deltas from discrete wheel ticks and converts movement into terminal lines.
4. When tmux mouse reporting is active, SwiftTerm writes standard terminal mouse-wheel events to the PTY.
5. tmux handles copy mode, scrolling, momentum event sequences, and the pane under the pointer through its normal mouse bindings.
6. Without tmux, SwiftTerm scrolls its own local history buffer.

There must be exactly one scroll path. OpenZeus must not both forward the event and issue tmux scrolling commands.

## Implementation Steps

### 1. Require SwiftTerm's precise scrolling behavior

Update `Package.swift` to require SwiftTerm `1.16.0` or later within the existing major version.

This version:

- Uses `NSEvent.hasPreciseScrollingDeltas` to distinguish trackpads from mouse wheels.
- Accumulates fractional trackpad movement instead of dropping small deltas.
- Converts pixel movement using terminal cell height.
- Ensures a discrete mouse-wheel tick moves at least one line.
- Preserves momentum because every AppKit event is handled as it arrives.

### 2. Remove command-based scrolling

In `Sources/OpenZeus/Views/TerminalView.swift`, change `TerminalContainerView.scrollWheel(with:)` so it immediately forwards the event to the embedded terminal view.

Remove the scrolling-specific state and behavior:

- `scrollAccumulator`
- `scrollTimer`
- Timer invalidation and debounce scheduling
- Delta-to-step conversion
- `tmux copy-mode`
- `tmux send-keys -X scroll-up`
- `tmux send-keys -X scroll-down`

Keep the existing container and mouse-selection forwarding for this change unless testing demonstrates that native child hit-testing is required. Avoid broad pointer-event refactoring as part of the scrolling fix.

### 3. Preserve tmux mouse reporting

Keep tmux mouse mode enabled per OpenZeus session:

```text
tmux set-option -t <session> mouse on
```

Keep `LocalProcessTerminalView.allowMouseReporting` enabled during normal terminal use. This lets SwiftTerm send wheel events directly through the PTY to tmux without launching another process.

Preserve the existing Option-key behavior:

- Normal state: mouse reporting is enabled, so tmux receives pane clicks and scrolling.
- Option held: mouse reporting is disabled, so SwiftTerm handles native text selection.
- Option released: mouse reporting is restored.

The scrolling implementation must not introduce a second modifier-key rule.

### 4. Preserve the no-tmux fallback

When tmux is unavailable, forward the same event to SwiftTerm. Because terminal mouse mode is then inactive, SwiftTerm will scroll its local history buffer.

Do not retain a separate OpenZeus delta conversion for this path.

### 5. Remove obsolete configuration

Remove `scrollTimerIntervalSeconds`, because scrolling will no longer be timer-batched.

Update:

- `Sources/OpenZeus/Core/AppConfig.swift`
- `Sources/OpenZeus/Views/SettingsView.swift`
- `docs/config.example.json`
- `docs/plans/app-configuration.md`

Existing configuration files remain compatible because `JSONDecoder` ignores unknown keys by default.

Do not add a sensitivity preference in this change. Start with SwiftTerm's native `1.0` sensitivity so scrolling follows system behavior. A sensitivity setting can be added later if user testing demonstrates a need.

### 6. Update documentation

Update documentation that currently describes command-based scrolling:

- `README.md`
- `docs/plans/TERMINAL_WINDOW_MANAGEMENT.md`

Describe the final path as SwiftTerm terminal mouse events handled by tmux, rather than batched `copy-mode` commands.

## Automated Tests

### Event-forwarding tests

Add tests around the terminal container using a recording terminal view or injected scroll handler.

Cover:

- Positive and negative scroll deltas are forwarded.
- Multiple events are forwarded synchronously and in their original order.
- Small precise deltas are not coalesced by OpenZeus.
- Momentum events are not delayed or discarded.
- Discrete mouse-wheel events use the same forwarding path.
- Scroll handling does not depend on finding a tmux executable.

The OpenZeus test should verify event routing. SwiftTerm remains responsible for pixel-to-line accumulation.

### tmux integration tests

Extend `Tests/OpenZeusTests/TerminalWindowManagementTests.swift` to:

1. Create an isolated tmux session.
2. Enable mouse mode.
3. Verify `show-options -v mouse` reports `on`.
4. Generate enough output to create scrollback.
5. Verify scrolling upward enters copy mode and moves `scroll_position` away from the live output.
6. Verify scrolling downward moves back toward the live output.
7. Always kill the temporary session during cleanup.

Where practical, use an AppKit test harness with synthesized pixel-unit and line-unit `CGEvent` scroll events to exercise the complete SwiftTerm-to-tmux path.

## Manual Verification

Use a tmux-backed task with several hundred lines of output and verify:

### Trackpad

- A slow two-finger gesture scrolls while the fingers are still moving.
- A fast flick continues with normal momentum.
- Reversing direction during one gesture responds immediately.
- Small movements do not cause one-line jumps before enough movement accumulates.
- Scrolling down reaches the live output normally.

### Mouse

- Every wheel notch moves the history predictably.
- Rapid wheel movement remains responsive.
- Both directions work without a noticeable delay.

### Regression coverage

- In a split tmux window, scrolling affects the pane under the pointer.
- Clicking still selects tmux panes.
- Option-drag still selects text and auto-copies it.
- Releasing Option restores normal tmux mouse behavior.
- Full-screen terminal programs receive the behavior defined by tmux's standard mouse bindings.
- A direct shell without tmux still scrolls SwiftTerm's local history.
- Pop-out sessions in Terminal.app remain unaffected.
- Logs show no `copy-mode` or `scroll-up`/`scroll-down` process launches for wheel gestures.

## Acceptance Criteria

- Trackpad scrolling responds during the gesture and follows momentum.
- Direction changes are reflected immediately rather than combined into a net delta.
- Mouse-wheel ticks scroll predictably in both directions.
- Scrolling targets the tmux pane under the pointer.
- No process is launched per scroll event or gesture.
- There is no duplicate scrolling from competing event paths.
- Option-drag selection and auto-copy continue to work.
- The no-tmux fallback continues to scroll.
- `swift test` passes.
- `./scripts/check.sh` passes.

## Out of Scope

- A configurable scrolling sensitivity control.
- Custom tmux wheel bindings.
- A toolbar button for leaving tmux copy mode; that remains a separate TODO item.
- Refactoring all terminal mouse and responder-chain handling beyond what is required for reliable scrolling.
