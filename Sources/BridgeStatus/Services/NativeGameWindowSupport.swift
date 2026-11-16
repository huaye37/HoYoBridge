import Foundation

struct NativeGameWindowSupport {
  let adapter: URL
  let helper: URL

  static func helperDelay(for game: MiHoYoGame) -> Duration {
    // ZZZ 3.3 reproducibly crashes during protection initialization when the Win32
    // window watcher starts first. The native AppKit adapter remains active immediately.
    game.baseGame == .zenlessZoneZero ? .seconds(32) : .zero
  }

  static func resolve(resourceURL: URL? = Bundle.main.resourceURL) -> Self? {
    guard let root = resourceURL?.appending(path: "RuntimeAssets") else { return nil }
    let result = Self(adapter: root.appending(path: "libMGBWindowAdapter.dylib"),
      helper: root.appending(path: "window-flags.exe"))
    return [result.adapter, result.helper].allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) } ? result : nil
  }

  static func titles(for game: MiHoYoGame) -> String {
    switch game {
    case .genshin, .genshinGlobal: "原神|Genshin Impact"
    case .starRail, .starRailGlobal: "Honkai: Star Rail"
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: "绝区零|ZenlessZoneZero|Zenless Zone Zero"
    case .honkaiImpact3, .honkaiImpact3Global: "崩坏3|崩坏 3|Honkai Impact 3rd"
    }
  }

  func apply(to environment: inout [String: String], game: MiHoYoGame, fullscreen: Bool = false) {
    environment["MGB_NATIVE_WINDOW"] = "1"
    environment["MGB_NATIVE_WINDOW_TITLE"] = Self.titles(for: game)
    environment["MGB_NATIVE_FULLSCREEN"] = fullscreen ? "1" : "0"
    environment["DYLD_INSERT_LIBRARIES"] = adapter.path
  }

  static func applyDisplayMode(_ mode: GameWindowMode, to environment: inout [String: String], resolution: GameResolution? = nil) {
    environment["MGB_NATIVE_FULLSCREEN"] = mode == .fullScreen ? "1" : "0"
    environment["MGB_TARGET_DISPLAY_UUID"] = UserDefaults.standard.string(forKey: GameDisplayCatalog.preferenceKey) ?? ""
    if let resolution {
      environment["MGB_STARTUP_PIXEL_WIDTH"] = String(resolution.width)
      environment["MGB_STARTUP_PIXEL_HEIGHT"] = String(resolution.height)
    }
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

@MainActor
final class DeferredWindowHelper {
  private var task: Task<Void, Never>?

  func schedule(delay: Duration, isCurrent: @escaping @MainActor () -> Bool,
    start: @escaping @MainActor () -> Void) {
    cancel()
    task = Task {
      do { try await Task.sleep(for: delay) } catch { return }
      guard !Task.isCancelled, isCurrent() else { return }
      start()
    }
  }

  func cancel() { task?.cancel(); task = nil }
}
