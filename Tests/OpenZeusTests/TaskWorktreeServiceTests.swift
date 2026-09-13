import Foundation
import Testing
@testable import OpenZeus

private enum TaskWorktreeServiceTestError: Error {
    case commandFailed(String)
}

private func runGitForTaskWorktreeTest(_ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw TaskWorktreeServiceTestError.commandFailed(errorText)
    }
    return outputText
}

private func taskWorktreeTestRepository() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let origin = directory.appendingPathComponent("origin.git", isDirectory: true)
    let repository = directory.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    _ = try runGitForTaskWorktreeTest(["init", "--bare", origin.path])
    _ = try runGitForTaskWorktreeTest(["init", "-b", "main", repository.path])
    _ = try runGitForTaskWorktreeTest(["-C", repository.path, "config", "user.email", "test@example.com"])
    _ = try runGitForTaskWorktreeTest(["-C", repository.path, "config", "user.name", "Test User"])
    try Data("initial".utf8).write(to: repository.appendingPathComponent("README.md"))
    _ = try runGitForTaskWorktreeTest(["-C", repository.path, "add", "README.md"])
    _ = try runGitForTaskWorktreeTest(["-C", repository.path, "commit", "-m", "Initial commit"])
    _ = try runGitForTaskWorktreeTest(["-C", repository.path, "remote", "add", "origin", origin.path])
    _ = try runGitForTaskWorktreeTest(["-C", repository.path, "push", "-u", "origin", "main"])
    _ = try runGitForTaskWorktreeTest(["--git-dir", origin.path, "symbolic-ref", "HEAD", "refs/heads/main"])
    return repository
}

@Test func taskWorktreeUsesTaskUUIDForBranchAndDirectory() {
    let taskID = UUID(uuidString: "A7B6C5D4-E3F2-4A1B-8C9D-0E1F2A3B4C5D")!
    let config = WorktreeConfig(basePath: "/tmp/worktrees")

    #expect(WorktreeService.taskBranchName(for: taskID) == "a7b6c5d4-e3f2-4a1b-8c9d-0e1f2a3b4c5d")
    #expect(
        WorktreeService.taskWorktreePath(taskID: taskID, projectName: "My Project", config: config)
            == "/tmp/worktrees/my-project/A7B6C5D4-E3F2-4A1B-8C9D-0E1F2A3B4C5D"
    )
}

@Test func repositoryDiscoveryIdentifiesMainAndLinkedWorktrees() async throws {
    let repository = try taskWorktreeTestRepository()
    defer { try? FileManager.default.removeItem(at: repository.deletingLastPathComponent()) }
    let service = WorktreeService()
    let taskID = UUID()
    let config = WorktreeConfig(basePath: repository.deletingLastPathComponent().appendingPathComponent("worktrees").path)

    let mainRepository = try await service.repository(at: repository.path)
    #expect(WorktreeService.pathsReferToSameLocation(mainRepository.rootPath, repository.path))
    #expect(!mainRepository.isLinkedWorktree)

    let result = try await service.createTaskWorktree(
        taskID: taskID,
        projectName: "Project",
        repoPath: mainRepository.rootPath,
        config: config
    )
    let linkedRepository = try await service.repository(at: result.path)
    #expect(WorktreeService.pathsReferToSameLocation(linkedRepository.rootPath, result.path))
    #expect(linkedRepository.isLinkedWorktree)

    let existing = await service.existingTaskWorktree(
        taskID: taskID,
        projectName: "Project",
        repoPath: mainRepository.rootPath,
        config: config
    )
    #expect(existing?.path == result.path)
    #expect(existing?.branch == result.branch)
}

@Test func taskWorktreeCleanupRemovesOnlyExpectedTaskWorktree() async throws {
    let repository = try taskWorktreeTestRepository()
    defer { try? FileManager.default.removeItem(at: repository.deletingLastPathComponent()) }
    let service = WorktreeService()
    let taskID = UUID()
    let config = WorktreeConfig(basePath: repository.deletingLastPathComponent().appendingPathComponent("worktrees").path)

    let result = try await service.createTaskWorktree(
        taskID: taskID,
        projectName: "Project",
        repoPath: repository.path,
        config: config
    )
    #expect(FileManager.default.fileExists(atPath: result.path))

    await service.removeTaskWorktree(
        taskID: taskID,
        projectName: "Project",
        repoPath: repository.path,
        config: config
    )

    #expect(!FileManager.default.fileExists(atPath: result.path))
    let branches = try runGitForTaskWorktreeTest(["-C", repository.path, "branch", "--list", result.branch])
    #expect(branches.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}
