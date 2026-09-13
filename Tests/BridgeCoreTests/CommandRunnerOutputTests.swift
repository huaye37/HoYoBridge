import Testing
@testable import BridgeCore

struct CommandRunnerOutputTests {
  @Test(.timeLimit(.minutes(1))) func drainsBothFullPipes() throws {
    let result = try ProcessCommandRunner().run("/bin/sh", arguments: ["-c",
      "i=0; while [ $i -lt 6000 ]; do printf 'abcdefghijklmnopabcdefghijklmnop\\n'; printf 'ABCDEFGHIJKLMNOPABCDEFGHIJKLMNOP\\n' >&2; i=$((i+1)); done"])
    #expect(result.exitCode == 0)
    #expect(result.standardOutput.split(separator: "\n").count == 6000)
    #expect(result.standardError.split(separator: "\n").count == 6000)
  }
}
