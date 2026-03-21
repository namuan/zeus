import AppKit
import Combine
import SwiftTerm

enum ZeusCommandVariables {
    static let projectDirectoryToken = "${zeus_project_directory}"
    static let supportedTokens = [projectDirectoryToken]
    static let helpText = "Available variable: \(supportedTokens.joined(separator: ", "))"

    static func expand(_ command: String, workingDirectory: String) -> String {
        guard command.contains(projectDirectoryToken) else { return command }
        let resolvedWorkingDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedWorkingDirectory.isEmpty else { return command }

        return command.replacingOccurrences(of: projectDirectoryToken, with: resolvedWorkingDirectory)
    }
}

struct TmuxWindow: Equatable {
    let index: Int
    let name: String
}

@MainActor
final class TerminalEntry: ObservableObject {
    let taskID: UUID
    let terminalView: LocalProcessTerminalView
    @Published var isRunning = false {
        didSet {
            logInfo("isRunning changed: \(isRunning)")
            isRunning ? startPolling() : stopPolling()
        }
    }
    @Published var hasActiveProcess = false {
        didSet { logDebug("hasActiveProcess changed: \(hasActiveProcess)") }
    }
    @Published var tmuxUnavailable = false {
        didSet { logInfo("tmuxUnavailable changed: \(tmuxUnavailable)") }
    }
    @Published var windows: [TmuxWindow] = [] {
        didSet {
            logInfo("windows changed: count=\(windows.count), windows=\(windows.map { "\($0.index):\($0.name)" })")
        }
    }
    @Published var currentWindowIndex: Int = 0 {
        didSet { logDebug("currentWindowIndex changed: \(currentWindowIndex)") }
    }
    @Published var paneCount: Int = 1 {
        didSet { logDebug("paneCount changed: \(paneCount)") }
    }
    @Published var mouseReportingEnabled: Bool = true {
        didSet { logDebug("mouseReportingEnabled changed: \(mouseReportingEnabled)") }
    }
    var workingDirectory: String = "" {
        didSet { logDebug("workingDirectory changed: '\(workingDirectory)'") }
    }

    let config: TerminalConfig
    private let delegate: TerminalEntryDelegate
    private var pollTimer: Timer?

    private var sessionName: String { "\(config.tmuxSessionPrefix)\(taskID.uuidString)" }
    private var knownShells: Set<String> { Set(config.knownShells) }

    init(taskID: UUID, config: TerminalConfig = .init()) {
        self.taskID = taskID
        self.config = config
        logInfo("TerminalEntry created for task \(taskID.uuidString)")
        terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.font = resolvedFont(config)
        let d = TerminalEntryDelegate()
        delegate = d
        d.entry = self
        terminalView.processDelegate = d
    }

    private func startPolling() {
        guard pollTimer == nil else {
            logDebug("startPolling: already polling, skipping")
            return
        }
        logInfo("startPolling: beginning \(config.pollIntervalSeconds)-second polling cycle")
        Task { await checkActiveProcess() }  // immediate check on start
        pollTimer = Timer.scheduledTimer(withTimeInterval: config.pollIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkActiveProcess() }
        }
    }

    private func stopPolling() {
        logInfo("stopPolling: stopping poll timer")
        pollTimer?.invalidate()
        pollTimer = nil
        hasActiveProcess = false
    }

    private func checkActiveProcess() async {
        logDebug("checkActiveProcess: starting for session \(sessionName)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logWarning("checkActiveProcess: tmux executable not found")
            return
        }
        logDebug("checkActiveProcess: using tmux at \(tmux)")

        async let commandFuture = runProcessOutput(tmux, args: [
            "display-message", "-p", "-t", sessionName, "#{pane_current_command}",
        ])
        async let windowsFuture = runProcessOutput(tmux, args: [
            "list-windows", "-t", sessionName, "-F",
            "#{window_index}|#{window_name}|#{window_active}",
        ])
        async let panesFuture = runProcessOutput(tmux, args: [
            "list-panes", "-t", sessionName,
        ])
        let (commandOutput, windowsOutput, panesOutput) = await (commandFuture, windowsFuture, panesFuture)

        logDebug("checkActiveProcess: commandOutput='\(commandOutput)'")
        logDebug("checkActiveProcess: windowsOutput='\(windowsOutput)'")
        logDebug("checkActiveProcess: panesOutput='\(panesOutput)'")

        let command = commandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasActive = hasActiveProcess
        hasActiveProcess = !command.isEmpty && !knownShells.contains(command)
        logDebug("checkActiveProcess: command='\(command)', hasActiveProcess=\(hasActiveProcess) (was \(wasActive))")

        parseWindowState(windowsOutput)

        let count = panesOutput.split(separator: "\n").filter { !$0.isEmpty }.count
        paneCount = max(1, count)
        logDebug("checkActiveProcess: pane count updated to \(paneCount)")
    }

    private func parseWindowState(_ output: String) {
        logDebug("parseWindowState: input length=\(output.count), raw='\(output)'")
        let lines = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        logDebug("parseWindowState: \(lines.count) lines after splitting")

        if lines.isEmpty {
            logWarning("parseWindowState: no lines to parse - tmux session may not exist or be stale")
            return
        }

        var wins: [TmuxWindow] = []
        var activeIdx = 0
        for (lineNum, line) in lines.enumerated() {
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            logDebug("parseWindowState: line \(lineNum): '\(line)' -> \(parts.count) parts: \(parts)")
            guard parts.count == 3, let idx = Int(parts[0]) else {
                logWarning("parseWindowState: SKIPPED line \(lineNum) - expected 3 pipe-separated parts with numeric index, got \(parts.count) parts")
                continue
            }
            wins.append(TmuxWindow(index: idx, name: parts[1]))
            if parts[2].trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                activeIdx = idx
                logDebug("parseWindowState: window \(idx) (\(parts[1])) is active")
            }
        }

        logInfo("parseWindowState: parsed \(wins.count) windows, active=\(activeIdx), previous count=\(windows.count)")
        if !wins.isEmpty {
            windows = wins
            currentWindowIndex = activeIdx
            logInfo("parseWindowState: UPDATED windows array - now \(windows.count) windows")
        } else {
            logWarning("parseWindowState: NO UPDATE - all lines failed to parse, windows still at \(windows.count)")
        }
    }

    // MARK: - Tmux window control

    func openWindow() {
        logInfo("openWindow: requested for session \(sessionName), current windows count=\(windows.count)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("openWindow: tmux executable not found")
            return
        }

        var args = ["new-window", "-t", sessionName]
        if !workingDirectory.isEmpty {
            args += ["-c", workingDirectory]
            logDebug("openWindow: using working directory '\(workingDirectory)'")
        }
        logInfo("openWindow: executing \(tmux) \(args.joined(separator: " "))")

        Task {
            let output = await runProcessOutput(tmux, args: args)
            logInfo("openWindow: tmux new-window completed, output='\(output)'")

            logDebug("openWindow: waiting \(config.tmuxSettleDelayMs)ms for tmux to settle...")
            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))

            logDebug("openWindow: calling checkActiveProcess to refresh state")
            await checkActiveProcess()

            logInfo("openWindow: completed - windows now count=\(windows.count), names=\(windows.map { $0.name })")
        }
    }

    func nextWindow() {
        logInfo("nextWindow: requested for session \(sessionName), current index=\(currentWindowIndex), windows=\(windows.count)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("nextWindow: tmux executable not found")
            return
        }

        Task {
            logDebug("nextWindow: executing tmux next-window")
            let output = await runProcessOutput(tmux, args: ["next-window", "-t", sessionName])
            logDebug("nextWindow: tmux output='\(output)'")

            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))

            logDebug("nextWindow: refreshing state")
            await checkActiveProcess()
            logInfo("nextWindow: completed - now at index=\(currentWindowIndex)")
        }
    }

    func previousWindow() {
        logInfo("previousWindow: requested for session \(sessionName), current index=\(currentWindowIndex), windows=\(windows.count)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("previousWindow: tmux executable not found")
            return
        }

        Task {
            logDebug("previousWindow: executing tmux previous-window")
            let output = await runProcessOutput(tmux, args: ["previous-window", "-t", sessionName])
            logDebug("previousWindow: tmux output='\(output)'")

            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))

            logDebug("previousWindow: refreshing state")
            await checkActiveProcess()
            logInfo("previousWindow: completed - now at index=\(currentWindowIndex)")
        }
    }

    func splitHorizontal() {
        logInfo("splitHorizontal: requested")
        splitPane(direction: "-h")
    }

    func splitVertical() {
        logInfo("splitVertical: requested")
        splitPane(direction: "-v")
    }

    private func splitPane(direction: String) {
        logInfo("splitPane: direction=\(direction), session=\(sessionName)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("splitPane: tmux executable not found")
            return
        }

        var args = ["split-window", direction, "-t", sessionName]
        if !workingDirectory.isEmpty {
            args += ["-c", workingDirectory]
        }
        logDebug("splitPane: executing \(tmux) \(args.joined(separator: " "))")

        Task {
            let output = await runProcessOutput(tmux, args: args)
            logDebug("splitPane: tmux output='\(output)'")

            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))
            await checkActiveProcess()
            logInfo("splitPane: completed - pane count now \(paneCount)")
        }
    }

    func rotatePane() {
        logInfo("rotatePane: requested for session \(sessionName), pane count=\(paneCount)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("rotatePane: tmux executable not found")
            return
        }

        Task {
            logDebug("rotatePane: executing tmux select-pane")
            let output = await runProcessOutput(tmux, args: ["select-pane", "-t", "\(sessionName):.+"])
            logDebug("rotatePane: tmux output='\(output)'")

            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))
            await checkActiveProcess()
            logInfo("rotatePane: completed")
        }
    }

    func closeWindow() {
        logInfo("closeWindow: requested for session \(sessionName), windows count=\(windows.count)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("closeWindow: tmux executable not found")
            return
        }

        Task {
            logDebug("closeWindow: executing tmux kill-window")
            let output = await runProcessOutput(tmux, args: ["kill-window", "-t", sessionName])
            logDebug("closeWindow: tmux output='\(output)'")

            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))
            await checkActiveProcess()
            logInfo("closeWindow: completed - windows now count=\(windows.count)")
        }
    }

    func selectWindow(index: Int) {
        logInfo("selectWindow: requested index=\(index), current=\(currentWindowIndex)")

        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else {
            logError("selectWindow: tmux executable not found")
            return
        }

        Task {
            logDebug("selectWindow: executing tmux select-window \(sessionName):\(index)")
            let output = await runProcessOutput(tmux, args: ["select-window", "-t", "\(sessionName):\(index)"])
            logDebug("selectWindow: tmux output='\(output)'")

            try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))
            await checkActiveProcess()
            logInfo("selectWindow: completed - now at index=\(currentWindowIndex)")
        }
    }

    func sendCommand(_ command: String, inNewVerticalPane: Bool = false) {
        let expandedCommand = ZeusCommandVariables.expand(command, workingDirectory: workingDirectory)
        logInfo("sendCommand: '\(command)', inNewVerticalPane=\(inNewVerticalPane), tmuxUnavailable=\(tmuxUnavailable)")
        if expandedCommand != command {
            logInfo("sendCommand: expanded variables using workingDirectory='\(workingDirectory)'")
        }

        if !tmuxUnavailable, let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) {
            Task {
                let target: String
                if inNewVerticalPane {
                    logDebug("sendCommand: creating vertical pane for command")
                    target = await createVerticalPane(using: tmux, sessionName: sessionName)
                    logDebug("sendCommand: new pane target=\(target)")
                } else {
                    target = sessionName
                }
                logDebug("sendCommand: sending to target=\(target)")
                await runProcessOutput(tmux, args: ["send-keys", "-t", target, expandedCommand, "Enter"])

                try? await Task.sleep(for: .milliseconds(config.tmuxSettleDelayMs))
                await checkActiveProcess()
                logInfo("sendCommand: completed via tmux")
            }
        } else {
            logDebug("sendCommand: sending directly to terminal view (no tmux)")
            let bytes = Array((expandedCommand + "\n").utf8)
            terminalView.send(data: bytes[...])
            logInfo("sendCommand: completed via direct PTY write")
        }
    }

    private func createVerticalPane(using tmux: String, sessionName: String) async -> String {
        logDebug("createVerticalPane: session=\(sessionName)")
        var args = ["split-window", "-h", "-P", "-F", "#{pane_id}", "-t", sessionName]
        if !workingDirectory.isEmpty {
            args += ["-c", workingDirectory]
        }
        let output = await runProcessOutput(tmux, args: args)
        let paneID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        logDebug("createVerticalPane: pane_id='\(paneID)'")
        return paneID.isEmpty ? sessionName : paneID
    }
}

@discardableResult
nonisolated func runProcessOutput(_ executable: String, args: [String]) async -> String {
    logDebug("runProcessOutput: \(executable) \(args.joined(separator: " "))")
    return await withCheckedContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        process.terminationHandler = { p in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""
            logDebug("runProcessOutput: terminated with status \(p.terminationStatus), stdout='\(output)', stderr='\(stderr)'")
            continuation.resume(returning: output)
        }
        do {
            try process.run()
            logDebug("runProcessOutput: process started, pid=\(process.processIdentifier)")
        } catch {
            logError("runProcessOutput: failed to start process: \(error)")
            continuation.resume(returning: "")
        }
    }
}

private final class TerminalEntryDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    weak var entry: TerminalEntry?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        logDebug("TerminalEntryDelegate: size changed to \(newCols)x\(newRows)")
    }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        logDebug("TerminalEntryDelegate: title changed to '\(title)'")
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        logDebug("TerminalEntryDelegate: directory updated to '\(directory ?? "nil")'")
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        logInfo("TerminalEntryDelegate: process terminated with exitCode=\(exitCode.map { String($0) } ?? "nil")")
        DispatchQueue.main.async { self.entry?.isRunning = false }
    }
}

@MainActor
final class TerminalStore: ObservableObject {
    private var entries: [UUID: TerminalEntry] = [:]
    @Published private(set) var activeProcessTaskIDs: Set<UUID> = []
    @Published private(set) var attentionTaskIDs: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []
    private var periodicCleanupTask: Task<Void, Never>?

    private let config: TerminalConfig
    private var taskMetadata: [UUID: (name: String, watchMode: WatchMode)] = [:]
    private let notifier: ActivityNotifier
    nonisolated(unsafe) private var optionKeyMonitor: Any?
    nonisolated(unsafe) private var shiftReturnMonitor: Any?

    init(config: TerminalConfig = .init(), notificationConfig: NotificationConfig = .init()) {
        self.config = config
        self.notifier = ActivityNotifier(config: notificationConfig)
    }

    deinit {
        if let monitor = optionKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = shiftReturnMonitor {
            NSEvent.removeMonitor(monitor)
        }
        periodicCleanupTask?.cancel()
    }

    func entry(for id: UUID) -> TerminalEntry {
        logInfo("TerminalStore.entry(for: \(id.uuidString)) - entries count=\(entries.count)")
        if let existing = entries[id] {
            logDebug("TerminalStore: returning existing entry")
            return existing
        }
        logInfo("TerminalStore: creating new TerminalEntry")
        installOptionKeyMonitor()
        installShiftReturnMonitor()
        let entry = TerminalEntry(taskID: id, config: config)
        entries[id] = entry
        entry.$hasActiveProcess
            .removeDuplicates()
            .scan((false, false)) { ($0.1, $1) }   // (previousValue, currentValue)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, id] pair in
                guard let self else { return }
                let (wasActive, isActive) = pair
                logDebug("TerminalStore: hasActiveProcess sink - wasActive=\(wasActive), isActive=\(isActive)")
                if isActive {
                    self.activeProcessTaskIDs.insert(id)
                    logInfo("TerminalStore: task \(id.uuidString) became active")
                } else {
                    self.activeProcessTaskIDs.remove(id)
                    // Transition active → idle: fire alert if watch mode is on
                    if wasActive, let meta = self.taskMetadata[id], meta.watchMode != .off {
                        logInfo("TerminalStore: task \(id.uuidString) transitioned active→idle, firing notification")
                        self.attentionTaskIDs.insert(id)
                        self.notifier.notify(taskName: meta.name, watchMode: meta.watchMode)
                    }
                }
            }
            .store(in: &cancellables)
        return entry
    }

    /// Update cached metadata for a task (call when the task's terminal opens or watch mode changes).
    func updateTaskMetadata(taskID: UUID, name: String, watchMode: WatchMode, workingDirectory: String = "") {
        logInfo("TerminalStore.updateTaskMetadata: task=\(taskID.uuidString), name='\(name)', watchMode=\(watchMode), cwd='\(workingDirectory)'")
        taskMetadata[taskID] = (name: name, watchMode: watchMode)
        entries[taskID]?.workingDirectory = workingDirectory
    }

    private func installOptionKeyMonitor() {
        guard optionKeyMonitor == nil else { return }
        logInfo("Installing Option key monitor for text selection")
        optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let optionHeld = event.modifierFlags.contains(.option)
            logDebug("Option key flagsChanged: optionHeld=\(optionHeld)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newValue = !optionHeld
                logDebug("Setting mouseReportingEnabled=\(newValue) on \(entries.count) entries")
                for entry in entries.values where entry.mouseReportingEnabled != newValue {
                    entry.mouseReportingEnabled = newValue
                }
            }
            return event
        }
    }

    // Intercept Shift+Return when a terminal view has focus and forward the kitty
    // keyboard protocol sequence (ESC [ 1 3 ; 2 u) instead of plain \r, so apps
    // like Claude Code can distinguish Shift+Enter (insert newline) from Enter (submit).
    //
    // Strategy: use `tmux send-keys -l` to inject the literal bytes directly into the
    // active pane — this bypasses tmux's own key-binding / input-parsing layer and
    // delivers the raw sequence to the running program (Claude Code) without needing
    // any tmux extended-keys configuration.  Falls back to a direct PTY write when
    // tmux is unavailable.
    private func installShiftReturnMonitor() {
        guard shiftReturnMonitor == nil else { return }
        logInfo("Installing Shift+Return monitor for kitty keyboard protocol")
        shiftReturnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let relevantFlags = event.modifierFlags.intersection([.shift, .option, .command, .control, .function])
            guard relevantFlags == .shift, event.keyCode == 36 || event.keyCode == 76 else {
                return event
            }
            Task { @MainActor [weak self] in
                guard let self,
                      let firstResponder = NSApplication.shared.keyWindow?.firstResponder
                          as? LocalProcessTerminalView else { return }

                if let entry = entries.values.first(where: { $0.terminalView === firstResponder }),
                   !entry.tmuxUnavailable,
                   let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) {
                    // Inject ESC [ 1 3 ; 2 u (Shift+Enter, kitty keyboard protocol)
                    // directly into the pane via `send-keys -l` (literal bytes).
                    let sessionName = "\(config.tmuxSessionPrefix)\(entry.taskID.uuidString)"
                    logDebug("Shift+Return: tmux send-keys -l to session \(sessionName)")
                    await runProcessOutput(tmux, args: ["send-keys", "-t", sessionName, "-l", "\u{1b}[13;2u"])
                } else {
                    // No tmux — write directly to the PTY.
                    logDebug("Shift+Return: direct PTY send of kitty ESC [ 1 3 ; 2 u")
                    firstResponder.send([0x1b, 0x5b, 0x31, 0x33, 0x3b, 0x32, 0x75])
                }
            }
            return nil // consume the event so SwiftTerm doesn't also send plain \r
        }
    }

    /// Kill the tmux session for a task and remove it from the cache.
    func killSession(for taskID: UUID) {
        logInfo("TerminalStore.killSession: task=\(taskID.uuidString)")
        entries[taskID]?.isRunning = false
        entries.removeValue(forKey: taskID)
        if let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) {
            let sessionName = "\(config.tmuxSessionPrefix)\(taskID.uuidString)"
            logDebug("TerminalStore.killSession: killing tmux session \(sessionName)")
            Task {
                await terminateSessionProcesses(
                    sessionName: sessionName, tmux: tmux,
                    pkillPath: config.pkillPath, sigtermGracePeriodMs: config.sigtermGracePeriodMs
                )
                await runProcessOutput(tmux, args: ["kill-session", "-t", sessionName])
            }
        } else {
            logWarning("TerminalStore.killSession: tmux not found, skipping session kill")
        }
        activeProcessTaskIDs.remove(taskID)
        attentionTaskIDs.remove(taskID)
    }

    /// Clear the attention state when the user opens the task's terminal.
    func clearAttention(taskID: UUID) {
        logDebug("TerminalStore.clearAttention: task=\(taskID.uuidString)")
        attentionTaskIDs.remove(taskID)
    }

    /// Kill any `<prefix>*` tmux sessions whose task ID is not in `keepingTaskIDs`.
    func cleanupOrphanedSessions(keepingTaskIDs: Set<UUID>) {
        guard let tmux = tmuxExecutable(searchPaths: config.tmuxSearchPaths) else { return }
        let prefix = config.tmuxSessionPrefix
        Task { @MainActor [weak self] in
            guard let self else { return }
            let output = await runProcessOutput(tmux, args: ["list-sessions", "-F", "#{session_name}"])
            let orphans = output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix(prefix) }
                .compactMap { session -> (session: String, taskID: UUID)? in
                    let uuidString = String(session.dropFirst(prefix.count))
                    guard let id = UUID(uuidString: uuidString) else { return nil }
                    return (session, id)
                }
                .filter { !keepingTaskIDs.contains($0.taskID) }
            guard !orphans.isEmpty else { return }
            logInfo("TerminalStore.cleanupOrphanedSessions: found \(orphans.count) orphaned session(s)")
            for (session, taskID) in orphans {
                logInfo("TerminalStore.cleanupOrphanedSessions: killing \(session)")
                await terminateSessionProcesses(
                    sessionName: session, tmux: tmux,
                    pkillPath: config.pkillPath, sigtermGracePeriodMs: config.sigtermGracePeriodMs
                )
                await runProcessOutput(tmux, args: ["kill-session", "-t", session])
                entries[taskID]?.isRunning = false
                entries.removeValue(forKey: taskID)
                activeProcessTaskIDs.remove(taskID)
                attentionTaskIDs.remove(taskID)
            }
        }
    }

    /// Start a repeating cleanup that kills orphaned tmux sessions.
    func startPeriodicCleanup(interval: TimeInterval = 300, taskIDsProvider: @escaping @MainActor () -> Set<UUID>) {
        periodicCleanupTask?.cancel()
        periodicCleanupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            cleanupOrphanedSessions(keepingTaskIDs: taskIDsProvider())
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                cleanupOrphanedSessions(keepingTaskIDs: taskIDsProvider())
            }
        }
    }
}

/// Send SIGTERM to all child processes of each pane in a tmux session, then wait briefly
/// for them to handle the signal before the caller kills the session.
nonisolated func terminateSessionProcesses(
    sessionName: String, tmux: String,
    pkillPath: String, sigtermGracePeriodMs: Int
) async {
    let paneOutput = await runProcessOutput(
        tmux, args: ["list-panes", "-s", "-t", sessionName, "-F", "#{pane_pid}"]
    )
    let panePIDs = paneOutput
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard !panePIDs.isEmpty else { return }
    logDebug("terminateSessionProcesses: \(sessionName) has \(panePIDs.count) pane(s)")
    for pid in panePIDs {
        logDebug("terminateSessionProcesses: SIGTERM children of pane shell pid=\(pid)")
        await runProcessOutput(pkillPath, args: ["-TERM", "-P", pid])
    }
    try? await Task.sleep(for: .milliseconds(sigtermGracePeriodMs))
}

func tmuxExecutable(searchPaths: [String] = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]) -> String? {
    let found = searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    logDebug("tmuxExecutable: found=\(found ?? "nil")")
    return found
}

// MARK: - Font helpers

private func resolvedFont(_ config: TerminalConfig) -> NSFont {
    let size = CGFloat(config.fontSize)
    let weight = fontWeightValue(config.fontWeight)
    if config.fontFamily == "monospacedSystemFont" {
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    return NSFont(name: config.fontFamily, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

private func fontWeightValue(_ string: String) -> NSFont.Weight {
    switch string.lowercased() {
    case "ultralight": return .ultraLight
    case "thin":       return .thin
    case "light":      return .light
    case "medium":     return .medium
    case "semibold":   return .semibold
    case "bold":       return .bold
    case "heavy":      return .heavy
    case "black":      return .black
    default:           return .regular
    }
}
