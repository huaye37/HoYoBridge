import Foundation

enum GPTKEarlyCrashDetector {
  static let startupWindow: TimeInterval = 45

  static func detect(
    paths: GameRuntimePaths,
    runStartedAt: Date,
    now: Date = Date(),
    manager: FileManager = .default
  ) -> Bool {
    let duration = now.timeIntervalSince(runStartedAt)
    guard duration >= 0, duration <= startupWindow else { return false }

    let users = paths.prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)
    guard
      let userDirectories = try? manager.contentsOfDirectory(
        at: users,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return false }

    return userDirectories.contains { userDirectory in
      let logURL = userDirectory.appending(
        path: "AppData/LocalLow/miHoYo/原神/output_log.txt",
        directoryHint: .notDirectory
      )
      guard
        let values = try? logURL.resourceValues(forKeys: [
          .contentModificationDateKey, .fileSizeKey,
        ]),
        let modifiedAt = values.contentModificationDate,
        modifiedAt >= runStartedAt.addingTimeInterval(-1),
        let size = values.fileSize,
        size > 0,
        size <= 1_048_576,
        let log = try? String(contentsOf: logURL, encoding: .utf8)
      else { return false }
      return matches(outputLog: log, runDuration: duration)
    }
  }

  static func matches(outputLog: String, runDuration: TimeInterval) -> Bool {
    guard runDuration >= 0, runDuration <= startupWindow else { return false }
    return outputLog.contains("GfxDevice: creating device client;")
      && outputLog.contains("Direct3D:")
      && outputLog.contains("Renderer: AMD Compatibility Mode")
      && outputLog.contains("**** Crash! ****")
  }
}
