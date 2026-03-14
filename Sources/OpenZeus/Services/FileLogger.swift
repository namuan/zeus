import Foundation

/// File-based logger with rolling log files.
/// Logs to ~/Library/Logs/OpenZeus/
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    private let logsDirectory: URL
    private let logFileURL: URL
    private let maxFileSize: Int = 5 * 1024 * 1024  // 5MB per file
    private let maxBackupFiles: Int = 5
    private let queue = DispatchQueue(label: "com.openzeus.filelogger", qos: .utility)
    private var fileHandle: FileHandle?

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logsDirectory = home.appendingPathComponent("Library/Logs/OpenZeus", isDirectory: true)
        logFileURL = logsDirectory.appendingPathComponent("openzeus.log")

        createLogsDirectoryIfNeeded()
        openFileHandle()
    }

    private func createLogsDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    private func openFileHandle() {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
    }

    func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = Self.formatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)\n"

        queue.async { [weak self] in
            guard let self else { return }
            self.writeLog(logLine)
        }
    }

    private func writeLog(_ logLine: String) {
        rotateIfNeeded()

        guard let data = logLine.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    private func rotateIfNeeded() {
        guard let handle = fileHandle else {
            openFileHandle()
            return
        }

        do {
            let fileSize = try handle.offset()
            if fileSize >= maxFileSize {
                rotateFile()
            }
        } catch {
            // If we can't get offset, try to reopen
            fileHandle?.closeFile()
            openFileHandle()
        }
    }

    private func rotateFile() {
        fileHandle?.closeFile()

        // Delete oldest backup if we have too many
        let oldestBackup = logFileURL.appendingPathExtension("5")
        try? FileManager.default.removeItem(at: oldestBackup)

        // Shift existing backups: .4 -> .5, .3 -> .4, etc.
        for i in stride(from: maxBackupFiles - 1, through: 1, by: -1) {
            let oldBackup = logFileURL.appendingPathExtension("\(i)")
            let newBackup = logFileURL.appendingPathExtension("\(i + 1)")
            try? FileManager.default.moveItem(at: oldBackup, to: newBackup)
        }

        // Move current log to .1
        let firstBackup = logFileURL.appendingPathExtension("1")
        try? FileManager.default.moveItem(at: logFileURL, to: firstBackup)

        // Create new log file
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        openFileHandle()
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Convenience Methods

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    /// Synchronously flush and close (call on app termination)
    func flush() {
        queue.sync {
            fileHandle?.synchronizeFile()
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }
}

// MARK: - Global Convenience

func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    FileLogger.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    FileLogger.shared.info(message, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    FileLogger.shared.warning(message, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    FileLogger.shared.error(message, file: file, function: function, line: line)
}
