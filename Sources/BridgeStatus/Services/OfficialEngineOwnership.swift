import Foundation

enum OfficialEngineOwnership {
  static func matchesExecutable(_ executable: String?, prefix: String) -> Bool {
    executable == prefix + "/drive_c/MacGameBridge/miHoYo Launcher/1.18.0.380/HYP.exe"
  }
  // Process environments are inspected in memory only, never written to diagnostics.
  static func matches(_ environment: String, prefix: String) -> Bool {
    let pattern = #"(?:^|\s)WINEPREFIX=(.*?)(?=\s[A-Za-z_][A-Za-z0-9_]*=|$)"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: environment, range: NSRange(environment.startIndex..., in: environment)),
      let range = Range(match.range(at: 1), in: environment) else { return false }
    return String(environment[range]).trimmingCharacters(in: .whitespacesAndNewlines) == prefix
  }

  static func ownsListener(port: UInt16, prefix: String) async -> Bool {
    await Task.detached {
      func output(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
          try process.run()
          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()
          guard process.terminationStatus == 0 else { return nil }
          return String(data: data, encoding: .utf8)
        } catch { return nil }
      }
      guard let listeners = output("/usr/sbin/lsof", ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"]) else { return false }
      let pids = Set(listeners.split(whereSeparator: \.isWhitespace))
      guard !pids.isEmpty else { return false }
      return pids.allSatisfy { pid in
        guard Int32(pid) != nil,
          let environment = output("/bin/ps", ["eww", "-p", String(pid), "-o", "command="]) else { return false }
        if matches(environment, prefix: prefix) { return true }
        if environment.range(of: #"(?:^|\s)WINEPREFIX="#, options: .regularExpression) != nil { return false }
        // Wine's Windows process can clear its exported environment after exec.
        // Its executable identity must still be the exact bundled HYP path.
        let executable = output("/bin/ps", ["-p", String(pid), "-o", "comm="])?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        return matchesExecutable(executable, prefix: prefix)
      }
    }.value
  }
}
