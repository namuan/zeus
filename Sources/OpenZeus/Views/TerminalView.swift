import SwiftUI
import SwiftTerm

struct TerminalPane: View {
    let task: AgentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(task.name)
                    .font(.headline)
                Spacer()
                Text(task.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.bar)

            SwiftTermViewRepresentable(task: task)
        }
        .navigationTitle(task.name)
    }
}

struct SwiftTermViewRepresentable: NSViewRepresentable {
    let task: AgentTask

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let terminal = SwiftTerm.TerminalView(frame: .zero)
        return terminal
    }

    func updateNSView(_ terminalView: SwiftTerm.TerminalView, context: Context) {
        // Future: pass task.command and terminalState to restore terminal
    }
}
