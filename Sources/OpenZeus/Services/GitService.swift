import Foundation

/// Git statistics for display in the UI.
struct GitStats: Sendable {
    let staged: Int
    let unstaged: Int
    let untracked: Int
    let branch: String
    let hasRemote: Bool
    let ahead: Int
    let behind: Int

    var hasChanges: Bool { staged > 0 || unstaged > 0 || untracked > 0 }
    var totalChanges: Int { staged + unstaged + untracked }
}

/// Service for running git commands in a working directory.
@MainActor
final class GitService: ObservableObject {
    @Published var stats: GitStats?
    @Published var isLoading = false
    @Published var lastError: String?

    private let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - Fetch Status

    func fetchStatus() async {
        isLoading = true
        lastError = nil

        do {
            let stats = try await computeStats()
            self.stats = stats
        } catch {
            lastError = error.localizedDescription
            stats = nil
        }

        isLoading = false
    }

    private func computeStats() async throws -> GitStats {
        // Check if this is a git repo
        let checkResult = await runGit(args: ["rev-parse", "--is-inside-work-tree"])
        guard checkResult.success else {
            throw GitError.notARepo
        }

        // Get porcelain status
        let statusOutput = await runGit(args: ["status", "--porcelain=v1"])
        guard statusOutput.success else {
            throw GitError.commandFailed(statusOutput.output)
        }

        var staged = 0
        var unstaged = 0
        var untracked = 0

        for line in statusOutput.output.split(separator: "\n") {
            guard line.count >= 2 else { continue }
            let indexChar = line[line.startIndex]
            let worktreeChar = line[line.index(after: line.startIndex)]

            // Index status (staged)
            if indexChar != " " && indexChar != "?" {
                staged += 1
            }

            // Worktree status (unstaged)
            if worktreeChar != " " && worktreeChar != "?" {
                unstaged += 1
            }

            // Untracked
            if indexChar == "?" && worktreeChar == "?" {
                untracked += 1
            }
        }

        // Get current branch
        let branchOutput = await runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"])
        let branch = branchOutput.success ? branchOutput.output.trimmingCharacters(in: .whitespacesAndNewlines) : "unknown"

        // Check for remote
        let remoteOutput = await runGit(args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        let hasRemote = remoteOutput.success

        // Get ahead/behind counts
        var ahead = 0
        var behind = 0
        if hasRemote {
            let trackingOutput = await runGit(args: ["rev-list", "--left-right", "--count", "HEAD...@{u}"])
            if trackingOutput.success {
                let parts = trackingOutput.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\t")
                    .map(String.init)
                if parts.count == 2 {
                    ahead = Int(parts[0]) ?? 0
                    behind = Int(parts[1]) ?? 0
                }
            }
        }

        return GitStats(
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
            branch: branch,
            hasRemote: hasRemote,
            ahead: ahead,
            behind: behind
        )
    }

    // MARK: - Git Actions

    /// Stage all changes (git add .)
    func stageAll() async -> GitCommandResult {
        let result = await runGit(args: ["add", "."])
        await fetchStatus()
        return result
    }

    /// Unstage all changes (git reset HEAD)
    func unstageAll() async -> GitCommandResult {
        let result = await runGit(args: ["reset", "HEAD"])
        await fetchStatus()
        return result
    }

    /// Discard all unstaged changes (git checkout -- .)
    func discardUnstagedChanges() async -> GitCommandResult {
        let result = await runGit(args: ["checkout", "--", "."])
        await fetchStatus()
        return result
    }

    /// Remove untracked files (git clean -fd)
    func removeUntrackedFiles() async -> GitCommandResult {
        let result = await runGit(args: ["clean", "-fd"])
        await fetchStatus()
        return result
    }

    /// Revert all changes (unstage + discard + remove untracked)
    func revertAllChanges() async -> GitCommandResult {
        // Reset staging area
        _ = await runGit(args: ["reset", "HEAD"])
        // Discard worktree changes
        _ = await runGit(args: ["checkout", "--", "."])
        // Remove untracked files
        let result = await runGit(args: ["clean", "-fd"])
        await fetchStatus()
        return result
    }

    /// Commit staged changes
    func commit(message: String) async -> GitCommandResult {
        let result = await runGit(args: ["commit", "-m", message])
        await fetchStatus()
        return result
    }

    /// Stage all and commit
    func stageAndCommit(message: String) async -> GitCommandResult {
        _ = await runGit(args: ["add", "."])
        let result = await runGit(args: ["commit", "-m", message])
        await fetchStatus()
        return result
    }

    /// Push to remote
    func push() async -> GitCommandResult {
        let result = await runGit(args: ["push"])
        await fetchStatus()
        return result
    }

    /// Stage all, commit, and push
    func stageCommitAndPush(message: String) async -> GitCommandResult {
        _ = await runGit(args: ["add", "."])
        let commitResult = await runGit(args: ["commit", "-m", message])
        guard commitResult.success else {
            await fetchStatus()
            return commitResult
        }
        let pushResult = await runGit(args: ["push"])
        await fetchStatus()
        return pushResult
    }

    // MARK: - Private Helpers

    private func runGit(args: [String]) async -> GitCommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""

                continuation.resume(returning: GitCommandResult(
                    success: process.terminationStatus == 0,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                    error: error.trimmingCharacters(in: .whitespacesAndNewlines),
                    exitCode: Int(process.terminationStatus)
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: GitCommandResult(
                    success: false,
                    output: "",
                    error: error.localizedDescription,
                    exitCode: -1
                ))
            }
        }
    }
}

// MARK: - Types

struct GitCommandResult: Sendable {
    let success: Bool
    let output: String
    let error: String
    let exitCode: Int
}

enum GitError: LocalizedError {
    case notARepo
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepo:
            return "Not a git repository"
        case .commandFailed(let details):
            return "Git command failed: \(details)"
        }
    }
}
