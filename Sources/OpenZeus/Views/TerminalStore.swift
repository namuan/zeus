import AppKit
import Combine
import SwiftTerm

@MainActor
final class TerminalEntry: ObservableObject {
    let taskID: UUID
    let terminalView: LocalProcessTerminalView
    @Published var isRunning = false {
        didSet { isRunning ? startPolling() : stopPolling() }
    }
    @Published var hasActiveProcess = false
    @Published var tmuxUnavailable = false

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
        let output = await runProcessOutput(tmux, args: [
            "display-message", "-p", "-t", sessionName, "#{pane_current_command}",
        ])
        let command = output.trimmingCharacters(in: .whitespacesAndNewlines)
        hasActiveProcess = !command.isEmpty && !Self.knownShells.contains(command)
    }
}

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
    func updateTaskMetadata(taskID: UUID, name: String, watchMode: WatchMode) {
        taskMetadata[taskID] = (name: name, watchMode: watchMode)
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
