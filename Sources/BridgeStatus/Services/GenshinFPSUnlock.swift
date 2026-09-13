import Foundation

enum GenshinFPSUnlockError: Error, Equatable {
  case compatibilityShimMissing
  case unsupportedVersionModule
}

enum GenshinFPSUnlockStatus: Equatable, Sendable {
  case scanning
  case active(Int)
  case failed

  init?(contents: String) {
    switch contents.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "scanning": self = .scanning
    case "active:120": self = .active(120)
    case "active:144": self = .active(144)
    case let value where value.hasPrefix("failed:"): self = .failed
    default: return nil
    }
  }
}

enum GenshinFPSUnlock {
  static let statusFileName = "mgb-fps-unlock.status"
  private static let compatibilityShimName = "gptk4-msaa-version.dll"

  static func prepareDXMTPrefix(
    paths: GameRuntimePaths,
    compatibilityShim suppliedCompatibilityShim: URL? = nil
  ) throws {
    let manager = FileManager.default
    let sourceVersion = paths.runtimeRoot.appending(
      path: "wine/lib/wine/x86_64-windows/version.dll"
    )
    var versionData = try Data(contentsOf: sourceVersion)
    let originalName = Data("version.dll".utf8)
    let forwardedName = Data("versi0n.dll".utf8)
    guard let match = versionData.range(of: originalName),
      versionData[match.upperBound...].range(of: originalName) == nil
    else {
      throw GenshinFPSUnlockError.unsupportedVersionModule
    }
    versionData.replaceSubrange(match, with: forwardedName)

    let shim = try resolveCompatibilityShim(suppliedCompatibilityShim)
    let system32 = paths.prefix.appending(
      path: "drive_c/windows/system32",
      directoryHint: .isDirectory
    )
    try manager.createDirectory(at: system32, withIntermediateDirectories: true)
    try versionData.write(
      to: system32.appending(path: "versi0n.dll"),
      options: .atomic
    )
    try replace(shim, at: system32.appending(path: "version.dll"))
  }

  static func statusURL(paths: GameRuntimePaths) -> URL {
    paths.prefix.appending(
      path: "drive_c/windows/temp/\(statusFileName)"
    )
  }

  static func clearStatus(paths: GameRuntimePaths) {
    try? FileManager.default.removeItem(at: statusURL(paths: paths))
  }

  static func readStatus(paths: GameRuntimePaths) -> GenshinFPSUnlockStatus? {
    guard
      let contents = try? String(contentsOf: statusURL(paths: paths), encoding: .utf8)
    else { return nil }
    return GenshinFPSUnlockStatus(contents: contents)
  }

  private static func resolveCompatibilityShim(_ supplied: URL?) throws -> URL {
    if let supplied { return supplied }
    guard let resources = Bundle.main.resourceURL else {
      throw GenshinFPSUnlockError.compatibilityShimMissing
    }
    let bundled = resources.appending(path: "RuntimeAssets/\(compatibilityShimName)")
    guard FileManager.default.fileExists(atPath: bundled.path) else {
      throw GenshinFPSUnlockError.compatibilityShimMissing
    }
    return bundled
  }

  private static func replace(_ source: URL, at destination: URL) throws {
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.path) {
      try manager.removeItem(at: destination)
    }
    try manager.copyItem(at: source, to: destination)
  }
}
