import Foundation

enum GameClientRegion: String, CaseIterable, Identifiable, Sendable {
  case china, global
  var id: String { rawValue }
  var title: String { self == .china ? "国服" : "国际服" }
  var enginePort: UInt16 { self == .china ? 19223 : 19224 }
  var engineDirectory: String { self == .china ? "Installer" : "Installer-Global" }
  var frontendHost: String { self == .china ? "hyp-api.mihoyo.com" : "sg-hyp-api.hoyoverse.com" }
  var engineDownloadURL: URL {
    URL(string: self == .china
      ? "https://hyp-webstatic.mihoyo.com/hyp-client/miHoYoLauncher_1.18.exe"
      : "https://download-porter.hoyoverse.com/download-porter/2026/09/03/VYTpXlbWo8_1.18.0.380_1_0_hyp_hoyoverse_prod_202608121905_ULWMhGsg.exe")!
  }
  var engineByteSize: Int { self == .china ? 209_837_072 : 203_175_872 }
  var engineSHA256: String { self == .china
    ? "674ff7201b42058cd569889ccbdc15cdd97709b1442876757a0f81785d716517"
    : "c15852937fb9f3a3f66646df5ba4c8fdb08e9611d2bf42a3bd87ea71294a751c" }
}

extension MiHoYoGame {
  static let navigationGames: [Self] = [.genshin, .starRail, .zenlessZoneZero, .honkaiImpact3]
  var region: GameClientRegion {
    switch self {
    case .genshin, .starRail, .zenlessZoneZero, .honkaiImpact3: .china
    default: .global
    }
  }
  var baseGame: Self {
    switch self {
    case .genshin, .genshinGlobal: .genshin
    case .starRail, .starRailGlobal: .starRail
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: .zenlessZoneZero
    case .honkaiImpact3, .honkaiImpact3Global: .honkaiImpact3
    }
  }
  func client(in region: GameClientRegion) -> Self {
    if region == .china { return baseGame }
    switch baseGame {
    case .genshin: return .genshinGlobal
    case .starRail: return .starRailGlobal
    case .zenlessZoneZero: return .zenlessZoneZeroGlobal
    default: return .honkaiImpact3Global
    }
  }
  var clientTitle: String { "\(title) · \(regionDescription)" }
  var officialBiz: String {
    let family: String = switch baseGame {
    case .genshin: "hk4e"
    case .starRail: "hkrpg"
    case .zenlessZoneZero: "nap"
    default: "bh3"
    }
    return family + (region == .china ? "_cn" : "_global")
  }
  // HoYoPlay separates HI3's regional distributions into packages under one biz.
  var officialPackage: String { self == .honkaiImpact3Global ? "glb_official" : "" }
  var regionDescription: String { self == .honkaiImpact3Global ? "国际服（欧美）" : region.title }
  func rememberedClient(defaults: UserDefaults = .standard) -> Self {
    client(in: GameClientRegion(rawValue: defaults.string(forKey: "games.\(baseGame.rawValue).selectedRegion") ?? "") ?? .china)
  }
  func rememberRegion(defaults: UserDefaults = .standard) {
    defaults.set(region.rawValue, forKey: "games.\(baseGame.rawValue).selectedRegion")
  }
}
