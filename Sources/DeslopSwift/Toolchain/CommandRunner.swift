import Foundation

/// Runs a command to its end and hands back what it printed.
struct CommandRunner: Sendable {
    struct Output: Sendable {
        let status: Int32
        let standardOutput: Data
        let standardError: String
    }

    /// Runs `arguments` through `/usr/bin/env`, in `directory`. A command that
    /// cannot start, or exits other than 0, is a failure, which carries what
    /// it printed to both its output and its error: some tools print why they
    /// failed to their output when it is not a terminal, as swiftly does.
    func run(_ arguments: [String], in directory: URL? = nil, environment: [String: String]? = nil) throws(FrontendError) -> Data {
        let output = try runAllowingFailure(arguments, in: directory, environment: environment)
        guard output.status == 0 else {
            let printed = String(decoding: output.standardOutput, as: UTF8.self) + output.standardError
            throw .commandFailed(command: arguments.joined(separator: " "), status: output.status, output: printed)
        }
        return output.standardOutput
    }

    /// Runs `arguments` and hands back its status and output whatever the status.
    /// What it prints goes to files of a scratch directory rather than pipes,
    /// so a command that prints more than a pipe holds never blocks; the
    /// directory is removed once the output is read. A failure on the way
    /// leaves it in the system's temporary directory, and is reported.
    /// `environment`, when given, replaces the process's own.
    func runAllowingFailure(
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil
    ) throws(FrontendError) -> Output {
        let command = arguments.joined(separator: " ")
        func failure(_ error: any Error) -> FrontendError {
            .commandFailed(command: command, status: -1, output: String(describing: error))
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("deslop-\(UUID().uuidString)", isDirectory: true)
        let outputFile = scratch.appendingPathComponent("stdout")
        let errorFile = scratch.appendingPathComponent("stderr")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        if let environment { process.environment = environment }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: outputFile.path, contents: nil)
            FileManager.default.createFile(atPath: errorFile.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: outputFile)
            let errorHandle = try FileHandle(forWritingTo: errorFile)
            process.standardOutput = outputHandle
            process.standardError = errorHandle
            try process.run()
            process.waitUntilExit()
            try outputHandle.close()
            try errorHandle.close()
            let standardOutput = try Data(contentsOf: outputFile)
            let standardError = try String(contentsOf: errorFile, encoding: .utf8)
            try FileManager.default.removeItem(at: scratch)
            return Output(status: process.terminationStatus, standardOutput: standardOutput, standardError: standardError)
        } catch {
            throw failure(error)
        }
    }
}
