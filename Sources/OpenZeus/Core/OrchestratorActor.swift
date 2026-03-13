import Foundation

@globalActor
actor OrchestratorActor {
    static let shared = OrchestratorActor()

    private var runningProcesses: [UUID: Process] = [:]

    func launch(task: AgentTask) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: task.command)
        process.currentDirectoryURL = task.workingDirectory

        let env = ProcessInfo.processInfo.environment.merging(task.environment) { _, new in new }
        process.environment = env

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        runningProcesses[task.id] = process
    }

    func terminate(taskID: UUID) {
        guard let process = runningProcesses[taskID] else { return }
        process.terminate()
        runningProcesses.removeValue(forKey: taskID)
    }

    func isRunning(taskID: UUID) -> Bool {
        runningProcesses[taskID]?.isRunning ?? false
    }

    func stopAll() {
        for (_, process) in runningProcesses {
            process.terminate()
        }
        runningProcesses.removeAll()
    }
}
