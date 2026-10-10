import Foundation
import Testing
@testable import OpenZeus

@Test func taskWorktreeUsesTaskUUIDForBranchAndDirectory() {
    let taskID = UUID(uuidString: "A7B6C5D4-E3F2-4A1B-8C9D-0E1F2A3B4C5D")!
    let config = WorktreeConfig(basePath: "/tmp/worktrees")

    #expect(WorktreeService.taskBranchName(for: taskID) == "a7b6c5d4-e3f2-4a1b-8c9d-0e1f2a3b4c5d")
    #expect(
        WorktreeService.taskWorktreePath(taskID: taskID, projectName: "My Project", config: config)
            == "/tmp/worktrees/my-project/A7B6C5D4-E3F2-4A1B-8C9D-0E1F2A3B4C5D"
    )
}
