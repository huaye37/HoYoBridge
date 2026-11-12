import Foundation

struct NativeGameWindowSupport {
  let adapter: URL
  let helper: URL

  static func resolve(resourceURL: URL? = Bundle.main.resourceURL) -> Self? {
    guard let root = resourceURL?.appending(path: "RuntimeAssets") else { return nil }
    let result = Self(adapter: root.appending(path: "libMGBWindowAdapter.dylib"),
      helper: root.appending(path: "window-flags.exe"))
    return [result.adapter, result.helper].allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) } ? result : nil
  }

  static func titles(for game: MiHoYoGame) -> String {
    switch game {
    case .genshin: "原神|Genshin Impact"
    case .starRail: "Honkai: Star Rail"
    case .zenlessZoneZero: "绝区零|ZenlessZoneZero|Zenless Zone Zero"
    case .honkaiImpact3: "崩坏3|崩坏 3|Honkai Impact 3rd"
    }
  }

  func apply(to environment: inout [String: String], game: MiHoYoGame, fullscreen: Bool = false) {
    environment["MGB_NATIVE_WINDOW"] = "1"
    environment["MGB_NATIVE_WINDOW_TITLE"] = Self.titles(for: game)
    environment["MGB_NATIVE_FULLSCREEN"] = fullscreen ? "1" : "0"
    environment["DYLD_INSERT_LIBRARIES"] = adapter.path
  }

  static func applyDisplayMode(_ mode: GameWindowMode, to environment: inout [String: String]) {
    environment["MGB_NATIVE_FULLSCREEN"] = mode == .fullScreen ? "1" : "0"
  }

  static func applyingResolution(_ resolution: GameResolution, to arguments: [String]) -> [String] {
    var result: [String] = []
    var index = 0
    while index < arguments.count {
      if ["-screen-width", "-screen-height"].contains(arguments[index]), index + 1 < arguments.count {
        index += 2
      } else {
        result.append(arguments[index])
        index += 1
      }
    }
    return result + ["-screen-width", String(resolution.width), "-screen-height", String(resolution.height)]
  }

  static func applyFrameRate(_ mode: GameFPSUnlockMode, to environment: inout [String: String]) {
    var options = (environment["DXMT_CONFIG"] ?? "").split(separator: ";").map(String.init)
    options.removeAll { $0.trimmingCharacters(in: .whitespaces).hasPrefix("d3d11.preferredMaxFrameRate=") }
    options.append("d3d11.preferredMaxFrameRate=\(mode.targetFPS ?? 60)")
    environment["DXMT_CONFIG"] = options.joined(separator: ";") + ";"
  }

  func arguments(for game: MiHoYoGame) -> [String] {
    ["Z:" + helper.path.replacingOccurrences(of: "/", with: "\\"), Self.titles(for: game), "--watch"]
  }
}
