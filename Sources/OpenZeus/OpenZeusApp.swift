import SwiftUI

@main
struct OpenZeusApp: App {
    @StateObject private var terminalStore = TerminalStore()
    @StateObject private var appDatabase = try! AppDatabase()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(terminalStore)
                .environmentObject(appDatabase)
        }
    }
}
