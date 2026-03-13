import AppKit
import SwiftTerm

@MainActor
final class TerminalEntry: ObservableObject {
    let terminalView: LocalProcessTerminalView
    @Published var isRunning = false
    @Published var tmuxUnavailable = false
    // Held strongly so process events arrive even when the terminal is hidden
    private let delegate: TerminalEntryDelegate

    init() {
        terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let d = TerminalEntryDelegate()
        delegate = d
        d.entry = self
        terminalView.processDelegate = d
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

    func entry(for id: UUID) -> TerminalEntry {
        if let existing = entries[id] { return existing }
        let entry = TerminalEntry()
        entries[id] = entry
        return entry
    }
}
