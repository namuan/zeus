import Foundation

/// Notification level for a watched task terminal.
enum WatchMode: String, Codable, Sendable, CaseIterable {
    case off     // no alerting
    case on      // sound + notification
    case silent  // notification only, no sound

    var next: WatchMode {
        switch self {
        case .off:    return .on
        case .on:     return .silent
        case .silent: return .off
        }
    }

    var systemImage: String {
        switch self {
        case .off:    return "bell.slash"
        case .on:     return "bell.fill"
        case .silent: return "bell"
        }
    }

    var label: String {
        switch self {
        case .off:    return "Watch: Off"
        case .on:     return "Watch: On (sound + notification)"
        case .silent: return "Watch: Silent (notification only)"
        }
    }
}
