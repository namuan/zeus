import AppKit
import Foundation
import Testing
@testable import OpenZeus

@Test @MainActor func terminalEntryInitialStateTest() {
    let taskID = UUID()
    let entry = TerminalEntry(taskID: taskID)
    #expect(entry.taskID == taskID)
    #expect(!entry.isRunning)
    #expect(!entry.hasActiveProcess)
    #expect(entry.workingDirectory.isEmpty)
}

@Test @MainActor func terminalEntryWorkingDirectoryGetSetTest() {
    let entry = TerminalEntry(taskID: UUID())
    entry.workingDirectory = "/tmp/test"
    #expect(entry.workingDirectory == "/tmp/test")
    entry.workingDirectory = ""
    #expect(entry.workingDirectory.isEmpty)
}

@Test @MainActor func terminalEntryCurrentPaneDirectoryConvertsFileURL() async {
    let entry = TerminalEntry(taskID: UUID())
    entry.activePaneDirectory = "file://MacBookPro/Users/nnn/project"
    #expect(await entry.currentPaneDirectory() == "/Users/nnn/project")
}

@Test func zeusCommandVariablesExpandProjectDirectoryToken() {
    let command = "./run.sh \(ZeusCommandVariables.projectDirectoryToken)"
    #expect(ZeusCommandVariables.expand(command, projectDirectory: "/tmp/my-project") == "./run.sh /tmp/my-project")
}

@Test func zeusCommandVariablesLeaveTemplateWhenWorkingDirectoryMissing() {
    let command = "./run.sh \(ZeusCommandVariables.projectDirectoryToken)"
    #expect(ZeusCommandVariables.expand(command, projectDirectory: "   ") == command)
}

@Test @MainActor func terminalEntryRunningStateToggleTest() {
    let entry = TerminalEntry(taskID: UUID())
    entry.isRunning = true
    #expect(entry.isRunning)
    entry.isRunning = false
    #expect(!entry.isRunning)
}

@Test @MainActor func terminalEntryProcessStateToggleTest() {
    let entry = TerminalEntry(taskID: UUID())
    entry.hasActiveProcess = true
    #expect(entry.hasActiveProcess)
    entry.hasActiveProcess = false
    #expect(!entry.hasActiveProcess)
}

@Test @MainActor func terminalEntryAppliesExplicitThemes() {
    let entry = TerminalEntry(taskID: UUID())
    entry.applyTheme(.dark, systemColorScheme: .light)
    #expect(abs(entry.terminalView.nativeBackgroundColor.redComponent - 13.0 / 255.0) < 0.000_001)
    #expect(abs(entry.terminalView.nativeForegroundColor.redComponent - 230.0 / 255.0) < 0.000_001)
    entry.applyTheme(.light, systemColorScheme: .dark)
    #expect(entry.terminalView.nativeBackgroundColor.redComponent == 1.0)
    entry.applyTheme(.system, systemColorScheme: .light)
    let lightBackground = entry.terminalView.nativeBackgroundColor
    entry.applyTheme(.system, systemColorScheme: .dark)
    #expect(entry.terminalView.nativeBackgroundColor != lightBackground)
}

@Test @MainActor func terminalStoreCreatesAndReturnsSameEntryTest() {
    let store = TerminalStore()
    let taskID = UUID()
    let entry = store.entry(for: taskID)
    #expect(entry.taskID == taskID)
    #expect(store.entry(for: taskID) === entry)
}

@Test @MainActor func terminalStoreCreatesIndependentEntriesPerTaskTest() {
    let store = TerminalStore()
    let first = store.entry(for: UUID())
    let second = store.entry(for: UUID())
    #expect(first !== second)
}

@Test @MainActor func terminalStoreAppliesFontChangesToExistingAndNewEntriesTest() {
    let store = TerminalStore()
    let existing = store.entry(for: UUID())
    var config = TerminalConfig()
    config.fontSize = 19
    config.fontWeight = "bold"
    store.updateTerminalConfig(config)
    #expect(existing.terminalView.font.pointSize == 19)
    #expect(store.entry(for: UUID()).terminalView.font.pointSize == 19)
}

@Test @MainActor func terminalStoreMetadataUpdateSetsWorkingDirectoryTest() {
    let store = TerminalStore()
    let taskID = UUID()
    _ = store.entry(for: taskID)
    store.updateTaskMetadata(taskID: taskID, name: "Test Task", watchMode: .on, workingDirectory: "/tmp", projectDirectory: "/project")
    let entry = store.entry(for: taskID)
    #expect(entry.workingDirectory == "/tmp")
    #expect(entry.projectDirectory == "/project")
}

@Test @MainActor func terminalStoreSplitsAndClosesTaskTerminalTest() {
    let store = TerminalStore()
    let taskID = UUID()
    let entry = store.entry(for: taskID)

    store.splitTerminal(taskID: taskID, orientation: .horizontal)
    let secondaryPane = entry.secondaryPane
    #expect(secondaryPane != nil)
    #expect(secondaryPane?.taskID == taskID)
    #expect(secondaryPane?.paneID != entry.paneID)
    #expect(entry.splitOrientation == .horizontal)

    if let secondaryPane { entry.focusPane(secondaryPane.paneID) }
    store.closeSplitTerminal(taskID: taskID)
    #expect(entry.secondaryPane == nil)

    store.splitTerminal(taskID: taskID, orientation: .vertical)
    let remainingPane = entry.secondaryPane
    entry.focusPane(entry.paneID)
    store.closeSplitTerminal(taskID: taskID)
    #expect(entry.primaryPaneClosed)
    #expect(entry.secondaryPane != nil)
    #expect(entry.activeTerminal === entry.secondaryPane)

    store.splitTerminal(taskID: taskID, orientation: .horizontal)
    #expect(!entry.primaryPaneClosed)
    #expect(entry.splitOrientation == .horizontal)
    #expect(entry.secondaryPane === remainingPane)
}

@Test @MainActor func terminalStoreTerminationRemovesTaskShellFromCacheTest() {
    let store = TerminalStore()
    let taskID = UUID()
    let entry = store.entry(for: taskID)
    store.terminateTerminal(for: taskID)
    #expect(store.entry(for: taskID) !== entry)
}

@Test @MainActor func terminalStoreClearAttentionDoesNotCrashTest() {
    TerminalStore().clearAttention(taskID: UUID())
}

@Test func knownShellsDetectionTest() {
    let knownShells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login"]
    for shell in knownShells { #expect(knownShells.contains(shell)) }
    #expect(!knownShells.contains("node"))
    #expect(!knownShells.contains("swift"))
    #expect(!knownShells.contains("python3"))
}

@Test func parseActivePaneInfoTest() {
    #expect(parseActivePaneInfo("88228 bash\n") == ActivePaneInfo(pid: 88228, command: "bash"))
}

@Test func deepestLeafDescendantPrefersDeepestForegroundLeafTest() {
    let snapshots = [
        ProcessSnapshot(pid: 100, parentPID: 1, stat: "Ss", command: "/bin/zsh -l"),
        ProcessSnapshot(pid: 200, parentPID: 100, stat: "S+", command: "bash wrapper.sh"),
        ProcessSnapshot(pid: 300, parentPID: 200, stat: "S+", command: "node /tmp/tool.js"),
        ProcessSnapshot(pid: 400, parentPID: 300, stat: "S+", command: "/usr/local/bin/kilo"),
        ProcessSnapshot(pid: 500, parentPID: 300, stat: "S", command: "/usr/local/bin/helper")
    ]
    let leaf = deepestLeafDescendant(in: snapshots, rootPID: 100)
    #expect(leaf?.pid == 400)
    #expect(leaf?.executableName == "kilo")
}

@Test func resolvedActiveCommandUsesDeepestLeafForShellTest() async throws {
    let psScript = "#!/bin/sh\ncat <<'EOF'\n100 1 Ss /bin/zsh -l\n200 100 S+ bash wrapper.sh\n300 200 S+ node /tmp/tool.js\n400 300 S+ /usr/local/bin/kilo\nEOF\n"
    let pgrepScript = "#!/bin/sh\ncase \"$2\" in\n100) printf '200\\n' ;;\n200) printf '300\\n' ;;\n300) printf '400\\n' ;;\nesac\n"
    let psURL = FileManager.default.temporaryDirectory.appendingPathComponent("openzeus-ps-\(UUID().uuidString).sh")
    let pgrepURL = FileManager.default.temporaryDirectory.appendingPathComponent("openzeus-pgrep-\(UUID().uuidString).sh")
    try psScript.write(to: psURL, atomically: true, encoding: .utf8)
    try pgrepScript.write(to: pgrepURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: psURL.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pgrepURL.path)
    defer {
        try? FileManager.default.removeItem(at: psURL)
        try? FileManager.default.removeItem(at: pgrepURL)
    }
    let command = await resolvedActiveCommand(
        paneInfo: ActivePaneInfo(pid: 100, command: "bash"),
        knownShells: ["bash", "zsh"],
        psExecutable: psURL.path,
        pgrepExecutable: pgrepURL.path
    )
    #expect(command == "kilo")
}

@Test func runProcessOutputEchoTest() async {
    #expect(await runProcessOutput("/bin/echo", args: ["hello", "world"]).trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
}

@Test func runProcessOutputPwdTest() async {
    #expect(!(await runProcessOutput("/bin/pwd", args: [])).isEmpty)
}

@Test func runProcessOutputNonExistentBinaryTest() async {
    #expect(await runProcessOutput("/nonexistent/binary", args: []).isEmpty)
}
