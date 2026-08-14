import Foundation

/// Converts terminal output into plain text suitable for a durable transcript.
/// It keeps one editable terminal line so carriage-return redraws do not become padded,
/// duplicated transcript lines.
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
            case .text:
                consumeTextByte(byte, output: &output)
            case .escape:
                consumeEscapeByte(byte)
            case .controlSequence(let parameters):
                consumeControlSequenceByte(byte, parameters: parameters)
            case .string:
                if byte == 0x07 { // BEL
                    escapeState = .text
                } else if byte == 0x1B { // ESC, possibly ST (ESC \\)
                    escapeState = .stringEscape
                }
            case .stringEscape:
                escapeState = byte == 0x5C ? .text : .string
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
        case 0x1B: // ESC
            escapeState = .escape
        case 0x0A: // LF
            output.append(contentsOf: completedCurrentLine().utf8)
            currentLine.removeAll()
            cursor = 0
        case 0x0D: // CR
            cursor = 0
        case 0x08, 0x7F: // Backspace and DEL
            cursor = max(0, cursor - 1)
        case 0x09: // Tab
            write(bytes: [0x20, 0x20, 0x20, 0x20])
        case 0x00...0x1F:
            break
        default:
            write(bytes: [byte])
        }
    }

    private mutating func consumeEscapeByte(_ byte: UInt8) {
        switch byte {
        case 0x5B: // [ — CSI
            escapeState = .controlSequence([])
        case 0x5D, 0x50, 0x5E, 0x5F, 0x6B: // ], P, ^, _, k — terminal strings
            escapeState = .string
        default:
            escapeState = .text
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
        let values = parameterString
            .split(separator: ";")
            .compactMap { Int($0.filter(\.isNumber)) }
        let value = values.first ?? 0

        switch finalByte {
        case 0x4A: // J — erase display
            if value == 0 || value == 2 { currentLine.removeAll() }
            cursor = 0
        case 0x4B: // K — erase line
            if value == 0 {
                currentLine.removeSubrange(min(cursor, currentLine.count)..<currentLine.count)
            } else if value == 2 {
                currentLine.removeAll()
                cursor = 0
            }
        case 0x43: // C — cursor forward
            cursor += value == 0 ? 1 : value
        case 0x44: // D — cursor backward
            cursor = max(0, cursor - (value == 0 ? 1 : value))
        case 0x47: // G — cursor horizontal absolute
            cursor = max(0, (value == 0 ? 1 : value) - 1)
        case 0x48, 0x66: // H and f — cursor position
            if values.count > 1 {
                cursor = max(0, values[1] - 1)
            }
        default:
            break
        }
    }

    private mutating func write(bytes: [UInt8]) {
        for byte in bytes {
            if cursor < currentLine.count {
                currentLine[cursor] = byte
            } else {
                while currentLine.count < cursor {
                    currentLine.append(0x20)
                }
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
    static let sessionOption = "@openzeus_transcript_session_id"
    private static let transcriptFormatVersion = "2"

    private struct PaneKey: Hashable, Sendable {
        let taskID: UUID
        let sessionID: String
        let paneID: String
    }

    private struct PaneState: Sendable {
        let rawURL: URL
        let transcriptURL: URL
        let checkpointURL: URL
        var rawOffset: UInt64
        var sanitizer = TerminalTranscriptSanitizer()
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private var panes: [PaneKey: PaneState] = [:]

    init(rootURL: URL = TerminalTranscriptRecorder.defaultRootURL()) {
        self.rootURL = rootURL
        fileManager = .default
    }

    nonisolated static func defaultRootURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("OpenZeus", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
    }

    func revealDirectory() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func transcriptDirectoryURL() -> URL {
        rootURL
    }

    /// Returns the transcript session directories recorded for a task, most
    /// recently modified first. Each directory holds the `pane-*.txt`
    /// transcripts for one tmux session of that task.
    nonisolated func transcriptDirectories(for taskID: UUID) -> [URL] {
        let taskDirectory = rootURL.appendingPathComponent(taskID.uuidString, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: taskDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else {
            return []
        }
        let directories = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        return directories.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    func reconcile(taskID: UUID, sessionName: String, tmux: String) async {
        guard let sessionID = await recordingSessionID(sessionName: sessionName, tmux: tmux) else {
            return
        }

        let paneOutput = await runProcessOutput(
            tmux,
            args: ["list-panes", "-s", "-t", sessionName, "-F", "#{pane_id}"]
        )
        let paneIDs = Set(
            paneOutput
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !paneIDs.isEmpty else { return }

        for paneID in paneIDs {
            let key = PaneKey(taskID: taskID, sessionID: sessionID, paneID: paneID)
            if panes[key] == nil {
                await startRecording(key: key, tmux: tmux)
            }
            synchronize(key: key)
        }

        let inactiveKeys = panes.keys.filter {
            $0.taskID == taskID && $0.sessionID == sessionID && !paneIDs.contains($0.paneID)
        }
        for key in inactiveKeys {
            synchronize(key: key)
            flushCurrentLine(for: key)
            panes.removeValue(forKey: key)
        }
    }

    func stopRecording(taskID: UUID, tmux: String) async {
        let keys = panes.keys.filter { $0.taskID == taskID }
        for key in keys {
            synchronize(key: key)
            flushCurrentLine(for: key)
            await runProcessOutput(tmux, args: ["pipe-pane", "-t", key.paneID])
            panes.removeValue(forKey: key)
        }
    }

    private func recordingSessionID(sessionName: String, tmux: String) async -> String? {
        let existing = await runProcessOutput(
            tmux,
            args: ["show-options", "-qv", "-t", sessionName, Self.sessionOption]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString
        _ = await runProcessOutput(
            tmux,
            args: ["set-option", "-t", sessionName, Self.sessionOption, newID]
        )
        let verified = await runProcessOutput(
            tmux,
            args: ["show-options", "-qv", "-t", sessionName, Self.sessionOption]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return verified.isEmpty ? nil : verified
    }

    private func startRecording(key: PaneKey, tmux: String) async {
        let paneName = sanitizedPaneName(key.paneID)
        let sessionDirectory = rootURL
            .appendingPathComponent(key.taskID.uuidString, isDirectory: true)
            .appendingPathComponent(key.sessionID, isDirectory: true)
        let rawDirectory = sessionDirectory.appendingPathComponent(".raw", isDirectory: true)
        let checkpointDirectory = sessionDirectory.appendingPathComponent(".checkpoints", isDirectory: true)

        do {
            try fileManager.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: checkpointDirectory, withIntermediateDirectories: true)
        } catch {
            logError("Terminal transcript directory creation failed: \(error)")
            return
        }

        let rawURL = rawDirectory.appendingPathComponent("\(paneName).raw")
        let transcriptURL = sessionDirectory.appendingPathComponent("\(paneName).txt")
        let checkpointURL = checkpointDirectory.appendingPathComponent("\(paneName).offset")
        let formatURL = checkpointDirectory.appendingPathComponent("\(paneName).format")
        let rebuildTranscript = transcriptFormatVersion(at: formatURL) != Self.transcriptFormatVersion
        let rawOffset = rebuildTranscript ? 0 : checkpointOffset(at: checkpointURL)
        if rebuildTranscript {
            try? Data().write(to: transcriptURL)
            try? fileManager.removeItem(at: checkpointURL)
            try? Self.transcriptFormatVersion.write(to: formatURL, atomically: true, encoding: .utf8)
        } else if !fileManager.fileExists(atPath: transcriptURL.path) {
            fileManager.createFile(atPath: transcriptURL.path, contents: nil)
        }
        panes[key] = PaneState(
            rawURL: rawURL,
            transcriptURL: transcriptURL,
            checkpointURL: checkpointURL,
            rawOffset: rawOffset
        )

        // OpenZeus owns pipe-pane for its tmux sessions. Clear a stale writer left by a
        // previous app process before replacing it with this pane's durable raw stream.
        _ = await runProcessOutput(tmux, args: ["pipe-pane", "-t", key.paneID])
        let command = "cat >> \(shellQuoted(rawURL.path))"
        _ = await runProcessOutput(tmux, args: ["pipe-pane", "-t", key.paneID, command])
        logInfo("Terminal transcript recording started for task \(key.taskID.uuidString), pane \(key.paneID)")
    }

    private func synchronize(key: PaneKey) {
        guard var state = panes[key] else { return }
        guard let rawData = appendedData(at: state.rawURL, from: state.rawOffset) else { return }
        guard !rawData.isEmpty else { return }

        let text = state.sanitizer.append(rawData)
        if !text.isEmpty {
            append(text: text, to: state.transcriptURL)
        }
        state.rawOffset += UInt64(rawData.count)
        writeCheckpoint(state.rawOffset, to: state.checkpointURL)
        panes[key] = state
    }

    private func flushCurrentLine(for key: PaneKey) {
        guard var state = panes[key] else { return }
        let trailingText = state.sanitizer.finish()
        if !trailingText.isEmpty {
            append(text: trailingText, to: state.transcriptURL)
        }
        panes[key] = state
    }

    private func appendedData(at url: URL, from offset: UInt64) -> Data? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }
        guard fileSize.uint64Value > offset else { return Data() }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            logWarning("Terminal transcript read failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func append(text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logWarning("Terminal transcript write failed for \(url.lastPathComponent): \(error)")
        }
    }

    private func checkpointOffset(at url: URL) -> UInt64 {
        guard let string = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return UInt64(string.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func transcriptFormatVersion(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeCheckpoint(_ offset: UInt64, to url: URL) {
        try? String(offset).write(to: url, atomically: true, encoding: .utf8)
    }

    private func sanitizedPaneName(_ paneID: String) -> String {
        let allowed = paneID.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return "pane-\(String(allowed))"
    }

    private func shellQuoted(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }
}
