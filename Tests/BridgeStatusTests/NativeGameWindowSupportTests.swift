import Foundation
import Testing
@testable import BridgeStatus

struct NativeGameWindowSupportTests {
  @Test(arguments: MiHoYoGame.allCases)
  func isolatedWindowConfiguration(_ game: MiHoYoGame) {
    let support = NativeGameWindowSupport(
      adapter: URL(fileURLWithPath: "/Applications/Bridge/adapter.dylib"),
      helper: URL(fileURLWithPath: "/Applications/Bridge/window-flags.exe"))
    var environment = ["WINEPREFIX": "/private/game-prefix", "WINEDLLOVERRIDES": "version=n"]
    support.apply(to: &environment, game: game)
    #expect(environment["WINEPREFIX"] == "/private/game-prefix")
    #expect(environment["WINEDLLOVERRIDES"] == "version=n")
    #expect(environment["MGB_NATIVE_WINDOW"] == "1")
    #expect(environment["MGB_NATIVE_FULLSCREEN"] == "0")
    #expect(environment["MGB_NATIVE_WINDOW_TITLE"] == NativeGameWindowSupport.titles(for: game))
    #expect(support.arguments(for: game) == ["Z:\\Applications\\Bridge\\window-flags.exe", NativeGameWindowSupport.titles(for: game), "--watch"])
  }

  @Test func fullscreenPreferenceAndMissingAssets() {
    let support = NativeGameWindowSupport(adapter: URL(fileURLWithPath: "/adapter"), helper: URL(fileURLWithPath: "/helper"))
    var environment: [String: String] = [:]
    support.apply(to: &environment, game: .genshin, fullscreen: true)
    #expect(environment["MGB_NATIVE_FULLSCREEN"] == "1")
    #expect(NativeGameWindowSupport.resolve(resourceURL: nil) == nil)
  }
}
