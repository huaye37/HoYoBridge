import Foundation

/// Applies only display mode and startup size. Graphics quality, language and account data are untouched.
enum GameWindowPreferences {
  static func registryPath(for game: MiHoYoGame) -> String {
    switch game {
    case .genshin: "HKCU\\Software\\miHoYo\\原神"
    case .genshinGlobal: "HKCU\\Software\\miHoYo\\Genshin Impact"
    case .starRail: "HKCU\\Software\\miHoYo\\崩坏：星穹铁道"
    case .starRailGlobal: "HKCU\\Software\\Cognosphere\\Star Rail"
    case .zenlessZoneZero: "HKCU\\Software\\miHoYo\\绝区零"
    case .zenlessZoneZeroGlobal: "HKCU\\Software\\miHoYo\\ZenlessZoneZero"
    case .honkaiImpact3: "HKCU\\Software\\miHoYo\\崩坏3"
    case .honkaiImpact3Global: "HKCU\\Software\\miHoYo\\Honkai Impact 3rd"
    }
  }

  static func commands(game: MiHoYoGame, resolution: GameResolution) throws -> [[String]] {
    let key = registryPath(for: game)
    var result = [
      ("Screenmanager Is Fullscreen mode_h3981298716", 0),
      ("Screenmanager Fullscreen mode_h3630240806", 3),
      ("Screenmanager Resolution Width_h182942802", resolution.width),
      ("Screenmanager Resolution Height_h2627697771", resolution.height),
      ("Screenmanager Resolution Use Native_h1405027254", 0),
    ].map { name, value in ["reg", "add", key, "/v", name, "/t", "REG_DWORD", "/d", String(value), "/f"] }
    if game.baseGame == .starRail {
      // Star Rail reapplies this dedicated resolution record after Unity has read command-line flags.
      var json = try JSONSerialization.data(withJSONObject: ["width": resolution.width,
        "height": resolution.height, "isFullScreen": false], options: [.sortedKeys])
      json.append(0)
      result.append(["reg", "add", key, "/v", "GraphicsSettings_PCResolution_h431323223",
        "/t", "REG_BINARY", "/d", json.map { String(format: "%02x", $0) }.joined(), "/f"])
    }
    return result
  }

  static func apply(game: MiHoYoGame, wine: URL, environment: [String: String], resolution: GameResolution) throws {
    for arguments in try commands(game: game, resolution: resolution) {
      let process = Process()
      process.executableURL = wine
      process.arguments = arguments
      process.environment = environment.merging(["WINEDEBUG": "-all"]) { _, new in new }
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw NSError(domain: "HoYoBridge.Window", code: Int(process.terminationStatus),
          userInfo: [NSLocalizedDescriptionKey: "窗口设置应用失败，请查看运行环境后重试。"])
      }
    }
  }
}
