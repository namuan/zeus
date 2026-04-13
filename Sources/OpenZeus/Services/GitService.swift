import Foundation

/// A single file entry from `git status --porcelain=v1`.
struct GitFileChange: Sendable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    let indexStatus: Character    // column 1: staged
    let worktreeStatus: Character // column 2: unstaged

    var isStaged: Bool { indexStatus != " " && indexStatus != "?" }
    var isUnstaged: Bool { worktreeStatus != " " && worktreeStatus != "?" }
    var isUntracked: Bool { indexStatus == "?" && worktreeStatus == "?" }

    var stagedLabel: String { Self.label(for: indexStatus) }
    var unstagedLabel: String { Self.label(for: worktreeStatus) }

    private static func label(for char: Character) -> String {
        switch char {
        case "M": return "modified"
        case "A": return "added"
        case "D": return "deleted"
        case "R": return "renamed"
        case "C": return "copied"
        case "U": return "unmerged"
        default:  return "changed"
        }
    }
}

/// Git statistics for display in the UI.
struct GitStats: Sendable, Equatable {
    let staged: Int
    let unstaged: Int
    let untracked: Int
    let branch: String
    let hasRemote: Bool
    let ahead: Int
    let behind: Int

    var hasChanges: Bool { staged > 0 || unstaged > 0 || untracked > 0 }
    var totalChanges: Int { staged + unstaged + untracked }
    var aheadLabel: String { "\(ahead) commits ahead of \(hasRemote ? "remote" : "default branch")" }
}

private struct StatsSnapshot {
    let stats: GitStats
    let changedFiles: [GitFileChange]
    let unpushedFiles: [GitFileChange]
}

/// Service for running git commands in a working directory.
@MainActor
final class GitService: ObservableObject {
    @Published var stats: GitStats?
    @Published var changedFiles: [GitFileChange] = []
    @Published var unpushedFiles: [GitFileChange] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let workingDirectory: String
    private let gitExecutablePath: String
    private var cachedDefaultBranch: String?
    /// Lazily-resolved repo toplevel — the directory `git status --porcelain` uses
    /// as its path root. Required so that `git diff -- <path>` resolves paths correctly
    /// when `workingDirectory` is a subdirectory of the actual repo root.
    private var cachedRepoTopLevel: String?
    /// Cached upstream ref (e.g. `@{u}` or `origin/main`) used by `fetchDiff(unpushed:)`.
    private var cachedUpstreamRef: String?

    // MARK: - Auto-refresh state
    private var watchedSources: [DispatchSourceFileSystemObject] = []
    private var debounceTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    private let debounceDelay: Duration
    private let remotePollInterval: Duration

    init(
        workingDirectory: String,
        gitExecutablePath: String = "/usr/bin/git",
        statusDebounceMs: Int = 300,
        statusPollIntervalSeconds: Int = 30
    ) {
        self.workingDirectory = workingDirectory
        self.gitExecutablePath = gitExecutablePath
        self.debounceDelay = .milliseconds(statusDebounceMs)
        self.remotePollInterval = .seconds(statusPollIntervalSeconds)
    }

    // MARK: - Watching

    /// Start watching `.git` index/HEAD/FETCH_HEAD for local changes and
    /// polling every 30 s for remote-tracking updates.
    func startWatching() {
        guard watchedSources.isEmpty else { return }

        let gitDir = (workingDirectory as NSString).appendingPathComponent(".git")
        let filesToWatch = [
            (gitDir as NSString).appendingPathComponent("index"),
            (gitDir as NSString).appendingPathComponent("HEAD"),
            (gitDir as NSString).appendingPathComponent("FETCH_HEAD"),
        ]

        for path in filesToWatch {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated { self.scheduleDebounce() }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            watchedSources.append(source)
        }

        startPolling()
    }

    /// Stop all watchers and cancel background tasks.
    func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil
        pollingTask?.cancel()
        pollingTask = nil

        for source in watchedSources { source.cancel() }
        watchedSources.removeAll()
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        let delay = debounceDelay
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // cancelled
            }
            await self?.fetchStatus()
        }
    }

    private func startPolling() {
        let interval = remotePollInterval
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return // cancelled
                }
                await self?.fetchStatus()
            }
        }
    }

    // MARK: - Fetch Status

    func fetchStatus() async {
        isLoading = true
        lastError = nil

        do {
            let snapshot = try await computeStats()
            if self.stats != snapshot.stats { self.stats = snapshot.stats }
            if self.changedFiles != snapshot.changedFiles { self.changedFiles = snapshot.changedFiles }
            if self.unpushedFiles != snapshot.unpushedFiles { self.unpushedFiles = snapshot.unpushedFiles }
        } catch {
            lastError = error.localizedDescription
            stats = nil
            changedFiles = []
            unpushedFiles = []
        }

        isLoading = false
    }

    private func computeStats() async throws -> StatsSnapshot {
        // Check if this is a git repo
        let checkResult = await runGit(args: ["rev-parse", "--is-inside-work-tree"])
        guard checkResult.success else {
            throw GitError.notARepo
        }

        // Status, branch, and remote check are independent — run in parallel.
        async let statusFetch = runGit(args: ["status", "--porcelain=v1"])
        async let branchFetch = runGit(args: ["rev-parse", "--abbrev-ref", "HEAD"])
        async let remoteFetch = runGit(args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        let (statusOutput, branchOutput, remoteOutput) = await (statusFetch, branchFetch, remoteFetch)

        guard statusOutput.success else {
            throw GitError.commandFailed(statusOutput.output)
        }

        var files: [GitFileChange] = []

        for line in statusOutput.output.split(separator: "\n") {
            guard line.count >= 3 else { continue }
            let indexChar = line[line.startIndex]
            let worktreeChar = line[line.index(after: line.startIndex)]
            let pathStart = line.index(line.startIndex, offsetBy: 3)
            let path = String(line[pathStart...])
            files.append(GitFileChange(path: path, indexStatus: indexChar, worktreeStatus: worktreeChar))
        }

        let staged = files.filter { $0.isStaged }.count
        let unstaged = files.filter { $0.isUnstaged }.count
        let untracked = files.filter { $0.isUntracked }.count

        let branch = branchOutput.success ? branchOutput.output.trimmingCharacters(in: .whitespacesAndNewlines) : "unknown"
        let hasRemote = remoteOutput.success

        // Resolve upstream ref and cache it for use by fetchDiff(unpushed:)
        let upstreamRef: String
        if hasRemote {
            upstreamRef = "@{u}"
        } else {
            upstreamRef = await resolveDefaultBranch()
        }
        cachedUpstreamRef = upstreamRef

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
        } else {
            let aheadOutput = await runGit(args: ["rev-list", "--count", "\(upstreamRef)..HEAD"])
            if aheadOutput.success {
                ahead = Int(aheadOutput.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }

        // Fetch the list of files changed in commits that haven't been pushed yet.
        var unpushedFilesList: [GitFileChange] = []
        if ahead > 0 {
            let nameStatus = await runGit(args: ["diff", "--name-status", "\(upstreamRef)..HEAD"])
            if nameStatus.success {
                for line in nameStatus.output.split(separator: "\n") {
                    let parts = line.split(separator: "\t", maxSplits: 1)
                    guard parts.count >= 2, let statusChar = parts[0].first else { continue }
                    let path = String(parts[1])
                    unpushedFilesList.append(GitFileChange(path: path, indexStatus: statusChar, worktreeStatus: " "))
                }
            }
        }

        return StatsSnapshot(
            stats: GitStats(
                staged: staged,
                unstaged: unstaged,
                untracked: untracked,
                branch: branch,
                hasRemote: hasRemote,
                ahead: ahead,
                behind: behind
            ),
            changedFiles: files,
            unpushedFiles: unpushedFilesList
        )
    }

    // MARK: - Git Actions

    /// Unstage a single file (git reset HEAD -- <path>)
    func unstageFile(path: String) async -> GitCommandResult {
        let result = await runGitFromTopLevel(args: ["reset", "HEAD", "--", path])
        await fetchStatus()
        return result
    }

    /// Discard unstaged changes for a single file (git checkout -- <path>)
    func discardFileChanges(path: String) async -> GitCommandResult {
        let result = await runGitFromTopLevel(args: ["checkout", "--", path])
        await fetchStatus()
        return result
    }

    /// Remove a single untracked file (git clean -f -- <path>)
    func removeUntrackedFile(path: String) async -> GitCommandResult {
        let result = await runGitFromTopLevel(args: ["clean", "-f", "--", path])
        await fetchStatus()
        return result
    }

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

    /// Returns the unified diff for a single file.
    /// - `unpushed: true` → `git diff <upstream>..HEAD -- path`
    /// - `staged: true`   → `git diff --cached -- path`
    /// - `untracked: true` → `git diff --no-index /dev/null path` (exit 1 is normal when diff exists)
    /// - otherwise        → `git diff -- path`
    func fetchDiff(path: String, staged: Bool, untracked: Bool, unpushed: Bool = false) async -> String {
        // `git status --porcelain` always emits paths relative to the repo root, regardless
        // of CWD.  `git diff -- <path>` resolves paths relative to CWD.  If the project's
        // working directory is a subdirectory of the repo, those two bases diverge and diff
        // silently returns nothing (exit 0, empty output).  Always run diff from the toplevel.
        let topLevel = await repoTopLevel()
        let args: [String]
        if unpushed {
            let ref = cachedUpstreamRef ?? "@{u}"
            args = ["--no-pager", "diff", "--no-color", "\(ref)..HEAD", "--", path]
        } else if untracked {
            args = ["--no-pager", "diff", "--no-color", "--no-index", "/dev/null", path]
        } else if staged {
            args = ["--no-pager", "diff", "--no-color", "--cached", "--", path]
        } else {
            args = ["--no-pager", "diff", "--no-color", "--", path]
        }
        let result = await runGitCommand(args: args, in: topLevel, executablePath: gitExecutablePath)
        logDebug("fetchDiff: path=\(path) topLevel=\(topLevel) exitCode=\(result.exitCode) output=\(result.output.count)b error='\(result.error)'")
        if result.output.isEmpty && !result.error.isEmpty {
            return "# git error (exit \(result.exitCode)): \(result.error)"
        }
        return result.output
    }

    private func repoTopLevel() async -> String {
        if let cached = cachedRepoTopLevel { return cached }
        let result = await runGit(args: ["rev-parse", "--show-toplevel"])
        let topLevel = result.success
            ? result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            : workingDirectory
        cachedRepoTopLevel = topLevel
        return topLevel
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

    /// Returns the best available default branch reference to compare against
    /// when no upstream is configured. Result is cached since the default branch
    /// doesn't change during a session.
    private func resolveDefaultBranch() async -> String {
        if let cached = cachedDefaultBranch { return cached }
        let symbolic = await runGit(args: ["symbolic-ref", "refs/remotes/origin/HEAD"])
        if symbolic.success {
            let ref = symbolic.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if ref.hasPrefix("refs/remotes/") {
                let branch = String(ref.dropFirst("refs/remotes/".count))
                cachedDefaultBranch = branch
                return branch
            }
        }
        let branch = await findExistingBranch(from: ["origin/main", "origin/master", "main", "master"]) ?? "main"
        cachedDefaultBranch = branch
        return branch
    }

    private func findExistingBranch(from candidates: [String]) async -> String? {
        for candidate in candidates {
            let result = await runGit(args: ["rev-parse", "--verify", candidate])
            if result.success { return candidate }
        }
        return nil
    }

    private func runGit(args: [String]) async -> GitCommandResult {
        await runGitCommand(args: args, in: workingDirectory, executablePath: gitExecutablePath)
    }

    /// Like `runGit`, but runs from the repo toplevel so that porcelain paths resolve correctly
    /// when `workingDirectory` is a subdirectory of the actual repo root.
    private func runGitFromTopLevel(args: [String]) async -> GitCommandResult {
        await runGitCommand(args: args, in: await repoTopLevel(), executablePath: gitExecutablePath)
    }
}

// MARK: - Shared Git Runner

/// Runs a git command and returns the result. Shared by all git-based services.
///
/// Reads stdout and stderr concurrently on background threads *while the process is running*,
/// then waits for exit. This avoids the classic pipe-buffer deadlock where a process blocks
/// trying to write more than ~64 KB to stdout because nothing is reading the pipe yet.
func runGitCommand(args: [String], in workingDirectory: String, executablePath: String) async -> GitCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        outputPipe.fileHandleForReading.closeFile()
        errorPipe.fileHandleForReading.closeFile()
        return GitCommandResult(
            success: false,
            output: "",
            error: error.localizedDescription,
            exitCode: -1
        )
    }

    // Read both pipes concurrently as child tasks so we never block the write side
    // waiting for a reader (which would stall the process indefinitely on > ~64 KB output).
    let outputFH = outputPipe.fileHandleForReading
    let errorFH = errorPipe.fileHandleForReading
    async let outputData: Data = outputFH.readDataToEndOfFile()
    async let errorData: Data = errorFH.readDataToEndOfFile()
    let (out, err) = await (outputData, errorData)
    process.waitUntilExit()

    // Trim only newlines, not spaces — leading spaces are significant
    // in git porcelain output (they form the XY status columns).
    return GitCommandResult(
        success: process.terminationStatus == 0,
        output: (String(data: out, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines),
        error: (String(data: err, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines),
        exitCode: Int(process.terminationStatus)
    )
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
