# Terminal Trackpad and Mouse Scrolling

Open-Zeus embeds a SwiftTerm view for each direct shell. `TerminalContainerView` forwards AppKit scroll-wheel events to the embedded terminal view, where SwiftTerm handles its local scrollback.

## Event routing

- Trackpad and mouse-wheel events received by the terminal container are sent to its embedded SwiftTerm view.
- When there is no embedded terminal view, the container falls back to AppKit's default scroll handling.
- Each pane owns its own terminal view and scrollback buffer.

## Verification

- Unit tests verify scroll events are forwarded to SwiftTerm.
- Manual checks should cover slow trackpad movement, momentum scrolling, reversing direction, mouse-wheel ticks, and scrolling through local history.
