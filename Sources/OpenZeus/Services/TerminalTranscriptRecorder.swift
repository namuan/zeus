import Foundation

struct TerminalTranscriptSanitizer: Sendable {
    private enum EscapeState: Sendable {
        case text
        case escape
        case controlSequence([UInt8])
        case string
        case stringEscape
    }

    private var escapeState: EscapeState = .text
    private var currentLine: [UInt8] = []
    private var cursor = 0

    mutating func append(_ data: Data) -> String {
        var output = Data()
        for byte in data {
            switch escapeState {
            case .text: consumeTextByte(byte, output: &output)
            case .escape: consumeEscapeByte(byte)
            case .controlSequence(let parameters): consumeControlSequenceByte(byte, parameters: parameters)
            case .string:
                if byte == 0x07 { escapeState = .text } else if byte == 0x1B { escapeState = .stringEscape }
            case .stringEscape: escapeState = byte == 0x5C ? .text : .string
            }
        }
        return String(bytes: output, encoding: .utf8) ?? ""
    }

    mutating func finish() -> String {
        defer {
            currentLine.removeAll()
            cursor = 0
        }
        return completedCurrentLine()
    }

    private mutating func consumeTextByte(_ byte: UInt8, output: inout Data) {
        switch byte {
        case 0x1B: escapeState = .escape
        case 0x0A:
            output.append(contentsOf: completedCurrentLine().utf8)
            currentLine.removeAll()
            cursor = 0
        case 0x0D: cursor = 0
        case 0x08, 0x7F: cursor = max(0, cursor - 1)
        case 0x09: write(bytes: [0x20, 0x20, 0x20, 0x20])
        case 0x00...0x1F: break
        default: write(bytes: [byte])
        }
    }

    private mutating func consumeEscapeByte(_ byte: UInt8) {
        switch byte {
        case 0x5B: escapeState = .controlSequence([])
        case 0x5D, 0x50, 0x5E, 0x5F, 0x6B: escapeState = .string
        default: escapeState = .text
        }
    }

    private mutating func consumeControlSequenceByte(_ byte: UInt8, parameters: [UInt8]) {
        guard !(0x40...0x7E).contains(byte) else {
            applyControlSequence(finalByte: byte, parameters: parameters)
            escapeState = .text
            return
        }
        escapeState = .controlSequence(parameters + [byte])
    }

    private mutating func applyControlSequence(finalByte: UInt8, parameters: [UInt8]) {
        let parameterString = String(bytes: parameters, encoding: .ascii) ?? ""
        let values = parameterString.split(separator: ";").compactMap { Int($0.filter(\.isNumber)) }
        let value = values.first ?? 0
        switch finalByte {
        case 0x4A:
            if value == 0 || value == 2 { currentLine.removeAll() }
            cursor = 0
        case 0x4B:
            if value == 0 { currentLine.removeSubrange(min(cursor, currentLine.count)..<currentLine.count) } else if value == 2 {
                currentLine.removeAll()
                cursor = 0
            }
        case 0x43: cursor += value == 0 ? 1 : value
        case 0x44: cursor = max(0, cursor - (value == 0 ? 1 : value))
        case 0x47: cursor = max(0, (value == 0 ? 1 : value) - 1)
        case 0x48, 0x66:
            if values.count > 1 { cursor = max(0, values[1] - 1) }
        default: break
        }
    }

    private mutating func write(bytes: [UInt8]) {
        for byte in bytes {
            if cursor < currentLine.count {
                currentLine[cursor] = byte
            } else {
                while currentLine.count < cursor { currentLine.append(0x20) }
                currentLine.append(byte)
            }
            cursor += 1
        }
    }

    private func completedCurrentLine() -> String {
        let trimmedLine = currentLine.reversed().drop(while: { $0 == 0x20 }).reversed()
        guard !trimmedLine.isEmpty else { return "" }
        return (String(bytes: trimmedLine, encoding: .utf8) ?? "") + "\n"
    }
}

actor TerminalTranscriptRecorder {
    private struct Recording: Sendable {
        let transcriptURL: URL
        var sanitizer = TerminalTranscriptSanitizer()
    }

    private let rootURL: URL
    private var recordings: [UUID: Recording] = [:]

    init(rootURL: URL = TerminalTranscriptRecorder.defaultRootURL()) {
        self.rootURL = rootURL
    }

    nonisolated static func defaultRootURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("OpenZeus", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
    }

    func revealDirectory() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func transcriptDirectoryURL() -> URL { rootURL }

    nonisolated func transcriptDirectories(for taskID: UUID) -> [URL] {
        let taskDirectory = rootURL.appendingPathComponent(taskID.uuidString, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: taskDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    func append(_ data: Data, taskID: UUID) {
        if recordings[taskID] == nil { start(taskID: taskID) }
        guard var recording = recordings[taskID] else { return }
        let text = recording.sanitizer.append(data)
        if !text.isEmpty { append(text, to: recording.transcriptURL) }
        recordings[taskID] = recording
    }

    func stop(taskID: UUID) {
        guard var recording = recordings.removeValue(forKey: taskID) else { return }
        let trailingText = recording.sanitizer.finish()
        if !trailingText.isEmpty { append(trailingText, to: recording.transcriptURL) }
    }

    private func start(taskID: UUID) {
        let sessionDirectory = rootURL.appendingPathComponent(taskID.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        } catch {
            logError("Terminal transcript directory creation failed: \(error)")
            return
        }
        let transcriptURL = sessionDirectory.appendingPathComponent("terminal.txt")
        FileManager.default.createFile(atPath: transcriptURL.path, contents: nil)
        recordings[taskID] = Recording(transcriptURL: transcriptURL)
    }

    private func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logWarning("Terminal transcript write failed for \(url.lastPathComponent): \(error)")
        }
    }
}
