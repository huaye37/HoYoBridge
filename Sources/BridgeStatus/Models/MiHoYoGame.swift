import Foundation

enum MiHoYoGame: String, CaseIterable, Identifiable, Sendable {
  case genshin
  case starRail
  case zenlessZoneZero
  case honkaiImpact3
  case genshinGlobal = "genshin-global"
  case starRailGlobal = "starRail-global"
  case zenlessZoneZeroGlobal = "zenlessZoneZero-global"
  case honkaiImpact3Global = "honkaiImpact3-global"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .genshin, .genshinGlobal: "原神"
    case .starRail, .starRailGlobal: "崩坏：星穹铁道"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "绝区零"
    case .honkaiImpact3, .honkaiImpact3Global: "崩坏 3"
    }
  }

  var shortTitle: String {
    switch self {
    case .genshin, .genshinGlobal: "原"
    case .starRail, .starRailGlobal: "星"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "绝"
    case .honkaiImpact3, .honkaiImpact3Global: "崩"
    }
  }

  var sidebarTitle: String {
    switch self {
    case .genshin, .genshinGlobal: "原神"
    case .starRail, .starRailGlobal: "星穹铁道"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "绝区零"
    case .honkaiImpact3, .honkaiImpact3Global: "崩坏 3"
    }
  }

  var artworkResourceName: String {
    switch self {
    case .genshin, .genshinGlobal: "LauncherLandscape"
    case .starRail, .starRailGlobal: "StarRailLandscape"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "ZenlessLandscape"
    case .honkaiImpact3, .honkaiImpact3Global: "Honkai3Landscape"
    }
  }

  var tagline: String {
    switch self {
    case .genshin, .genshinGlobal: "在 Mac 上，继续你的旅途。"
    case .starRail, .starRailGlobal: "登上星穹列车，穿越银河。"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "欢迎来到新艾利都。"
    case .honkaiImpact3, .honkaiImpact3Global: "为世界上所有的美好而战。"
    }
  }

  var symbol: String {
    switch self {
    case .genshin, .genshinGlobal: "wind"
    case .starRail, .starRailGlobal: "sparkles"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "bolt.fill"
    case .honkaiImpact3, .honkaiImpact3Global: "flame.fill"
    }
  }

  var storageRecommendation: String? {
    guard baseGame == .zenlessZoneZero else { return nil }
    return "推荐安装在本机磁盘。网络盘不推荐用于游玩；外置 SSD 请确认接口、线材及实际读写稳定。"
  }

  var defaultDirectory: URL {
    if region == .global {
      return baseGame.defaultDirectory.deletingLastPathComponent()
        .appending(path: baseGame.defaultDirectory.lastPathComponent + " Global", directoryHint: .isDirectory)
    }
    let games = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Games/HoYoBridge", directoryHint: .isDirectory)
    switch self {
    case .genshin, .genshinGlobal: return games.appending(path: "Genshin Impact", directoryHint: .isDirectory)
    case .starRail, .starRailGlobal: return games.appending(path: "StarRail", directoryHint: .isDirectory)
    case .zenlessZoneZero, .zenlessZoneZeroGlobal:
      return games.appending(path: "ZenlessZoneZero", directoryHint: .isDirectory)
    case .honkaiImpact3, .honkaiImpact3Global:
      return games.appending(path: "HonkaiImpact3", directoryHint: .isDirectory)
    }
  }

  var executableNames: [String] {
    if self == .genshinGlobal { return ["GenshinImpact.exe"] }
    return switch self {
    case .genshin, .genshinGlobal: ["YuanShen.exe"]
    case .starRail, .starRailGlobal: ["StarRail.exe"]
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: ["ZenlessZoneZero.exe"]
    case .honkaiImpact3, .honkaiImpact3Global: ["BH3.exe", "bh3.exe"]
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

  var configuredDirectory: URL? { configuredDirectory(defaults: .standard) }

  func configuredDirectory(defaults: UserDefaults) -> URL? {
    if self == .genshin { return GameInstallLocationPreference.load(defaults: defaults) }
    guard
      let path = defaults.string(forKey: "games.\(rawValue).installationRoot"),
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

  func saveDirectory(_ url: URL, defaults: UserDefaults = .standard) {
    if self == .genshin {
      GameInstallLocationPreference.save(url, defaults: defaults)
    } else {
      defaults.set(
        url.standardizedFileURL.path,
        forKey: "games.\(rawValue).installationRoot"
      )
    }
  }
}
