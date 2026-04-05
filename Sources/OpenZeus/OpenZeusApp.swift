import SwiftUI
import UserNotifications

@main
struct OpenZeusApp: App {
    @State private var appConfig: AppConfig
    @StateObject private var terminalStore: TerminalStore
    @StateObject private var appDatabase: AppDatabase

    init() {
        let config = AppConfig.load()
        _appConfig = State(initialValue: config)
        FileLogger.config = config.logging
        _terminalStore = StateObject(wrappedValue: TerminalStore(
            config: config.terminal,
            notificationConfig: config.notifications
        ))
        _appDatabase = StateObject(wrappedValue: try! AppDatabase(storage: config.storage))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(terminalStore)
                .environmentObject(appDatabase)
                .environment(\.appConfig, appConfig)
                .onAppear {
                    UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    DispatchQueue.main.async {
                        NSApp.windows.first?.zoom(nil)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .appConfigChanged)) { _ in
                    appConfig = AppConfig.load()
                }
        }

        Settings {
            SettingsView()
                .environmentObject(terminalStore)
                .environmentObject(appDatabase)
        }
    }
}
