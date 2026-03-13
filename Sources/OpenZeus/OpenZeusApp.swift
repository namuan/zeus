import SwiftUI
import UserNotifications

@main
struct OpenZeusApp: App {
    @StateObject private var terminalStore = TerminalStore()
    @StateObject private var appDatabase = try! AppDatabase()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(terminalStore)
                .environmentObject(appDatabase)
                .onAppear {
                    UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    DispatchQueue.main.async {
                        NSApp.windows.first?.zoom(nil)
                    }
                }
        }
    }
}
