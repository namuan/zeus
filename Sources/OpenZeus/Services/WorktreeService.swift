import Foundation

// MARK: - Types

struct WorktreeResult: Sendable {
    let path: String
    let branch: String
}

struct WorktreeRequest: Sendable {
    let taskID: UUID
    let taskName: String
    let repoPath: String
    let projectSlug: String
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

// MARK: - Branch Source

enum WorktreeBranchSource: Sendable {
    /// Create a new branch. If name is empty, auto-generate one.
    case newBranch(name: String)
    /// Check out an existing branch into the worktree.
    case existingBranch(String)
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
        request: WorktreeRequest,
        config: WorktreeConfig,
        branchSource: WorktreeBranchSource
    ) async throws -> WorktreeResult {
        let basePath = config.resolvedBasePath
        guard !basePath.isEmpty else { throw WorktreeError.notConfigured }

        let parentDir = "\(basePath)/\(request.projectSlug)"
        let worktreePath = "\(parentDir)/\(request.taskID.uuidString)"

        let branch: String
        let gitArgs: [String]

        switch branchSource {
        case .newBranch(let name):
            branch = name.isEmpty
                ? Self.branchName(for: request.taskID, taskName: request.taskName)
                : name
            gitArgs = ["worktree", "add", worktreePath, "-b", branch, config.defaultBaseBranch]

        case .existingBranch(let branchName):
            guard !branchName.isEmpty else {
                throw WorktreeError.gitCommandFailed("No existing branch selected.")
            }
            branch = branchName
            gitArgs = ["worktree", "add", worktreePath, branch]
        }

        do {
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw WorktreeError.directoryCreationFailed(parentDir)
        }

        let result = await runGit(args: gitArgs, in: request.repoPath)
        guard result.success else {
            let detail = result.error.isEmpty ? result.output : result.error
            throw WorktreeError.gitCommandFailed(detail)
        }

        return WorktreeResult(path: worktreePath, branch: branch)
    }

    /// Lists local branches that are not checked out in another worktree.
    func listAvailableBranches(repoPath: String) async throws -> [String] {
        async let branchesResult = runGit(
            args: ["for-each-ref", "--sort=-committerdate", "refs/heads/", "--format=%(refname:short)"],
            in: repoPath
        )
        async let worktreesResult = runGit(args: ["worktree", "list", "--porcelain"], in: repoPath)
        let (branches, worktrees) = await (branchesResult, worktreesResult)

        guard branches.success else {
            let detail = branches.error.isEmpty ? branches.output : branches.error
            throw WorktreeError.gitCommandFailed(detail)
        }
        guard worktrees.success else {
            let detail = worktrees.error.isEmpty ? worktrees.output : worktrees.error
            throw WorktreeError.gitCommandFailed(detail)
        }

        let branchPrefix = "branch refs/heads/"
        let checkedOutBranches: Set<String> = Set(worktrees.output.split(separator: "\n").compactMap { line in
            guard line.hasPrefix(branchPrefix) else { return nil }
            return String(line.dropFirst(branchPrefix.count))
        })
        return branches.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !checkedOutBranches.contains($0) }
    }

    /// Removes a worktree directory and its branch when the app created that branch.
    func removeWorktree(
        worktreePath: String,
        repoPath: String,
        branchName: String,
        deleteBranch: Bool
    ) async {
        _ = await runGit(args: ["worktree", "remove", "--force", worktreePath], in: repoPath)
        async let prune = runGit(args: ["worktree", "prune"], in: repoPath)
        if deleteBranch {
            async let branchDelete = runGit(args: ["branch", "-d", branchName], in: repoPath)
            _ = await (branchDelete, prune)
        } else {
            _ = await prune
        }
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
