import Foundation

struct GamePerformanceSample: Equatable, Sendable {
  let memoryBytes: UInt64
  let cpuPercent: Double
  let processCount: Int
}

struct GamePerformanceSnapshot: Equatable, Sendable {
  let memoryBytes: UInt64
  let peakMemoryBytes: UInt64
  let cpuPercent: Double
  let processCount: Int

  var memoryText: String {
    Self.format(bytes: memoryBytes)
  }

  var peakMemoryText: String {
    Self.format(bytes: peakMemoryBytes)
  }

  private static func format(bytes: UInt64) -> String {
    String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
  }
}

enum GamePerformanceSampler {
  static func sample(paths: GameRuntimePaths) throws -> GamePerformanceSample {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,ppid=,rss=,%cpu=,command="]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "C"
    process.environment = environment
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
      return GamePerformanceSample(memoryBytes: 0, cpuPercent: 0, processCount: 0)
    }
    return parse(
      text,
      matching: [
        paths.runtimeRoot.path,
        paths.prefix.path,
        paths.gameExecutable.lastPathComponent,
        "ZFGameBrowser.exe",
      ]
    )
  }

  static func parse(_ output: String, matching tokens: [String]) -> GamePerformanceSample {
    var memoryKiB: UInt64 = 0
    var cpuPercent = 0.0
    var processCount = 0

    for line in output.split(separator: "\n") {
      let fields = line.split(
        maxSplits: 4,
        omittingEmptySubsequences: true,
        whereSeparator: { $0 == " " || $0 == "\t" }
      )
      guard fields.count == 5,
        let rss = UInt64(fields[2]),
        let cpu = Double(fields[3])
      else { continue }
      let command = String(fields[4])
      guard !command.contains("/bin/ps"), tokens.contains(where: command.contains) else { continue }
      let (nextMemory, overflow) = memoryKiB.addingReportingOverflow(rss)
      memoryKiB = overflow ? UInt64.max : nextMemory
      cpuPercent += cpu
      processCount += 1
    }

    let (memoryBytes, overflow) = memoryKiB.multipliedReportingOverflow(by: 1_024)
    return GamePerformanceSample(
      memoryBytes: overflow ? UInt64.max : memoryBytes,
      cpuPercent: cpuPercent,
      processCount: processCount
    )
  }
}
