import Foundation
import Testing
@testable import OpenZeus

// MARK: - Helpers

/// Synchronously kill a tmux session using Process (not async).
/// Used for cleanup in tests since `defer` cannot use `await`.
private func killTmuxSessionSync(_ tmux: String, sessionName: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tmux)
    process.arguments = ["kill-session", "-t", sessionName]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

// MARK: - TmuxWindow Tests

@Test func tmuxWindowEqualityTest() {
    let a = TmuxWindow(index: 1, name: "shell")
    let b = TmuxWindow(index: 1, name: "shell")
    let c = TmuxWindow(index: 2, name: "other")

    #expect(a == b)
    #expect(a != c)
}

@Test func tmuxWindowPropertiesTest() {
    let window = TmuxWindow(index: 0, name: "test-window")
    #expect(window.index == 0)
    #expect(window.name == "test-window")
}

// MARK: - TerminalEntry Tests

@Test @MainActor func terminalEntryInitialStateTest() {
    let taskID = UUID()
    let entry = TerminalEntry(taskID: taskID)

    #expect(entry.taskID == taskID)
    #expect(entry.isRunning == false)
    #expect(entry.hasActiveProcess == false)
    #expect(entry.tmuxUnavailable == false)
    #expect(entry.windows.isEmpty)
    #expect(entry.currentWindowIndex == 0)
    #expect(entry.paneCount == 1)
    #expect(entry.workingDirectory.isEmpty)
}

@Test @MainActor func terminalEntryWorkingDirectoryGetSetTest() {
    let entry = TerminalEntry(taskID: UUID())

    #expect(entry.workingDirectory.isEmpty)

    entry.workingDirectory = "/tmp/test"
    #expect(entry.workingDirectory == "/tmp/test")

    entry.workingDirectory = ""
    #expect(entry.workingDirectory.isEmpty)
}

@Test @MainActor func terminalEntryRunningStateToggleTest() {
    let entry = TerminalEntry(taskID: UUID())

    #expect(entry.isRunning == false)
    entry.isRunning = true
    #expect(entry.isRunning == true)
    entry.isRunning = false
    #expect(entry.isRunning == false)
}

@Test @MainActor func terminalEntryProcessStateToggleTest() {
    let entry = TerminalEntry(taskID: UUID())

    #expect(entry.hasActiveProcess == false)
    entry.hasActiveProcess = true
    #expect(entry.hasActiveProcess == true)
    entry.hasActiveProcess = false
    #expect(entry.hasActiveProcess == false)
}

@Test @MainActor func terminalEntryTmuxUnavailableToggleTest() {
    let entry = TerminalEntry(taskID: UUID())

    #expect(entry.tmuxUnavailable == false)
    entry.tmuxUnavailable = true
    #expect(entry.tmuxUnavailable == true)
}

// MARK: - TerminalStore Tests

@Test @MainActor func terminalStoreCreatesAndReturnsSameEntryTest() {
    let store = TerminalStore()
    let taskID = UUID()

    let entry = store.entry(for: taskID)
    #expect(entry.taskID == taskID)

    let sameEntry = store.entry(for: taskID)
    #expect(entry === sameEntry)
}

@Test @MainActor func terminalStoreCreatesDifferentEntriesTest() {
    let store = TerminalStore()
    let taskID1 = UUID()
    let taskID2 = UUID()

    let entry1 = store.entry(for: taskID1)
    let entry2 = store.entry(for: taskID2)

    #expect(entry1 !== entry2)
    #expect(entry1.taskID == taskID1)
    #expect(entry2.taskID == taskID2)
}

@Test @MainActor func terminalStoreMetadataUpdateSetsWorkingDirectoryTest() {
    let store = TerminalStore()
    let taskID = UUID()

    // Create entry first, then update metadata
    _ = store.entry(for: taskID)
    store.updateTaskMetadata(
        taskID: taskID,
        name: "Test Task",
        watchMode: .on,
        workingDirectory: "/tmp"
    )

    let entry = store.entry(for: taskID)
    #expect(entry.workingDirectory == "/tmp")
}

@Test @MainActor func terminalStoreKillSessionCreatesNewEntryTest() {
    let store = TerminalStore()
    let taskID = UUID()

    let entry = store.entry(for: taskID)
    entry.isRunning = true

    store.killSession(for: taskID)

    // Entry should be removed from cache, new entry created
    let newEntry = store.entry(for: taskID)
    #expect(newEntry !== entry)
}

@Test @MainActor func terminalStoreClearAttentionDoesNotCrashTest() {
    let store = TerminalStore()
    let taskID = UUID()

    // This tests that clearAttention doesn't crash
    store.clearAttention(taskID: taskID)
}

// MARK: - Window State Tests

@Test @MainActor func windowStateInitialValuesTest() {
    let entry = TerminalEntry(taskID: UUID())

    #expect(entry.windows.isEmpty)
    #expect(entry.currentWindowIndex == 0)
}

// MARK: - Tmux Executable Detection Tests

@Test func tmuxExecutableDetectionTest() {
    let tmux = tmuxExecutable()

    // tmux may or may not be installed in the test environment
    if let tmux {
        #expect(FileManager.default.isExecutableFile(atPath: tmux))
    }
}

// MARK: - Active Process Detection Logic Tests

@Test func knownShellsDetectionTest() {
    let knownShells: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login",
        "tmux", "tmux: server",
    ]

    for shell in knownShells {
        #expect(knownShells.contains(shell))
    }

    // Non-shell commands should not be in the set
    #expect(!knownShells.contains("node"))
    #expect(!knownShells.contains("swift"))
    #expect(!knownShells.contains("python3"))
}

// MARK: - Run Process Output Tests

@Test func runProcessOutputEchoTest() async {
    let output = await runProcessOutput("/bin/echo", args: ["hello", "world"])
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
}

@Test func runProcessOutputPwdTest() async {
    let output = await runProcessOutput("/bin/pwd", args: [])
    #expect(!output.isEmpty)
}

@Test func runProcessOutputNonExistentBinaryTest() async {
    let output = await runProcessOutput("/nonexistent/binary", args: [])
    #expect(output.isEmpty)
}

@Test func runProcessOutputFalseExitCodeTest() async {
    let output = await runProcessOutput("/bin/false", args: [])
    // false exits with 1 but we don't check exit code, just that it completes
    #expect(output.isEmpty)
}

// MARK: - Window Control Methods (Integration Tests with Tmux)

@Test @MainActor func tmuxSessionCreationAndListTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-session-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Verify session exists
    let listOutput = await runProcessOutput(tmux, args: [
        "list-sessions", "-F", "#{session_name}"
    ])
    #expect(listOutput.contains(sessionName))

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxWindowCreationTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-windows-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Create new window
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])

    // Verify two windows exist
    let windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName, "-F", "#{window_index}"
    ])
    let windowIndices = windows
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .compactMap { Int($0) }
    #expect(windowIndices.count == 2)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxWindowNavigationTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-nav-\(UUID().uuidString.prefix(8))"

    // Create session with two windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])

    // Navigate to next window
    _ = await runProcessOutput(tmux, args: [
        "next-window", "-t", sessionName
    ])

    // Navigate to previous window
    _ = await runProcessOutput(tmux, args: [
        "previous-window", "-t", sessionName
    ])

    // Select specific window
    _ = await runProcessOutput(tmux, args: [
        "select-window", "-t", "\(sessionName):1"
    ])

    let activeWindow = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{window_index}"
    ])
    #expect(activeWindow.trimmingCharacters(in: .whitespacesAndNewlines) == "1")

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxPaneSplitHorizontalTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-split-h-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Split horizontally
    _ = await runProcessOutput(tmux, args: [
        "split-window", "-h", "-t", sessionName
    ])

    // Verify pane count
    let panes = await runProcessOutput(tmux, args: [
        "list-panes", "-t", sessionName
    ])
    let paneCount = panes
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .count
    #expect(paneCount == 2)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxPaneSplitVerticalTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-split-v-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Split vertically
    _ = await runProcessOutput(tmux, args: [
        "split-window", "-v", "-t", sessionName
    ])

    // Verify pane count
    let panes = await runProcessOutput(tmux, args: [
        "list-panes", "-t", sessionName
    ])
    let paneCount = panes
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .count
    #expect(paneCount == 2)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxPaneRotationTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-rotate-\(UUID().uuidString.prefix(8))"

    // Create session with multiple panes
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "split-window", "-h", "-t", sessionName
    ])
    _ = await runProcessOutput(tmux, args: [
        "split-window", "-v", "-t", sessionName
    ])

    // Rotate to next pane
    let result = await runProcessOutput(tmux, args: [
        "select-pane", "-t", "\(sessionName):.+"
    ])

    // select-pane doesn't output on success
    #expect(result.isEmpty || result.contains("%"))

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxWindowCloseTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-close-\(UUID().uuidString.prefix(8))"

    // Create session with two windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])

    // Verify two windows
    var windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    let initialCount = windows
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .count
    #expect(initialCount == 2)

    // Close a window
    _ = await runProcessOutput(tmux, args: [
        "kill-window", "-t", sessionName
    ])

    // Verify one window remains
    windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    let finalCount = windows
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .count
    #expect(finalCount == 1)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxSendCommandTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-send-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Send a command
    _ = await runProcessOutput(tmux, args: [
        "send-keys", "-t", sessionName, "echo test", "Enter"
    ])

    // Wait for command to execute
    try? await Task.sleep(nanoseconds: 100_000_000)

    // Verify the session is still alive
    let alive = await runProcessOutput(tmux, args: [
        "has-session", "-t", sessionName
    ])
    // has-session returns empty on success
    #expect(alive.isEmpty)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxWorkingDirectoryInheritanceTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-cwd-\(UUID().uuidString.prefix(8))"
    let testDir = NSTemporaryDirectory()

    // Create session with working directory
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "-c", testDir, "/bin/bash"
    ])

    // Create new window with working directory
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "-c", testDir, "/bin/bash"
    ])

    // Verify window was created
    let windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    #expect(windows.contains("1"))

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxSessionPersistOnAttachTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-persist-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Attach to existing session (creates new window if -A is used)
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-A", "-s", sessionName, "/bin/bash"
    ])

    // Verify session still exists
    let exists = await runProcessOutput(tmux, args: [
        "has-session", "-t", sessionName
    ])
    #expect(exists.isEmpty)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxListWindowsFormatTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-format-\(UUID().uuidString.prefix(8))"

    // Create session with named window
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "-n", "main", "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "-n", "editor", "/bin/bash"
    ])

    // Get formatted output
    let output = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName,
        "-F", "#{window_index}|#{window_name}|#{window_active}"
    ])

    let lines = output
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")

    #expect(lines.count == 2)

    // Parse and verify format
    for line in lines {
        let parts = line.split(separator: "|")
        #expect(parts.count == 3)
        #expect(Int(parts[0]) != nil)  // index is a number
        #expect(!parts[1].isEmpty)     // name is not empty
        #expect(parts[2] == "0" || parts[2] == "1")  // active is 0 or 1
    }

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxListPanesFormatTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-panes-\(UUID().uuidString.prefix(8))"

    // Create session and split
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "split-window", "-h", "-t", sessionName
    ])
    _ = await runProcessOutput(tmux, args: [
        "split-window", "-v", "-t", sessionName
    ])

    // Get pane list
    let panes = await runProcessOutput(tmux, args: [
        "list-panes", "-t", sessionName
    ])

    let paneCount = panes
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .count
    #expect(paneCount == 3)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxDetectActiveProcessTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-proc-\(UUID().uuidString.prefix(8))"

    // Create session with shell
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Check current command (should be shell)
    let command = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{pane_current_command}"
    ])

    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    let knownShells = ["zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login", "tmux", "tmux: server"]
    #expect(knownShells.contains(trimmedCommand))

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

@Test @MainActor func tmuxSetMouseOptionTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let sessionName = "zeus-test-mouse-\(UUID().uuidString.prefix(8))"

    // Create session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    // Set mouse option to off
    let result = await runProcessOutput(tmux, args: [
        "set-option", "-t", sessionName, "mouse", "off"
    ])

    // set-option doesn't output on success
    #expect(result.isEmpty)

    // Cleanup
    killTmuxSessionSync(tmux, sessionName: sessionName)
}

// MARK: - Edge Cases

@Test @MainActor func terminalStoreMultipleKillSessionTest() {
    let store = TerminalStore()
    let taskID = UUID()

    _ = store.entry(for: taskID)

    // Kill session multiple times should not crash
    store.killSession(for: taskID)
    store.killSession(for: taskID)

    // Should be able to create new entry after kill
    let newEntry = store.entry(for: taskID)
    #expect(newEntry.taskID == taskID)
}

@Test @MainActor func terminalStoreMetadataUpdateCachesTaskInfoTest() {
    let store = TerminalStore()
    let taskID = UUID()

    // Update metadata before entry exists - this caches task metadata
    // The workingDirectory is only set on existing entries
    store.updateTaskMetadata(
        taskID: taskID,
        name: "Pre-created",
        watchMode: .silent,
        workingDirectory: "/pre"
    )

    // Now create entry - workingDirectory won't be set since entry didn't exist
    let entry = store.entry(for: taskID)
    #expect(entry.workingDirectory.isEmpty)

    // Update metadata after entry exists - now workingDirectory is set
    store.updateTaskMetadata(
        taskID: taskID,
        name: "Updated",
        watchMode: .on,
        workingDirectory: "/updated"
    )
    #expect(entry.workingDirectory == "/updated")
}

@Test @MainActor func tmuxSessionNameFormatTest() {
    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    #expect(sessionName.hasPrefix("zeus-"))
    #expect(sessionName.count == 41)  // "zeus-" (5) + UUID (36)
}

@Test @MainActor func windowNavigationEdgeCaseWithNoWindowsTest() {
    let entry = TerminalEntry(taskID: UUID())

    // With no windows, operations should be no-ops
    entry.openWindow()
    entry.nextWindow()
    entry.previousWindow()
    entry.closeWindow()
    entry.selectWindow(index: 0)
    entry.rotatePane()

    // These should not crash
    #expect(entry.windows.isEmpty)
}

@Test @MainActor func commandSendWithoutTmuxTest() {
    let entry = TerminalEntry(taskID: UUID())
    entry.tmuxUnavailable = true

    // Should not crash when sending command without tmux
    entry.sendCommand("echo test", inNewVerticalPane: false)
    entry.sendCommand("echo test", inNewVerticalPane: true)
}

// MARK: - TerminalEntry Window Navigation Tests (Button Simulation)

@Test @MainActor func terminalEntryNextWindowTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    // Create session with two windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "-n", "window2", "/bin/bash"
    ])

    // Explicitly select window 0 to ensure consistent starting state
    _ = await runProcessOutput(tmux, args: [
        "select-window", "-t", "\(sessionName):0"
    ])

    defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

    // Verify starting at window 0
    var active = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{window_index}"
    ])
    #expect(active.trimmingCharacters(in: .whitespacesAndNewlines) == "0")

    // Simulate clicking "Next Window" button
    let entry = TerminalEntry(taskID: taskID)
    entry.nextWindow()

    // Wait for async operation
    try? await Task.sleep(nanoseconds: 500_000_000)

    // Verify we moved to window 1
    active = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{window_index}"
    ])
    #expect(active.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
}

@Test @MainActor func terminalEntryPreviousWindowTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    // Create session with two windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "-n", "window1", "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "-n", "window2", "/bin/bash"
    ])

    defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

    // Start at window 1
    _ = await runProcessOutput(tmux, args: [
        "select-window", "-t", "\(sessionName):1"
    ])

    var active = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{window_index}"
    ])
    #expect(active.trimmingCharacters(in: .whitespacesAndNewlines) == "1")

    // Simulate clicking "Previous Window" button
    let entry = TerminalEntry(taskID: taskID)
    entry.previousWindow()

    // Wait for async operation
    try? await Task.sleep(nanoseconds: 300_000_000)

    // Verify we moved to window 0
    active = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{window_index}"
    ])
    #expect(active.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
}

@Test @MainActor func terminalEntryWindowsArrayPopulatedTest() async {
    // This test verifies that TerminalEntry.windows array is correctly populated
    // after checkActiveProcess runs - catching format string mismatches
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    // Create session with 3 windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])

    defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

    // Create TerminalEntry and trigger checkActiveProcess
    let entry = TerminalEntry(taskID: taskID)
    entry.isRunning = true  // This starts polling which calls checkActiveProcess

    // Wait for polling to complete (allow extra time under parallel test load)
    try? await Task.sleep(nanoseconds: 1_500_000_000)

    // CRITICAL: Verify windows array was populated via parsing
    #expect(entry.windows.count == 3, "Expected 3 windows after parsing, got \(entry.windows.count)")
    #expect(entry.windows.contains { $0.index == 0 }, "Should have window 0")
    #expect(entry.windows.contains { $0.index == 1 }, "Should have window 1")
    #expect(entry.windows.contains { $0.index == 2 }, "Should have window 2")

    entry.isRunning = false
}

@Test @MainActor func terminalEntryOpenNewWindowTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    // Create initial session
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])

    defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

    // Create TerminalEntry to track windows
    let entry = TerminalEntry(taskID: taskID)
    entry.isRunning = true
    try? await Task.sleep(nanoseconds: 500_000_000)

    // Verify one window exists in entry
    #expect(entry.windows.count == 1, "Should start with 1 window")

    // Verify one window exists
    var windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    var count = windows.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n").count
    #expect(count == 1)

    // Simulate clicking "+" button to open new window
    entry.openWindow()

    // Wait for async operation
    try? await Task.sleep(nanoseconds: 300_000_000)

    // Verify two windows now exist
    windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    count = windows.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n").count
    #expect(count == 2)
}

@Test @MainActor func terminalEntrySelectSpecificWindowTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    // Create session with three windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])

    defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

    // Simulate clicking window tab for window 2
    let entry = TerminalEntry(taskID: taskID)
    entry.selectWindow(index: 2)

    // Wait for async operation
    try? await Task.sleep(nanoseconds: 300_000_000)

    // Verify we're on window 2
    let active = await runProcessOutput(tmux, args: [
        "display-message", "-p", "-t", sessionName, "#{window_index}"
    ])
    #expect(active.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
}

@Test @MainActor func terminalEntryCloseWindowButtonTest() async {
    guard let tmux = tmuxExecutable() else {
        return  // Skip if tmux not installed
    }

    let taskID = UUID()
    let sessionName = "zeus-\(taskID.uuidString)"

    // Create session with two windows
    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash"
    ])
    _ = await runProcessOutput(tmux, args: [
        "new-window", "-t", sessionName, "/bin/bash"
    ])

    defer { killTmuxSessionSync(tmux, sessionName: sessionName) }

    // Verify two windows
    var windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    var count = windows.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n").count
    #expect(count == 2)

    // Simulate clicking "x" button to close window
    let entry = TerminalEntry(taskID: taskID)
    entry.closeWindow()

    // Wait for async operation
    try? await Task.sleep(nanoseconds: 300_000_000)

    // Verify one window remains
    windows = await runProcessOutput(tmux, args: [
        "list-windows", "-t", sessionName
    ])
    count = windows.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n").count
    #expect(count == 1)
}
