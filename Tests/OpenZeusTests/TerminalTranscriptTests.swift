import Foundation
import Testing
@testable import OpenZeus

@Test func terminalTranscriptSanitizerRemovesTerminalControlSequences() {
    var sanitizer = TerminalTranscriptSanitizer()
    let transcript = sanitizer.append(Data("hello \u{1B}[31mred\u{1B}[0m\r\n".utf8))
    #expect(transcript == "hello red\n")
}

@Test func terminalTranscriptSanitizerTracksSplitEscapeSequences() {
    var sanitizer = TerminalTranscriptSanitizer()
    let first = sanitizer.append(Data("before \u{1B}[3".utf8))
    let second = sanitizer.append(Data("2mafter\u{1B}[0m".utf8))
    #expect(first.isEmpty)
    #expect(second.isEmpty)
    #expect(sanitizer.finish() == "before after\n")
}

@Test func terminalTranscriptSanitizerRemovesOperatingSystemCommandsAndBackspaces() {
    var sanitizer = TerminalTranscriptSanitizer()
    _ = sanitizer.append(Data("ab\u{08}c\u{1B}]0;window title\u{07} done".utf8))
    #expect(sanitizer.finish() == "ac done\n")
}

@Test func terminalTranscriptSanitizerRewritesCarriageReturnAndTerminalTitle() {
    var sanitizer = TerminalTranscriptSanitizer()
    let input = Data("%                         \r \r\u{1B}kold title\u{1B}\\\r\u{1B}[J clean prompt\r\n".utf8)
    #expect(sanitizer.append(input) == " clean prompt\n")
}

@Test func terminalTranscriptRecorderCreatesRequestedDirectory() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("openzeus-transcripts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = TerminalTranscriptRecorder(rootURL: directory)
    await recorder.revealDirectory()
    let resolvedDirectory = await recorder.transcriptDirectoryURL()
    var isDirectory: ObjCBool = false
    #expect(resolvedDirectory == directory)
    #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}

@Test func directTerminalTranscriptRecorderSanitizesAndStoresOutput() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("openzeus-transcripts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let taskID = UUID()
    let recorder = TerminalTranscriptRecorder(rootURL: directory)
    await recorder.append(Data("\u{1B}[31mtranscript text\u{1B}[0m\n".utf8), taskID: taskID)
    await recorder.stop(taskID: taskID)
    let transcriptFiles = try recursiveFiles(in: directory).filter { $0.lastPathComponent == "terminal.txt" }
    #expect(transcriptFiles.count == 1)
    #expect(try String(contentsOf: transcriptFiles[0], encoding: .utf8) == "transcript text\n")
}

@Test func terminalTranscriptRecorderListsTaskSessionDirectoriesMostRecentFirst() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("openzeus-transcripts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let taskID = UUID()
    let taskDirectory = root.appendingPathComponent(taskID.uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
    let older = taskDirectory.appendingPathComponent("session-older", isDirectory: true)
    let newer = taskDirectory.appendingPathComponent("session-newer", isDirectory: true)
    try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: taskDirectory.appendingPathComponent("stray.txt").path, contents: nil)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: older.path)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_600)], ofItemAtPath: newer.path)
    let recorder = TerminalTranscriptRecorder(rootURL: root)
    #expect(recorder.transcriptDirectories(for: taskID).map(\.lastPathComponent) == ["session-newer", "session-older"])
    #expect(recorder.transcriptDirectories(for: UUID()).isEmpty)
}

private func recursiveFiles(in directory: URL) throws -> [URL] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
    return (enumerator?.allObjects as? [URL] ?? []).filter {
        (try? $0.resourceValues(forKeys: keys).isRegularFile) == true
    }
}
