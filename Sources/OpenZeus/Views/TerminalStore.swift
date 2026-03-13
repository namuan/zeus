import AppKit
import Combine
import SwiftTerm

struct TmuxWindow: Equatable {
    let index: Int
    let name: String
}

@MainActor
final class TerminalEntry: ObservableObject {
    let taskID: UUID
    let terminalView: LocalProcessTerminalView
    @Published var isRunning = false {
        didSet { isRunning ? startPolling() : stopPolling() }
    }
    @Published var hasActiveProcess = false
    @Published var tmuxUnavailable = false
    @Published var windows: [TmuxWindow] = []
    @Published var currentWindowIndex: Int = 0
    var workingDirectory: String = ""

    private let delegate: TerminalEntryDelegate
    private var pollTimer: Timer?

    private static let knownShells: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "csh", "tcsh", "login",
        "tmux", "tmux: server",
    ]

    init(taskID: UUID) {
        self.taskID = taskID
        terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let d = TerminalEntryDelegate()
        delegate = d
        d.entry = self
        terminalView.processDelegate = d
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        Task { await checkActiveProcess() }  // immediate check on start
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkActiveProcess() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        hasActiveProcess = false
    }

    private func checkActiveProcess() async {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        async let commandFuture = runProcessOutput(tmux, args: [
            "display-message", "-p", "-t", sessionName, "#{pane_current_command}",
        ])
        async let windowsFuture = runProcessOutput(tmux, args: [
            "list-windows", "-t", sessionName, "-F",
            "#{window_index}\t#{window_name}\t#{window_active}",
        ])
        let (commandOutput, windowsOutput) = await (commandFuture, windowsFuture)
        let command = commandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        hasActiveProcess = !command.isEmpty && !Self.knownShells.contains(command)
        parseWindowState(windowsOutput)
    }

    private func parseWindowState(_ output: String) {
        let lines = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        var wins: [TmuxWindow] = []
        var activeIdx = 0
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3, let idx = Int(parts[0]) else { continue }
            wins.append(TmuxWindow(index: idx, name: parts[1]))
            if parts[2].trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                activeIdx = idx
            }
        }
        if !wins.isEmpty {
            windows = wins
            currentWindowIndex = activeIdx
        }
    }

    // MARK: - Tmux window control

    func openWindow() {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        var args = ["new-window", "-t", sessionName]
        if !workingDirectory.isEmpty {
            args += ["-c", workingDirectory]
        }
        Task {
            await runProcessOutput(tmux, args: args)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await checkActiveProcess()
        }
    }

    func nextWindow() {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        Task {
            await runProcessOutput(tmux, args: ["next-window", "-t", sessionName])
            try? await Task.sleep(nanoseconds: 200_000_000)
            await checkActiveProcess()
        }
    }

    func previousWindow() {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        Task {
            await runProcessOutput(tmux, args: ["previous-window", "-t", sessionName])
            try? await Task.sleep(nanoseconds: 200_000_000)
            await checkActiveProcess()
        }
    }

    func splitHorizontal() {
        splitPane(direction: "-h")
    }

    func splitVertical() {
        splitPane(direction: "-v")
    }

    private func splitPane(direction: String) {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        var args = ["split-window", direction, "-t", sessionName]
        if !workingDirectory.isEmpty {
            args += ["-c", workingDirectory]
        }
        Task {
            await runProcessOutput(tmux, args: args)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await checkActiveProcess()
        }
    }

    func closeWindow() {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        Task {
            await runProcessOutput(tmux, args: ["kill-window", "-t", sessionName])
            try? await Task.sleep(nanoseconds: 200_000_000)
            await checkActiveProcess()
        }
    }

    func selectWindow(index: Int) {
        guard let tmux = tmuxExecutable() else { return }
        let sessionName = "zeus-\(taskID.uuidString)"
        Task {
            await runProcessOutput(tmux, args: ["select-window", "-t", "\(sessionName):\(index)"])
            try? await Task.sleep(nanoseconds: 200_000_000)
            await checkActiveProcess()
        }
    }
}

@discardableResult
private nonisolated func runProcessOutput(_ executable: String, args: [String]) async -> String {
    await withCheckedContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.entry?.isRunning = false }
    }
}

@MainActor
final class TerminalStore: ObservableObject {
    private var entries: [UUID: TerminalEntry] = [:]
    @Published private(set) var activeProcessTaskIDs: Set<UUID> = []
    @Published private(set) var attentionTaskIDs: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []

    // Per-task metadata needed to fire notifications without a DB lookup
    private var taskMetadata: [UUID: (name: String, watchMode: WatchMode)] = [:]
    private let notifier = ActivityNotifier()

    func entry(for id: UUID) -> TerminalEntry {
        if let existing = entries[id] { return existing }
        let entry = TerminalEntry(taskID: id)
        entries[id] = entry
        entry.$hasActiveProcess
            .removeDuplicates()
            .scan((false, false)) { ($0.1, $1) }   // (previousValue, currentValue)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, id] pair in
                guard let self else { return }
                let (wasActive, isActive) = pair
                if isActive {
                    self.activeProcessTaskIDs.insert(id)
                } else {
                    self.activeProcessTaskIDs.remove(id)
                    // Transition active → idle: fire alert if watch mode is on
                    if wasActive, let meta = self.taskMetadata[id], meta.watchMode != .off {
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
        taskMetadata[taskID] = (name: name, watchMode: watchMode)
        entries[taskID]?.workingDirectory = workingDirectory
    }

    /// Clear the attention state when the user opens the task's terminal.
    func clearAttention(taskID: UUID) {
        attentionTaskIDs.remove(taskID)
    }
}

func tmuxExecutable() -> String? {
    let candidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}
