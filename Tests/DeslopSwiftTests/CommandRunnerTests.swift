import Testing
@testable import DeslopSwift

@Suite("commands")
struct CommandRunnerTests {
    @Test("a command that fails says why, whether it prints the reason to its error or its output")
    func failureSaysWhy() throws {
        for script in ["echo reason >&2; exit 3", "echo reason; exit 3"] {
            #expect {
                try CommandRunner().run(["sh", "-c", script])
            } throws: { error in
                guard case FrontendError.commandFailed(_, 3, let output) = error else { return false }
                return output.contains("reason")
            }
        }
    }

    @Test("what a command prints is handed back when it succeeds")
    func success() throws {
        let printed = try CommandRunner().run(["sh", "-c", "echo out; echo noise >&2"])
        #expect(String(decoding: printed, as: UTF8.self) == "out\n")
    }
}
