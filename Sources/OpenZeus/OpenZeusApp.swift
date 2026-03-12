import SwiftUI
import SwiftData

@main
struct OpenZeusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, AgentTask.self])
    }
}
