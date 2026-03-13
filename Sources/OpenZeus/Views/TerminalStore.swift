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
    private var cancellables: Set<AnyCancellable> = []

    func entry(for id: UUID) -> TerminalEntry {
        if let existing = entries[id] { return existing }
        let entry = TerminalEntry(taskID: id)
        entries[id] = entry
        entry.$hasActiveProcess
            .receive(on: DispatchQueue.main)
            .sink { [weak self, id] isActive in
                if isActive {
                    self?.activeProcessTaskIDs.insert(id)
                } else {
                    self?.activeProcessTaskIDs.remove(id)
                }
            }
            .store(in: &cancellables)
        return entry
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
