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

  func arguments(for game: MiHoYoGame) -> [String] {
    ["Z:" + helper.path.replacingOccurrences(of: "/", with: "\\"), Self.titles(for: game), "--watch"]
  }
}
