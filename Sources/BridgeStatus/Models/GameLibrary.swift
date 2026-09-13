import Foundation

enum GameCompatibilityProfile: String, Codable, Sendable {
  case genshinCN
  case starRailCN
  case zenlessZoneZeroCN
  case honkaiImpact3CN
  case genericCrossOverDXMT
  case unconfigured
}

struct GameLibraryItem: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let title: String
  let subtitle: String
  let executablePath: String?
  let profile: GameCompatibilityProfile
  let profileRevision: Int

  var isConfigured: Bool { profile != .unconfigured }

  init(
    id: String,
    title: String,
    subtitle: String,
    executablePath: String?,
    profile: GameCompatibilityProfile,
    profileRevision: Int = 1
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.executablePath = executablePath
    self.profile = profile
    self.profileRevision = profileRevision
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, subtitle, executablePath, profile, profileRevision
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    title = try values.decode(String.self, forKey: .title)
    subtitle = try values.decode(String.self, forKey: .subtitle)
    executablePath = try values.decodeIfPresent(String.self, forKey: .executablePath)
    profile = try values.decode(GameCompatibilityProfile.self, forKey: .profile)
    profileRevision = try values.decodeIfPresent(Int.self, forKey: .profileRevision) ?? 1
  }

  static let genshinCN = Self(
    id: "genshin-cn",
    title: "原神",
    subtitle: "国服 · 7.0.0",
    executablePath: nil,
    profile: .genshinCN,
    profileRevision: 1
  )

  static let starRailCN = Self(
    id: "starrail-cn",
    title: "崩坏：星穹铁道",
    subtitle: "国服 · CrossOver + DXMT",
    executablePath: nil,
    profile: .starRailCN,
    profileRevision: 1
  )

  static let zenlessZoneZeroCN = Self(
    id: "zzz-cn",
    title: "绝区零",
    subtitle: "国服 · CrossOver + DXMT",
    executablePath: nil,
    profile: .zenlessZoneZeroCN,
    profileRevision: 1
  )

  static let honkaiImpact3CN = Self(
    id: "honkai3-cn",
    title: "崩坏 3",
    subtitle: "国服 · CrossOver + DXMT",
    executablePath: nil,
    profile: .honkaiImpact3CN,
    profileRevision: 1
  )

  static let miHoYoCN: [Self] = [
    .genshinCN, .starRailCN, .zenlessZoneZeroCN, .honkaiImpact3CN,
  ]
}

enum SidebarDestination: Hashable {
  case game(String)
  case tool(StatusSection)
}
