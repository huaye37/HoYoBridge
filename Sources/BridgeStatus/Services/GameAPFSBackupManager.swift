import Darwin
import Foundation

struct GameBackupSnapshot: Equatable, Sendable {
  let version: String?
  let createdAt: Date
  let gameURL: URL
  let isRestorable: Bool
}

enum GameBackupManagerError: Error {
  case invalidGameDirectory
  case cloningUnavailable
  case commandFailed
  case invalidBackup
  case atomicSwapFailed
}

enum GameAPFSBackupManager {
  private struct Record: Codable {
    let schemaVersion: Int
    let createdAt: Date
  }

  private static let backupDirectoryName = ".MacGameBridge-Backups"
  private static let currentDirectoryName = "current"
  private static let gameDirectoryName = "Game"
  private static let recordName = "backup.json"

  static func loadBackup(for gameURL: URL) -> GameBackupSnapshot? {
    let current = currentBackupURL(for: gameURL)
    let backupGame = current.appending(path: gameDirectoryName, directoryHint: .isDirectory)
    let recordURL = current.appending(path: recordName)
    guard let attributes = try? backupGame.resourceValues(forKeys: [.isDirectoryKey]),
      attributes.isDirectory == true,
      let data = try? Data(contentsOf: recordURL),
      data.count <= 65_536,
      let record = try? JSONDecoder().decode(Record.self, from: data),
      record.schemaVersion == 1
    else {
      return nil
    }
    return GameBackupSnapshot(
      version: configuredVersion(at: backupGame),
      createdAt: record.createdAt,
      gameURL: backupGame,
      isRestorable: GameInstallationRecord.isInstalled(at: backupGame)
    )
  }

  static func createBackup(
    for gameURL: URL,
    now: Date = Date()
  ) throws -> GameBackupSnapshot {
    try Task.checkCancellation()
    let source = gameURL.standardizedFileURL
    let sourceValues = try source.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeSupportsFileCloningKey])
    guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true else {
      throw GameBackupManagerError.invalidGameDirectory
    }
    guard GameInstallationRecord.isInstalled(at: source) else {
      throw GameBackupManagerError.invalidGameDirectory
    }
    guard sourceValues.volumeSupportsFileCloning == true else {
      throw GameBackupManagerError.cloningUnavailable
    }

    let root = backupRootURL(for: source)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let staging = root.appending(
      path: ".preparing-\(UUID().uuidString)", directoryHint: .isDirectory)
    let stagedGame = staging.appending(path: gameDirectoryName, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

    try runClone(source: source, destination: stagedGame)
    try Task.checkCancellation()
    guard GameInstallationRecord.isInstalled(at: stagedGame)
    else {
      throw GameBackupManagerError.invalidBackup
    }
    let record = Record(schemaVersion: 1, createdAt: now)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(record).write(
      to: staging.appending(path: recordName), options: [.atomic])
    try publish(staging: staging, current: currentBackupURL(for: source))
    guard let snapshot = loadBackup(for: source) else {
      throw GameBackupManagerError.invalidBackup
    }
    return snapshot
  }

  static func rollback(gameURL: URL) throws -> GameBackupSnapshot {
    try Task.checkCancellation()
    let target = gameURL.standardizedFileURL
    guard let existing = loadBackup(for: target), existing.isRestorable else {
      throw GameBackupManagerError.invalidBackup
    }
    let targetValues = try target.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeIdentifierKey])
    let backupValues = try existing.gameURL.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeIdentifierKey])
    guard targetValues.isDirectory == true,
      backupValues.isDirectory == true,
      targetValues.isSymbolicLink != true,
      backupValues.isSymbolicLink != true,
      targetValues.volumeIdentifier as? AnyHashable
        == backupValues.volumeIdentifier as? AnyHashable
    else {
      throw GameBackupManagerError.invalidBackup
    }

    let result = target.path.withCString { source in
      existing.gameURL.path.withCString { destination in
        renamex_np(source, destination, UInt32(RENAME_SWAP))
      }
    }
    guard result == 0 else { throw GameBackupManagerError.atomicSwapFailed }
    // The atomic exchange already committed; cancellation cannot undo its outcome.
    guard let snapshot = loadBackup(for: target) else {
      throw GameBackupManagerError.invalidBackup
    }
    return snapshot
  }

  static func removeBackup(for gameURL: URL) throws {
    let current = currentBackupURL(for: gameURL)
    guard FileManager.default.fileExists(atPath: current.path) else { return }
    try FileManager.default.removeItem(at: current)
  }

  private static func runClone(source: URL, destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/cp")
    process.arguments = ["-cR", source.path, destination.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    while process.isRunning {
      if Task.isCancelled {
        process.terminate()
        process.waitUntilExit()
        throw CancellationError()
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    guard process.terminationStatus == 0 else {
      throw GameBackupManagerError.commandFailed
    }
  }

  private static func publish(staging: URL, current: URL) throws {
    if !FileManager.default.fileExists(atPath: current.path) {
      try FileManager.default.moveItem(at: staging, to: current)
      return
    }
    let result = staging.path.withCString { source in
      current.path.withCString { destination in
        renamex_np(source, destination, UInt32(RENAME_SWAP))
      }
    }
    guard result == 0 else { throw GameBackupManagerError.atomicSwapFailed }
    try FileManager.default.removeItem(at: staging)
  }

  private static func backupRootURL(for gameURL: URL) -> URL {
    gameURL.deletingLastPathComponent()
      .appending(path: backupDirectoryName, directoryHint: .isDirectory)
      .appending(path: gameURL.lastPathComponent, directoryHint: .isDirectory)
  }

  private static func currentBackupURL(for gameURL: URL) -> URL {
    backupRootURL(for: gameURL).appending(
      path: currentDirectoryName, directoryHint: .isDirectory)
  }

  private static func configuredVersion(at gameURL: URL) -> String? {
    let marker = gameURL.appending(path: ".mgb-managed-cn-download")
    if let text = try? String(contentsOf: marker, encoding: .utf8),
      let value = text.split(separator: "\n").first(where: { $0.hasPrefix("version=") })
    {
      return String(value.dropFirst("version=".count))
    }
    let config = gameURL.appending(path: "config.ini")
    guard let text = try? String(contentsOf: config, encoding: .utf8),
      let value = text.split(separator: "\n").first(where: { $0.hasPrefix("game_version=") })
    else {
      return nil
    }
    return String(value.dropFirst("game_version=".count))
  }
}
