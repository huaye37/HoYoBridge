import Foundation

enum MiHoYoGame: String, CaseIterable, Identifiable, Sendable {
  case genshin
  case starRail
  case zenlessZoneZero
  case honkaiImpact3

  var id: String { rawValue }

  var title: String {
    switch self {
    case .genshin: "原神"
    case .starRail: "崩坏：星穹铁道"
    case .zenlessZoneZero: "绝区零"
    case .honkaiImpact3: "崩坏 3"
    }
  }

  var shortTitle: String {
    switch self {
    case .genshin: "原"
    case .starRail: "星"
    case .zenlessZoneZero: "绝"
    case .honkaiImpact3: "崩"
    }
  }

  var sidebarTitle: String {
    switch self {
    case .genshin: "原神"
    case .starRail: "星穹铁道"
    case .zenlessZoneZero: "绝区零"
    case .honkaiImpact3: "崩坏 3"
    }
  }

  var artworkResourceName: String {
    switch self {
    case .genshin: "LauncherLandscape"
    case .starRail: "StarRailLandscape"
    case .zenlessZoneZero: "ZenlessLandscape"
    case .honkaiImpact3: "Honkai3Landscape"
    }
  }

  var tagline: String {
    switch self {
    case .genshin: "在 Mac 上，继续你的旅途。"
    case .starRail: "登上星穹列车，穿越银河。"
    case .zenlessZoneZero: "欢迎来到新艾利都。"
    case .honkaiImpact3: "为世界上所有的美好而战。"
    }
  }

  var symbol: String {
    switch self {
    case .genshin: "wind"
    case .starRail: "sparkles"
    case .zenlessZoneZero: "bolt.fill"
    case .honkaiImpact3: "flame.fill"
    }
  }

  var defaultDirectory: URL {
    let games = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Games/HoYoBridge", directoryHint: .isDirectory)
    switch self {
    case .genshin: return games.appending(path: "Genshin Impact", directoryHint: .isDirectory)
    case .starRail: return games.appending(path: "StarRail", directoryHint: .isDirectory)
    case .zenlessZoneZero:
      return games.appending(path: "ZenlessZoneZero", directoryHint: .isDirectory)
    case .honkaiImpact3:
      return games.appending(path: "HonkaiImpact3", directoryHint: .isDirectory)
    }
  }

  var executableNames: [String] {
    switch self {
    case .genshin: ["YuanShen.exe"]
    case .starRail: ["StarRail.exe"]
    case .zenlessZoneZero: ["ZenlessZoneZero.exe"]
    case .honkaiImpact3: ["BH3.exe", "bh3.exe"]
    }
  }

  var executableURL: URL? {
    let root = configuredDirectory ?? defaultDirectory
    guard UserDefaults.standard.string(forKey: "games.\(rawValue).pendingInstall") != root.path else { return nil }
    return executableNames.lazy.map { root.appending(path: $0) }
      .first { FileManager.default.isReadableFile(atPath: $0.path) }
  }

  var installationDiskOffline: Bool {
    Self.isInstallationDiskOffline(configuredDirectory,
      mountedVolumes: FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [])
  }

  static func isInstallationDiskOffline(_ directory: URL?, mountedVolumes: [URL]) -> Bool {
    guard let directory else { return false }
    let parts = directory.standardizedFileURL.pathComponents
    guard parts.count > 2, parts[1] == "Volumes" else { return false }
    let volume = "/Volumes/" + parts[2]
    return !mountedVolumes.contains { $0.standardizedFileURL.path == volume }
  }

  var configuredDirectory: URL? {
    if self == .genshin { return GameInstallLocationPreference.load() }
    guard
      let path = UserDefaults.standard.string(forKey: "games.\(rawValue).installationRoot"),
      path.hasPrefix("/")
    else {
      let legacy = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Games/MacGameBridge/Trials")
        .appending(path: defaultDirectory.lastPathComponent)
      return executableNames.contains(where: {
        FileManager.default.isReadableFile(atPath: legacy.appending(path: $0).path)
      }) ? legacy : nil
    }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  }

  func saveDirectory(_ url: URL) {
    if self == .genshin {
      GameInstallLocationPreference.save(url)
    } else {
      UserDefaults.standard.set(
        url.standardizedFileURL.path,
        forKey: "games.\(rawValue).installationRoot"
      )
    }
  }
}
