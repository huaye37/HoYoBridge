import Foundation

public struct CommandResult: Equatable, Sendable {
  public let exitCode: Int32
  public let standardOutput: String
  public let standardError: String

  public init(exitCode: Int32, standardOutput: String, standardError: String) {
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

public protocol CommandRunning: Sendable {
  func run(_ executable: String, arguments: [String]) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
  public init() {}

  public func run(_ executable: String, arguments: [String]) throws -> CommandResult {
    let process = Process()
    // Drain both streams concurrently: waiting first deadlocks once either pipe fills.
    let output = Pipe()
    let error = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error

    try process.run()
    let streams = CommandOutputCapture()
    let readers = DispatchGroup()
    readers.enter()
    DispatchQueue.global().async {
      streams.setOutput(output.fileHandleForReading.readDataToEndOfFile())
      readers.leave()
    }
    readers.enter()
    DispatchQueue.global().async {
      streams.setError(error.fileHandleForReading.readDataToEndOfFile())
      readers.leave()
    }
    process.waitUntilExit()
    readers.wait()
    let (outputData, errorData) = streams.result()

    return CommandResult(
      exitCode: process.terminationStatus,
      standardOutput: String(decoding: outputData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines),
      standardError: String(decoding: errorData, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
    )
  }
}

private final class CommandOutputCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var output = Data()
  private var error = Data()
  func setOutput(_ value: Data) { lock.withLock { output = value } }
  func setError(_ value: Data) { lock.withLock { error = value } }
  func result() -> (Data, Data) { lock.withLock { (output, error) } }
}
