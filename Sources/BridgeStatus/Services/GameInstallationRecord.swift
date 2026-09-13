import Foundation

/// The managed marker is committed only after the downloader finishes verification.
/// Executable/config existence alone must never override an interrupted transaction.
enum GameInstallationRecord {
  static let markerName = ".mgb-managed-cn-download"

  static func state(at game: URL) -> GameInstallationState {
    let executableExists = FileManager.default.fileExists(
      atPath: game.appending(path: "YuanShen.exe").path)
    let marker = game.appending(path: markerName)
    if let attributes = try? marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    {
      guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
        let fields = fields(at: marker), fields["schema"] == "1"
      else { return .recoveryRequired }
      switch fields["state"] {
      case "complete":
        guard executableExists, let version = fields["version"],
          version == configuredVersion(at: game)
        else { return .recoveryRequired }
        return .installed(version: version)
      case "imported":
        return executableExists
          ? .installed(version: configuredVersion(at: game)) : .recoveryRequired
      case "downloading":
        return executableExists || configuredVersion(at: game) != nil
          ? .recoveryRequired : .resumable
      default:
        return .recoveryRequired
      }
    }
    // A dangling marker symlink is also an incomplete/invalid managed installation.
    if (try? FileManager.default.destinationOfSymbolicLink(atPath: marker.path)) != nil {
      return .recoveryRequired
    }
    return executableExists ? .installed(version: configuredVersion(at: game)) : .notInstalled
  }

  static func isInstalled(at game: URL) -> Bool {
    if case .installed = state(at: game) { return true }
    return false
  }

  static func begin(at game: URL) throws {
    try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
    try Data("schema=1\nstate=downloading\n".utf8).write(
      to: game.appending(path: markerName), options: [.atomic])
  }

  static func completedVersion(at game: URL) -> String? {
    guard fields(at: game.appending(path: markerName))?["state"] == "complete",
      case .installed(let version) = state(at: game)
    else { return nil }
    return version
  }

  static func configuredVersion(at game: URL) -> String? {
    guard let text = try? String(contentsOf: game.appending(path: "config.ini"), encoding: .utf8)
    else { return nil }
    let values = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
      let parts = line.split(separator: "=", maxSplits: 1)
      guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "game_version"
      else { return nil }
      return parts[1].trimmingCharacters(in: .whitespaces)
    }
    return values.count == 1 && !values[0].isEmpty ? values[0] : nil
  }

  private static func fields(at url: URL) -> [String: String]? {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size <= 65_536, let text = try? String(contentsOf: url, encoding: .utf8)
    else { return nil }
    var fields: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
      guard let separator = line.firstIndex(of: "=") else { continue }
      let key = line[..<separator].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      guard fields[key] == nil, !value.isEmpty else { return nil }
      fields[key] = value
    }
    return fields
  }
}
