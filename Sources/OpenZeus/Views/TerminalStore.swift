import AppKit
import Combine
import SwiftTerm

enum ZeusCommandVariables {
    static let projectDirectoryToken = "${zeus_project_directory}"
    static let supportedTokens = [projectDirectoryToken]
    static let helpText = "Available variable: \(supportedTokens.joined(separator: ", "))"

    static func expand(_ command: String, projectDirectory: String) -> String {
        guard command.contains(projectDirectoryToken) else { return command }
        let directory = projectDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else { return command }
        return command.replacingOccurrences(of: projectDirectoryToken, with: directory)
    }
}

final class RecordingLocalProcessTerminalView: LocalProcessTerminalView {
    var outputHandler: ((Data) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        outputHandler?(Data(slice))
        super.dataReceived(slice: slice)
    }
}

enum TerminalSplitOrientation {
    case horizontal
    case vertical
}

@MainActor
final class TerminalEntry: ObservableObject {
    let taskID: UUID
    let paneID: UUID
    let isPrimaryPane: Bool
    let terminalView: RecordingLocalProcessTerminalView
    @Published var isRunning = false {
        didSet {
            isRunning ? startPolling() : stopPolling()
        }
    }
    @Published var hasActiveProcess = false
    @Published var activePaneDirectory = ""
    @Published var mouseReportingEnabled = true
    @Published var secondaryPane: TerminalEntry?
    @Published var splitOrientation: TerminalSplitOrientation?
    @Published var focusedPaneID: UUID
    @Published var primaryPaneClosed = false
    var workingDirectory = ""
    var projectDirectory = ""
    var taskName = ""
    var projectName = ""
    var recordsTranscript = false
    var onOutput: ((Data) -> Void)?
    var onProcessTerminated: (() -> Void)?
    let config: TerminalConfig
    private let delegate: TerminalEntryDelegate
    private var pollTimer: Timer?
    weak var parentEntry: TerminalEntry?
    private var knownShells: Set<String> { Set(config.knownShells) }

    init(taskID: UUID, config: TerminalConfig = .init(), paneID: UUID? = nil, isPrimaryPane: Bool = true) {
        self.taskID = taskID
        self.paneID = paneID ?? taskID
        self.isPrimaryPane = isPrimaryPane
        focusedPaneID = paneID ?? taskID
        self.config = config
        terminalView = RecordingLocalProcessTerminalView(frame: .zero)
        terminalView.font = resolvedFont(config)
        let delegate = TerminalEntryDelegate()
        self.delegate = delegate
        delegate.entry = self
        terminalView.processDelegate = delegate
        terminalView.outputHandler = { [weak self] data in
            guard let self, self.recordsTranscript else { return }
            self.onOutput?(data)
        }
    }

    func focusTerminalView() {
        let terminal = activeTerminal
        terminal.terminalView.window?.makeFirstResponder(terminal.terminalView)
    }

    func updateFont(_ config: TerminalConfig) {
        terminalView.font = resolvedFont(config)
    }

    var activeTerminal: TerminalEntry {
        guard isPrimaryPane, let secondaryPane else { return self }
        if primaryPaneClosed || focusedPaneID == secondaryPane.paneID { return secondaryPane }
        return self
    }

    var hasActivePaneProcess: Bool {
        (!primaryPaneClosed && hasActiveProcess) || secondaryPane?.hasActiveProcess == true
    }

    func focusPane(_ paneID: UUID) {
        guard isPrimaryPane else {
            parentEntry?.focusPane(paneID)
            return
        }
        focusedPaneID = primaryPaneClosed && paneID == self.paneID ? secondaryPane?.paneID ?? paneID : paneID
        let terminal = activeTerminal
        activePaneDirectory = terminal.activePaneDirectory.isEmpty ? terminal.workingDirectory : terminal.activePaneDirectory
    }

    func currentPaneDirectory(fallback: String? = nil) async -> String {
        let terminal = activeTerminal
        let directory = terminal.activePaneDirectory.isEmpty ? (fallback ?? terminal.workingDirectory) : terminal.activePaneDirectory
        guard let url = URL(string: directory), url.isFileURL else { return directory }
        return url.path
    }

    func changeDirectory(to directory: String) async -> Bool {
        let terminal = activeTerminal
        guard terminal.isRunning, !terminal.hasActiveProcess else { return false }
        let quotedDirectory = "'\(directory.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
        terminal.sendRawCommand("cd -- \(quotedDirectory)")
        terminal.workingDirectory = directory
        terminal.activePaneDirectory = directory
        if terminal !== self { activePaneDirectory = directory }
        return true
    }

    func sendCommand(_ command: String) {
        let terminal = activeTerminal
        let expandedCommand = ZeusCommandVariables.expand(command, projectDirectory: terminal.projectDirectory)
        terminal.sendRawCommand(expandedCommand)
    }

    private func sendRawCommand(_ command: String) {
        let bytes = Array((command + "\n").utf8)
        terminalView.send(data: bytes[...])
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        Task { await checkActiveProcess() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: config.pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkActiveProcess()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        hasActiveProcess = false
    }

    private func checkActiveProcess() async {
        guard isRunning else { return }
        let shellPID = Int(terminalView.process.shellPid)
        guard shellPID > 0 else {
            hasActiveProcess = false
            return
        }
        let paneInfo = ActivePaneInfo(pid: shellPID, command: URL(fileURLWithPath: config.resolvedShell).lastPathComponent)
        hasActiveProcess = await resolvedActiveCommand(paneInfo: paneInfo, knownShells: knownShells) != nil
    }
}

struct ActivePaneInfo: Equatable {
    let pid: Int?
    let command: String
}

struct ProcessSnapshot: Equatable {
    let pid: Int
    let parentPID: Int
    let stat: String
    let command: String

    var isForeground: Bool { stat.contains("+") }

    var executableName: String {
        command
            .split(separator: " ", maxSplits: 1)
            .first
            .map(String.init)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? ""
    }
}

func parseActivePaneInfo(_ output: String) -> ActivePaneInfo {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ActivePaneInfo(pid: nil, command: "") }
    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
    guard parts.count == 2 else { return ActivePaneInfo(pid: nil, command: trimmed) }
    return ActivePaneInfo(pid: Int(parts[0]), command: parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
}

func parseProcessSnapshots(_ output: String) -> [ProcessSnapshot] {
    output.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4, let pid = Int(parts[0]), let parentPID = Int(parts[1]) else { return nil }
        return ProcessSnapshot(pid: pid, parentPID: parentPID, stat: String(parts[2]), command: String(parts[3]))
    }
}

func deepestLeafDescendant(in snapshots: [ProcessSnapshot], rootPID: Int) -> ProcessSnapshot? {
    let snapshotsByPID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.pid, $0) })
    let childrenByParent = Dictionary(grouping: snapshots, by: \.parentPID)
    guard snapshotsByPID[rootPID] != nil else { return nil }
    var stack: [(pid: Int, depth: Int)] = [(rootPID, 0)]
    var visited: Set<Int> = []
    var descendants: [(snapshot: ProcessSnapshot, depth: Int)] = []
    while let current = stack.popLast() {
        guard visited.insert(current.pid).inserted, let children = childrenByParent[current.pid] else { continue }
        for child in children {
            descendants.append((child, current.depth + 1))
            stack.append((child.pid, current.depth + 1))
        }
    }
    let descendantPIDs = Set(descendants.map(\.snapshot.pid))
    let leaves = descendants.filter { candidate in
        childrenByParent[candidate.snapshot.pid, default: []].allSatisfy { !descendantPIDs.contains($0.pid) }
    }
    guard !leaves.isEmpty else { return nil }
    let foreground = leaves.filter { $0.snapshot.isForeground }
    return (foreground.isEmpty ? leaves : foreground).max {
        $0.depth == $1.depth ? $0.snapshot.pid < $1.snapshot.pid : $0.depth < $1.depth
    }?.snapshot
}

nonisolated func resolvedActiveCommand(
    paneInfo: ActivePaneInfo,
    knownShells: Set<String>,
    psExecutable: String = "/bin/ps",
    pgrepExecutable: String = "/usr/bin/pgrep"
) async -> String? {
    let command = paneInfo.command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return nil }
    guard knownShells.contains(command) else { return command }
    guard let rootPID = paneInfo.pid else { return nil }
    let descendantPIDs = await descendantProcessIDs(rootPID: rootPID, pgrepExecutable: pgrepExecutable)
    let pidList = ([rootPID] + descendantPIDs).map(String.init).joined(separator: ",")
    let output = await runProcessOutput(psExecutable, args: ["-o", "pid=,ppid=,stat=,command=", "-p", pidList])
    guard let leaf = deepestLeafDescendant(in: parseProcessSnapshots(output), rootPID: rootPID) else { return nil }
    let leafCommand = leaf.executableName.trimmingCharacters(in: .whitespacesAndNewlines)
    return leafCommand.isEmpty ? nil : leafCommand
}

nonisolated func descendantProcessIDs(rootPID: Int, pgrepExecutable: String = "/usr/bin/pgrep") async -> [Int] {
    var visited: Set<Int> = [rootPID]
    var queue: [Int] = [rootPID]
    var descendants: [Int] = []
    while !queue.isEmpty {
        let parentPID = queue.removeFirst()
        let output = await runProcessOutput(pgrepExecutable, args: ["-P", String(parentPID)])
        for childPID in output.split(separator: "\n").compactMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        where visited.insert(childPID).inserted {
            descendants.append(childPID)
            queue.append(childPID)
        }
    }
    return descendants
}

@discardableResult
nonisolated func runProcessOutput(_ executable: String, args: [String]) async -> String {
    await withCheckedContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.terminationHandler = { _ in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            try process.run()
        } catch {
            continuation.resume(returning: "")
        }
    }
}

private final class TerminalEntryDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    weak var entry: TerminalEntry?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        Task { @MainActor [weak entry] in
            guard let entry else { return }
            entry.activePaneDirectory = directory
            if let parent = entry.parentEntry, parent.focusedPaneID == entry.paneID {
                parent.activePaneDirectory = directory
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak entry] in
            entry?.isRunning = false
            entry?.onProcessTerminated?()
        }
    }
}

@MainActor
final class TerminalStore: ObservableObject {
    private var entries: [UUID: TerminalEntry] = [:]
    private var gitServices: [String: GitService] = [:]
    @Published private(set) var activeProcessTaskIDs: Set<UUID> = []
    @Published private(set) var attentionTaskIDs: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []
    private var config: TerminalConfig
    private var taskMetadata: [UUID: (name: String, watchMode: WatchMode)] = [:]
    private var activePaneIDsByTask: [UUID: Set<UUID>] = [:]
    private let transcriptRecorder = TerminalTranscriptRecorder()
    private let notifier: ActivityNotifier
    nonisolated(unsafe) private var optionKeyMonitor: Any?
    nonisolated(unsafe) private var shiftReturnMonitor: Any?
    nonisolated(unsafe) private var returnFocusMonitor: Any?
    nonisolated(unsafe) var selectedTaskID: UUID?

    init(config: TerminalConfig = .init(), notificationConfig: NotificationConfig = .init()) {
        self.config = config
        notifier = ActivityNotifier(config: notificationConfig)
    }

    func updateTerminalConfig(_ config: TerminalConfig) {
        self.config = config
        allPaneEntries.forEach { $0.updateFont(config) }
    }

    deinit {
        if let optionKeyMonitor { NSEvent.removeMonitor(optionKeyMonitor) }
        if let shiftReturnMonitor { NSEvent.removeMonitor(shiftReturnMonitor) }
        if let returnFocusMonitor { NSEvent.removeMonitor(returnFocusMonitor) }
    }

    func entry(for id: UUID, recordTranscript: Bool = false) -> TerminalEntry {
        if let entry = entries[id] {
            entry.recordsTranscript = recordTranscript || entry.recordsTranscript
            return entry
        }
        installOptionKeyMonitor()
        installShiftReturnMonitor()
        installReturnFocusMonitor()
        let entry = TerminalEntry(taskID: id, config: config)
        entry.recordsTranscript = recordTranscript
        entry.onOutput = { [weak self] data in
            guard let self else { return }
            Task { await self.transcriptRecorder.append(data, taskID: id) }
        }
        entry.onProcessTerminated = { [weak self] in
            guard let self else { return }
            let root = self.entries[id]
            if root?.isRunning != true, root?.secondaryPane?.isRunning != true {
                Task { await self.transcriptRecorder.stop(taskID: id) }
            }
        }
        entries[id] = entry
        observeActivity(entry)
        return entry
    }

    func updateTaskMetadata(taskID: UUID, name: String, watchMode: WatchMode, workingDirectory: String = "", projectDirectory: String = "", projectName: String = "", recordTranscript: Bool = true) {
        taskMetadata[taskID] = (name, watchMode)
        entries[taskID]?.recordsTranscript = recordTranscript
        entries[taskID]?.secondaryPane?.recordsTranscript = recordTranscript
        entries[taskID]?.taskName = name
        entries[taskID]?.workingDirectory = workingDirectory
        entries[taskID]?.projectDirectory = projectDirectory
        entries[taskID]?.secondaryPane?.workingDirectory = entries[taskID]?.activeTerminal.workingDirectory ?? workingDirectory
        entries[taskID]?.secondaryPane?.projectDirectory = projectDirectory
        if !projectName.isEmpty {
            entries[taskID]?.projectName = projectName
            entries[taskID]?.secondaryPane?.projectName = projectName
        }
    }

    private var allPaneEntries: [TerminalEntry] {
        entries.values.flatMap { entry in [entry] + [entry.secondaryPane].compactMap { $0 } }
    }

    private func observeActivity(_ entry: TerminalEntry) {
        let taskID = entry.taskID
        let paneID = entry.paneID
        entry.$hasActiveProcess
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                var paneIDs = self.activePaneIDsByTask[taskID, default: []]
                let wasActive = !paneIDs.isEmpty
                if isActive { paneIDs.insert(paneID) } else { paneIDs.remove(paneID) }
                self.activePaneIDsByTask[taskID] = paneIDs
                let isTaskActive = !paneIDs.isEmpty
                if isTaskActive { self.activeProcessTaskIDs.insert(taskID) } else {
                    self.activeProcessTaskIDs.remove(taskID)
                }
                if wasActive, !isTaskActive,
                   let metadata = self.taskMetadata[taskID], metadata.watchMode != .off {
                    self.attentionTaskIDs.insert(taskID)
                    self.notifier.notify(taskName: metadata.name, watchMode: metadata.watchMode)
                }
            }
            .store(in: &cancellables)
    }

    func splitTerminal(taskID: UUID, orientation: TerminalSplitOrientation) {
        guard let root = entries[taskID] else { return }
        if root.primaryPaneClosed, let active = root.secondaryPane {
            root.workingDirectory = active.workingDirectory
            root.activePaneDirectory = active.activePaneDirectory
            root.terminalView.terminal.resetToInitialState()
            root.terminalView.needsDisplay = true
            root.primaryPaneClosed = false
            root.splitOrientation = orientation
            root.focusPane(active.paneID)
            return
        }
        guard root.secondaryPane == nil else { return }
        let active = root.activeTerminal
        let pane = TerminalEntry(taskID: taskID, config: config, paneID: UUID(), isPrimaryPane: false)
        pane.parentEntry = root
        pane.recordsTranscript = root.recordsTranscript
        pane.workingDirectory = active.workingDirectory
        pane.activePaneDirectory = active.activePaneDirectory
        pane.projectDirectory = active.projectDirectory
        pane.projectName = active.projectName
        pane.taskName = active.taskName
        pane.onOutput = root.onOutput
        pane.onProcessTerminated = root.onProcessTerminated
        root.secondaryPane = pane
        root.splitOrientation = orientation
        observeActivity(pane)
    }

    func closeSplitTerminal(taskID: UUID) {
        guard let root = entries[taskID], let pane = root.secondaryPane else { return }
        if root.focusedPaneID == root.paneID, !root.primaryPaneClosed {
            root.primaryPaneClosed = true
            root.terminalView.terminate()
            root.focusPane(pane.paneID)
            var paneIDs = activePaneIDsByTask[taskID, default: []]
            paneIDs.remove(root.paneID)
            activePaneIDsByTask[taskID] = paneIDs
            if paneIDs.isEmpty { activeProcessTaskIDs.remove(taskID) }
            return
        }
        guard !root.primaryPaneClosed else { return }
        pane.recordsTranscript = false
        pane.terminalView.terminate()
        root.secondaryPane = nil
        root.splitOrientation = nil
        root.focusPane(root.paneID)
        var paneIDs = activePaneIDsByTask[taskID, default: []]
        paneIDs.remove(pane.paneID)
        activePaneIDsByTask[taskID] = paneIDs
        if paneIDs.isEmpty { activeProcessTaskIDs.remove(taskID) }
    }

    func gitService(for workingDirectory: String, config: GitConfig) -> GitService {
        if let existing = gitServices[workingDirectory] { return existing }
        let service = GitService(
            workingDirectory: workingDirectory,
            gitExecutablePath: config.executablePath,
            statusDebounceMs: config.statusDebounceMs,
            statusPollIntervalSeconds: config.statusPollIntervalSeconds
        )
        gitServices[workingDirectory] = service
        return service
    }

    func removeGitService(for workingDirectory: String) {
        gitServices[workingDirectory]?.stopWatching()
        gitServices.removeValue(forKey: workingDirectory)
    }

    private func installOptionKeyMonitor() {
        guard optionKeyMonitor == nil else { return }
        optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let enabled = !event.modifierFlags.contains(.option)
            Task { @MainActor [weak self] in
                self?.allPaneEntries.forEach { $0.mouseReportingEnabled = enabled }
            }
            return event
        }
    }

    private func installShiftReturnMonitor() {
        guard shiftReturnMonitor == nil else { return }
        shiftReturnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.shift, .option, .command, .control, .function])
            guard flags == .shift, event.keyCode == 36 || event.keyCode == 76 else { return event }
            Task { @MainActor [weak self] in
                guard let self,
                      let view = NSApplication.shared.keyWindow?.firstResponder as? LocalProcessTerminalView,
                      allPaneEntries.contains(where: { $0.terminalView === view }) else { return }
                view.send([0x1b, 0x5b, 0x31, 0x33, 0x3b, 0x32, 0x75])
            }
            return nil
        }
    }

    private func installReturnFocusMonitor() {
        guard returnFocusMonitor == nil else { return }
        returnFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.shift, .option, .command, .control, .function])
            guard flags.isEmpty, event.keyCode == 36 || event.keyCode == 76,
                  let firstResponder = NSApplication.shared.keyWindow?.firstResponder,
                  !(firstResponder is LocalProcessTerminalView), !(firstResponder is NSTextView),
                  let taskID = self?.selectedTaskID else { return event }
            Task { @MainActor [weak self] in self?.entries[taskID]?.focusTerminalView() }
            return nil
        }
    }

    func terminateAllTerminals() {
        let taskIDs = Array(entries.keys)
        taskIDs.forEach(terminateTerminal(for:))
    }

    func terminateTerminal(for taskID: UUID) {
        if let entry = entries[taskID] {
            entry.secondaryPane?.recordsTranscript = false
            entry.secondaryPane?.terminalView.terminate()
            entry.terminalView.terminate()
        }
        Task { await transcriptRecorder.stop(taskID: taskID) }
        entries.removeValue(forKey: taskID)
        activePaneIDsByTask.removeValue(forKey: taskID)
        activeProcessTaskIDs.remove(taskID)
        attentionTaskIDs.remove(taskID)
        taskMetadata.removeValue(forKey: taskID)
    }

    func clearAttention(taskID: UUID) {
        attentionTaskIDs.remove(taskID)
    }

    func transcriptDirectories(for taskID: UUID) -> [URL] {
        transcriptRecorder.transcriptDirectories(for: taskID)
    }
}

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
    case "thin": return .thin
    case "light": return .light
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "black": return .black
    default: return .regular
    }
}
