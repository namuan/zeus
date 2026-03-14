# Terminal Activity Detection

This document proposes adding output activity detection to Open-Zeus using SwiftTerm's `rangeChanged` delegate callback.

## Problem Statement

Currently, Open-Zeus distinguishes between:
- **Process running**: A non-shell command is executing (detected via tmux polling every 2s)
- **Process idle**: Only a shell is active

However, it cannot distinguish between:
- **Process running, actively outputting**: Command is producing terminal output
- **Process running, idle**: Command is running but waiting (e.g., `sleep 10`, waiting for input, long compilation)

This limitation means:
1. Watch mode notifications fire only on `active → idle` transitions, not on new output
2. No visual indicator shows "this terminal has new output you haven't seen"
3. Cannot detect when a running process produces output while the user is focused elsewhere

## SwiftTerm Capabilities

The `TerminalViewDelegate` protocol provides:

```swift
/// Invoked when there are visual changes in the terminal buffer if
/// the `notifyUpdateChanges` variable is set to true.
func rangeChanged(source: TerminalView, startY: Int, endY: Int)
```

### Current Limitation

`LocalProcessTerminalView` implements `rangeChanged` but **does not forward** it to `processDelegate`:

```swift
// MacLocalTerminalView.swift (SwiftTerm)
open func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
    // empty - not forwarded to processDelegate
}
```

This means `TerminalEntryDelegate` (which conforms to `LocalProcessTerminalViewDelegate`) cannot receive range change notifications from SwiftTerm without subclassing.

### Key Requirements

1. `notifyUpdateChanges` must be `true` on the `TerminalView` for `rangeChanged` to fire
2. The property name suggests it may be internal; verification needed during implementation

## Proposed Architecture

### Approach A: Subclass LocalProcessTerminalView (Recommended)

Create a custom terminal view that forwards `rangeChanged` to a new delegate method.

```swift
// New protocol extending LocalProcessTerminalViewDelegate
protocol TerminalActivityDelegate: LocalProcessTerminalViewDelegate {
    func terminalContentChanged(source: LocalProcessTerminalView, startY: Int, endY: Int)
}

// Custom subclass
class ActivityDetectingTerminalView: LocalProcessTerminalView {
    weak var activityDelegate: TerminalActivityDelegate?
    
    override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        activityDelegate?.terminalContentChanged(source: self, startY: startY, endY: endY)
    }
}
```

**Pros:**
- Minimal changes to existing code
- Clear separation of concerns
- Compatible with SwiftTerm updates

**Cons:**
- Requires one new subclass file
- Need to verify `notifyUpdateChanges` is accessible

### Approach B: Monitor dataReceived at PTY Level

Hook into the `LocalProcessDelegate.dataReceived` callback by subclassing `LocalProcessTerminalView`.

```swift
class ActivityDetectingTerminalView: LocalProcessTerminalView {
    weak var activityDelegate: TerminalActivityDelegate?
    
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        if !slice.isEmpty {
            activityDelegate?.terminalDataReceived(source: self, byteCount: slice.count)
        }
    }
}
```

**Pros:**
- Fires on any data from PTY (input echo + output)
- Does not require `notifyUpdateChanges`

**Cons:**
- Less precise (fires on user input echo too)
- Does not distinguish between content regions

### Approach C: Hybrid (Proposed)

Combine both approaches for comprehensive detection:

1. Use `rangeChanged` for content-change detection (visual changes)
2. Use `dataReceived` as fallback if `rangeChanged` is unavailable
3. Track `lastOutputTimestamp` on `TerminalEntry`

## Data Model Changes

### TerminalEntry additions

```swift
@Published var hasNewOutput: Bool = false
@Published var lastOutputTime: Date?

// Activity tracking
private var outputActivityTimer: Timer?
private var pendingOutputCount: Int = 0
```

### TerminalStore additions

```swift
@Published private(set) var outputActivityTaskIDs: Set<UUID> = []
```

## Implementation Plan

### Phase 1: Create ActivityDetectingTerminalView

**File:** `Sources/OpenZeus/Views/ActivityDetectingTerminalView.swift`

```swift
import SwiftTerm

protocol ActivityDetectingDelegate: AnyObject {
    func contentDidChange(source: LocalProcessTerminalView, startY: Int, endY: Int)
}

class ActivityDetectingTerminalView: LocalProcessTerminalView {
    weak var activityDelegate: ActivityDetectingDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Enable range change notifications if property exists
        // terminalView.notifyUpdateChanges = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        super.rangeChanged(source: source, startY: startY, endY: endY)
        activityDelegate?.contentDidChange(source: self, startY: startY, endY: endY)
    }
}
```

### Phase 2: Update TerminalEntry

**File:** `Sources/OpenZeus/Views/TerminalStore.swift`

1. Replace `LocalProcessTerminalView` with `ActivityDetectingTerminalView`:
   ```swift
   let terminalView: ActivityDetectingTerminalView
   ```

2. Add new published properties:
   ```swift
   @Published var hasNewOutput = false
   @Published var lastOutputTime: Date?
   ```

3. Implement `ActivityDetectingDelegate` in `TerminalEntry`:
   ```swift
   extension TerminalEntry: ActivityDetectingDelegate {
       func contentDidChange(source: LocalProcessTerminalView, startY: Int, endY: Int) {
           DispatchQueue.main.async {
               self.lastOutputTime = Date()
               if !NSApp.isActive || self.isViewedElsewhere {
                   self.hasNewOutput = true
               }
           }
       }
   }
   ```

4. Clear `hasNewOutput` when terminal gains focus or user scrolls to bottom

### Phase 3: Update TerminalStore for Output Activity

1. Add `outputActivityTaskIDs` published set
2. Subscribe to `hasNewOutput` changes per entry
3. Integrate with existing `attentionTaskIDs` or create parallel tracking

### Phase 4: UI Indicators

**File:** `Sources/OpenZeus/Views/TaskList.swift`

Add visual indicator for new output:
```swift
if terminalStore.outputActivityTaskIDs.contains(task.id) {
    Image(systemName: "circle.fill")
        .font(.caption2)
        .foregroundStyle(.blue)
}
```

### Phase 5: Optional - Enhanced Watch Mode

Extend watch mode to optionally trigger on new output (not just completion):

```swift
enum WatchTrigger: String, Codable {
    case completion  // current behavior: active → idle
    case output      // new: any output while app unfocused
    case both        // either trigger
}
```

This requires a database migration (v4) to add the new column.

## Verification Strategy

### Unit Tests

```swift
@Test func activityDetectingTerminalViewForwardsRangeChanged() {
    // Mock terminal view, verify delegate is called
}

@Test func terminalEntryTracksLastOutputTime() {
    // Simulate content change, verify timestamp updated
}
```

### Integration Verification Script

Create `_verify/check_activity_detection.swift`:

1. Create mock `ActivityDetectingTerminalView`
2. Simulate `rangeChanged` callback
3. Verify `hasNewOutput` becomes `true`
4. Verify `lastOutputTime` is set
5. Verify clearing works when focus returns

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `notifyUpdateChanges` not publicly accessible | Investigate during Phase 1; may need PR to SwiftTerm |
| Excessive callbacks on high-throughput output | Debounce or batch updates (e.g., 100ms window) |
| False positives from screen clears/resizes | Filter: ignore callbacks when `startY == 0 && endY == rows` (full screen clear) |
| Performance impact from frequent callbacks | Use debouncing; only update UI after 200ms of inactivity |

## Files to Modify

| File | Change |
|------|--------|
| `Sources/OpenZeus/Views/ActivityDetectingTerminalView.swift` | **New** - Custom terminal view subclass |
| `Sources/OpenZeus/Views/TerminalStore.swift` | Replace `LocalProcessTerminalView`, add activity tracking |
| `Sources/OpenZeus/Views/TerminalView.swift` | Update to use `ActivityDetectingTerminalView` |
| `Sources/OpenZeus/Views/TaskList.swift` | Add output activity indicator |
| `Tests/OpenZeusTests/OpenZeusTests.swift` | Add activity detection tests |
| `docs/plans/TERMINAL_WINDOW_MANAGEMENT.md` | Update to document activity detection |

## Open Questions

1. Should `hasNewOutput` clear automatically on scroll, or require explicit user action?
2. Should output activity trigger watch mode notifications, or only visual indicators?
3. Should we track per-window activity or aggregate across all windows in a task session?

## Estimated Scope

- **Lines of code**: ~150-200 new, ~50 modified
- **New files**: 1 (ActivityDetectingTerminalView.swift)
- **Database migration**: Optional (v4) only if watch trigger enum is added
- **Risk level**: Low (additive change, no existing behavior modified)
