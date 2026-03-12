import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    let task: AgentTask
    @StateObject private var coordinator = TerminalCoordinator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(task.name)
                    .font(.headline)
                Spacer()
                Text(coordinator.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.bar)

            TerminalRepresentable(task: task, coordinator: coordinator)
        }
        .navigationTitle(task.name)
    }
}

final class TerminalCoordinator: ObservableObject {
    @Published var isRunning = false
}

struct TerminalRepresentable: NSViewRepresentable {
    let task: AgentTask
    @ObservedObject var coordinator: TerminalCoordinator

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.processDelegate = context.coordinator
        return terminalView
    }

    func updateNSView(_ terminalView: LocalProcessTerminalView, context: Context) {
        if terminalView.process?.running != true {
            let shell = task.command.isEmpty
                ? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash")
                : task.command
            let cwd = task.workingDirectory.path(percentEncoded: false)
            terminalView.startProcess(executable: shell, args: ["-l"], currentDirectory: cwd)
            coordinator.isRunning = true
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }
    }

    func makeCoordinator() -> TerminalDelegate {
        TerminalDelegate(coordinator: coordinator)
    }

    static func dismantleNSView(_ terminalView: LocalProcessTerminalView, coordinator: TerminalDelegate) {
        if terminalView.process?.running == true {
            terminalView.terminate()
            coordinator.appCoordinator?.isRunning = false
        }
    }
}

class TerminalDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    weak var appCoordinator: TerminalCoordinator?

    init(coordinator: TerminalCoordinator) {
        self.appCoordinator = coordinator
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        appCoordinator?.isRunning = false
    }
}
