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

struct WorktreeBranchOption: Identifiable, Sendable {
    enum Kind: Sendable { case local, remote }
    let id: String
    let name: String
    let kind: Kind
    let localName: String
    let presentLocally: Bool
    let checkedOutElsewhere: Bool
    var isAvailable: Bool {
        switch kind {
        case .local: return !checkedOutElsewhere
        case .remote: return !presentLocally || !checkedOutElsewhere
        }
    }
}

enum WorktreeError: LocalizedError {
    case notConfigured
    case defaultBranchUnavailable(String)
    case gitCommandFailed(String)
    case directoryCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Worktree base path is not configured. Set it in Settings > Worktree."
        case .defaultBranchUnavailable(let details):
            return "Could not determine the repository default branch: \(details)"
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
    /// Check out a remote-tracking branch. Creates a local tracking branch when absent.
    case remoteBranch(ref: String, localName: String, presentLocally: Bool)
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
            let baseBranch = try await defaultBranch(repoPath: request.repoPath)
            gitArgs = ["worktree", "add", worktreePath, "-b", branch, baseBranch]

        case .existingBranch(let branchName):
            guard !branchName.isEmpty else {
                throw WorktreeError.gitCommandFailed("No existing branch selected.")
            }
            branch = branchName
            gitArgs = ["worktree", "add", worktreePath, branch]

        case .remoteBranch(let ref, let localName, let presentLocally):
            branch = localName
            gitArgs = presentLocally
                ? ["worktree", "add", worktreePath, localName]
                : ["worktree", "add", worktreePath, "-b", localName, ref]
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

    /// Lists local and remote-tracking branches that can be used for a new worktree.
    func listBranchOptions(repoPath: String) async throws -> [WorktreeBranchOption] {
        async let localResult = runGit(
            args: ["for-each-ref", "--sort=-committerdate", "refs/heads/", "--format=%(refname:short)"],
            in: repoPath
        )
        async let remoteResult = runGit(
            args: ["for-each-ref", "--sort=-committerdate", "refs/remotes/", "--format=%(refname:short)"],
            in: repoPath
        )
        async let worktreesResult = runGit(args: ["worktree", "list", "--porcelain"], in: repoPath)
        let (local, remote, worktrees) = await (localResult, remoteResult, worktreesResult)

        guard local.success else {
            let detail = local.error.isEmpty ? local.output : local.error
            throw WorktreeError.gitCommandFailed(detail)
        }
        guard remote.success else {
            let detail = remote.error.isEmpty ? remote.output : remote.error
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

        let localBranches = local.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let localBranchSet: Set<String> = Set(localBranches)

        let localOptions: [WorktreeBranchOption] = localBranches.map { name in
            WorktreeBranchOption(
                id: "local:\(name)",
                name: name,
                kind: .local,
                localName: name,
                presentLocally: true,
                checkedOutElsewhere: checkedOutBranches.contains(name)
            )
        }

        let remoteBranches = remote.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("/") && !$0.hasSuffix("/HEAD") }

        let remoteOptions: [WorktreeBranchOption] = remoteBranches.map { name in
            let localName = name.remoteBranchLocalName
            let presentLocally = localBranchSet.contains(localName)
            return WorktreeBranchOption(
                id: "remote:\(name)",
                name: name,
                kind: .remote,
                localName: localName,
                presentLocally: presentLocally,
                checkedOutElsewhere: presentLocally && checkedOutBranches.contains(localName)
            )
        }

        return remoteOptions + localOptions.filter(\.isAvailable)
    }

    /// Fetches remote-tracking refs from the default remote via `git fetch --prune`.
    func fetchRemotes(repoPath: String) async throws {
        let result = await runGit(args: ["fetch", "--prune"], in: repoPath)
        guard result.success else {
            let detail = result.error.isEmpty ? result.output : result.error
            throw WorktreeError.gitCommandFailed(detail)
        }
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

    static func defaultBranch(from output: String) -> String? {
        let prefix = "ref: refs/heads/"
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let branch = line.dropFirst(prefix.count).split(whereSeparator: \Character.isWhitespace).first
        return branch.map(String.init)
    }

    private func defaultBranch(repoPath: String) async throws -> String {
        let result = await runGit(args: ["ls-remote", "--symref", "origin", "HEAD"], in: repoPath)
        guard result.success else {
            let details = result.error.isEmpty ? result.output : result.error
            throw WorktreeError.defaultBranchUnavailable(details)
        }
        guard let branch = Self.defaultBranch(from: result.output), !branch.isEmpty else {
            throw WorktreeError.defaultBranchUnavailable("origin did not report one.")
        }
        return branch
    }

    private func runGit(args: [String], in workingDirectory: String) async -> GitCommandResult {
        await runGitCommand(args: args, in: workingDirectory, executablePath: gitExecutablePath)
    }
}

private extension String {
    var remoteBranchLocalName: String {
        guard let slashIndex = firstIndex(of: "/") else { return self }
        return String(self[index(after: slashIndex)...])
    }
}
