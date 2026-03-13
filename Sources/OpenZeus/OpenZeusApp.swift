import SwiftUI
import SwiftData

@main
struct OpenZeusApp: App {
    @StateObject private var terminalStore = TerminalStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(terminalStore)
        }
        .modelContainer(for: [Project.self, AgentTask.self])
    }
}
