import Foundation

enum CommandLineTool {
    struct Failure: LocalizedError {
        let status: Int32

        var errorDescription: String? {
            String(localized: "The command failed (exit status \(status))")
        }
    }

    /// Runs a tool with no shell and returns its stdout. Throws on a non-zero exit or a
    /// timeout, and terminates the process when it times out or the task is cancelled.
    static func run(_ executable: URL, _ arguments: [String], timeout: Duration = .seconds(60)) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()
            // Cancelled between the check and the launch: the handler saw no running process.
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            let timer = Task {
                try await Task.sleep(for: timeout)
                if process.isRunning { process.terminate() }
            }
            defer { timer.cancel() }
            // Drain stdout off the cooperative pool so a full pipe never stalls the tool.
            let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure(status: process.terminationStatus) }
            return data
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
