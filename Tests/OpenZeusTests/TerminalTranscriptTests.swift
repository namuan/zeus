import Foundation
import Testing
@testable import OpenZeus

@Test func terminalTranscriptSanitizerRemovesTerminalControlSequences() {
    var sanitizer = TerminalTranscriptSanitizer()
    let input = Data("hello \u{1B}[31mred\u{1B}[0m\r\n".utf8)

    let transcript = sanitizer.append(input)

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
    let input = Data("ab\u{08}c\u{1B}]0;window title\u{07} done".utf8)

    _ = sanitizer.append(input)

    #expect(sanitizer.finish() == "ac done\n")
}

@Test func terminalTranscriptSanitizerRewritesCarriageReturnAndTerminalTitle() {
    var sanitizer = TerminalTranscriptSanitizer()
    let input = Data("%                         \r \r\u{1B}kold title\u{1B}\\\r\u{1B}[J clean prompt\r\n".utf8)

    let transcript = sanitizer.append(input)

    #expect(transcript == " clean prompt\n")
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

@Test func tmuxTranscriptRecorderCreatesOnePlainTextFilePerPane() async throws {
    guard let tmux = tmuxExecutable() else { return }

    let sessionName = "zeus-transcript-\(UUID().uuidString.prefix(8))"
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("openzeus-transcripts-\(UUID().uuidString)", isDirectory: true)
    let taskID = UUID()
    defer {
        killTranscriptTestTmuxSession(tmux, sessionName: sessionName)
        try? FileManager.default.removeItem(at: directory)
    }

    _ = await runProcessOutput(tmux, args: [
        "new-session", "-d", "-s", sessionName, "/bin/bash",
    ])
    _ = await runProcessOutput(tmux, args: ["split-window", "-h", "-t", sessionName])

    let recorder = TerminalTranscriptRecorder(rootURL: directory)
    await recorder.reconcile(taskID: taskID, sessionName: sessionName, tmux: tmux)
    _ = await runProcessOutput(tmux, args: [
        "send-keys", "-t", sessionName, "printf '\\033[31mtranscript text\\033[0m\\n'", "Enter",
    ])
    try? await Task.sleep(for: .milliseconds(200))
    await recorder.reconcile(taskID: taskID, sessionName: sessionName, tmux: tmux)

    let transcriptFiles = try recursiveFiles(in: directory).filter { $0.pathExtension == "txt" }
    #expect(transcriptFiles.count == 2)
    let transcriptText = try transcriptFiles
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    #expect(transcriptText.contains("transcript text"))
    #expect(!transcriptText.contains("\u{1B}[31m"))

    await recorder.stopRecording(taskID: taskID, tmux: tmux)
}

private func killTranscriptTestTmuxSession(_ tmux: String, sessionName: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tmux)
    process.arguments = ["kill-session", "-t", sessionName]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
}

private func recursiveFiles(in directory: URL) throws -> [URL] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
    )
    return (enumerator?.allObjects as? [URL] ?? []).filter { url in
        (try? url.resourceValues(forKeys: keys).isRegularFile) == true
    }
}
