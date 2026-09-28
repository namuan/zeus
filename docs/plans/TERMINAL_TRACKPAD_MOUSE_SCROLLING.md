# Terminal Trackpad and Mouse Scrolling

## Constraint

The Command Line Tools-compatible SwiftTerm revision used by OpenZeus predates SwiftTerm's tmux mouse-wheel reporting. Later SwiftTerm releases include Metal shaders and require the `metal` compiler, which is unavailable in this Command Line Tools-only setup.

## Event Routing

- AppKit delivers trackpad and mouse-wheel events to `TerminalContainerView`.
- For tmux-backed sessions, precise deltas accumulate into scroll steps; discrete wheel deltas become steps directly.
- OpenZeus flushes pending steps in short batches, enters tmux copy mode when scrolling up, and sends `scroll-up` or `scroll-down` to the session's active pane.
- Without tmux, OpenZeus forwards the original event to SwiftTerm so its local history continues to scroll.

## Tradeoffs

- Tmux CLI commands preserve scrolling without requiring a SwiftTerm version that compiles Metal shaders.
- Scroll commands target the session's active pane rather than the pane under the pointer.
- Scroll input is batched briefly to limit process launches while keeping trackpad movement responsive.

## Automated Verification

- Unit tests verify direct-shell events still reach SwiftTerm.
- A tmux integration test synthesizes trackpad scroll events and checks that tmux enters copy mode, moves into history, and returns to the live output when scrolling down.

## Manual Verification

- A slow two-finger gesture scrolls while fingers are moving.
- A fast flick continues scrolling through momentum events.
- Reversing direction responds correctly.
- Mouse-wheel ticks scroll in both directions.
- Scrolling down returns to live output.
- Direct shell sessions continue to scroll SwiftTerm's local history.
