import Foundation

// MARK: - Types

struct WorktreeResult: Sendable {
    let path: String
    let branch: String
}

enum WorktreeError: LocalizedError {
    case notConfigured
    case gitCommandFailed(String)
    case directoryCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Worktree base path is not configured. Set it in Settings > Worktree."
        case .gitCommandFailed(let details):
            return "Git command failed: \(details)"
        case .directoryCreationFailed(let path):
            return "Failed to create directory at: \(path)"
        }
    }
}

// MARK: - Service

final class WorktreeService: Sendable {
    let gitExecutablePath: String

    init(gitExecutablePath: String = "/usr/bin/git") {
        self.gitExecutablePath = gitExecutablePath
    }

    // MARK: - Public API

    /// Creates a git worktree for a task and returns its path and branch name.
    func createWorktree(
        taskID: UUID,
        taskName: String,
        repoPath: String,
        projectSlug: String,
        config: WorktreeConfig,
        branchNameOverride: String = ""
    ) async throws -> WorktreeResult {
        let basePath = config.resolvedBasePath
        guard !basePath.isEmpty else { throw WorktreeError.notConfigured }

        let branch = branchNameOverride.isEmpty
            ? Self.branchName(for: taskID, taskName: taskName)
            : branchNameOverride
        let parentDir = "\(basePath)/\(projectSlug)"
        let worktreePath = "\(parentDir)/\(taskID.uuidString)"

        do {
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw WorktreeError.directoryCreationFailed(parentDir)
        }

        let result = await runGit(
            args: ["worktree", "add", worktreePath, "-b", branch, config.defaultBaseBranch],
            in: repoPath
        )
        guard result.success else {
            let detail = result.error.isEmpty ? result.output : result.error
            throw WorktreeError.gitCommandFailed(detail)
        }

        return WorktreeResult(path: worktreePath, branch: branch)
    }

    /// Removes a worktree directory and deletes the associated branch.
    func removeWorktree(worktreePath: String, repoPath: String, branchName: String) async {
        _ = await runGit(args: ["worktree", "remove", "--force", worktreePath], in: repoPath)
        async let branchDel = runGit(args: ["branch", "-d", branchName], in: repoPath)
        async let prune = runGit(args: ["worktree", "prune"], in: repoPath)
        _ = await (branchDel, prune)
    }

    // MARK: - Naming Helpers

    static func branchName(for taskID: UUID, taskName: String) -> String {
        let shortID = String(taskID.uuidString.prefix(8)).lowercased()
        let slug = toSlug(taskName, maxLength: 30)
        return slug.isEmpty ? "task-\(shortID)" : "task-\(shortID)-\(slug)"
    }

    static func projectSlug(from name: String) -> String {
        let slug = toSlug(name)
        return slug.isEmpty ? "project" : slug
    }

    // MARK: - Private

    private static func toSlug(_ text: String, maxLength: Int? = nil) -> String {
        let joined = text
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return maxLength.map { String(joined.prefix($0)) } ?? joined
    }

    private func runGit(args: [String], in workingDirectory: String) async -> GitCommandResult {
        await runGitCommand(args: args, in: workingDirectory, executablePath: gitExecutablePath)
    }
}
