import Foundation
import Testing
@testable import BridgeStatus

struct NativeGameWindowSupportTests {
  @Test(arguments: MiHoYoGame.allCases)
  func onlyZenlessDefersWindowWatcher(_ game: MiHoYoGame) {
    #expect(NativeGameWindowSupport.helperDelay(for: game) == (game.baseGame == .zenlessZoneZero ? .seconds(32) : .zero))
  }

  @Test @MainActor func deferredWatcherHonorsCancellationAndLaunchIdentity() async throws {
    let scheduler = DeferredWindowHelper()
    var starts = 0
    scheduler.schedule(delay: .milliseconds(10), isCurrent: { true }, start: { starts += 1 })
    scheduler.cancel()
    try await Task.sleep(for: .milliseconds(30))
    #expect(starts == 0)
    scheduler.schedule(delay: .milliseconds(10), isCurrent: { false }, start: { starts += 1 })
    try await Task.sleep(for: .milliseconds(30))
    #expect(starts == 0)
    scheduler.schedule(delay: .milliseconds(10), isCurrent: { true }, start: { starts += 100 })
    scheduler.schedule(delay: .milliseconds(10), isCurrent: { true }, start: { starts += 1 })
    try await Task.sleep(for: .milliseconds(50))
    #expect(starts == 1)
  }
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

  @Test(arguments: MiHoYoGame.allCases, GameWindowMode.allCases)
  func commonNativeDisplayMode(_ game: MiHoYoGame, _ mode: GameWindowMode) {
    let support = NativeGameWindowSupport(adapter: URL(fileURLWithPath: "/adapter"), helper: URL(fileURLWithPath: "/helper"))
    var environment: [String: String] = [:]
    support.apply(to: &environment, game: game)
    NativeGameWindowSupport.applyDisplayMode(mode, to: &environment)
    #expect(environment["MGB_NATIVE_FULLSCREEN"] == (mode == .fullScreen ? "1" : "0"))
    #expect(environment["MGB_NATIVE_WINDOW_TITLE"] == NativeGameWindowSupport.titles(for: game))
  }

  @Test func globalResolutionReplacesProfileDefaults() {
    let arguments = ["jadeite", "game.exe", "--", "-screen-fullscreen", "0", "-screen-width", "3840", "-screen-height", "2160"]
    let result = NativeGameWindowSupport.applyingResolution(.balanced, to: arguments)
    #expect(result == ["jadeite", "game.exe", "--", "-screen-fullscreen", "0", "-screen-width", "1600", "-screen-height", "900"])
  }

  @Test func globalFrameRatePreservesOtherDXMTOptions() {
    var environment = ["DXMT_CONFIG": "d3d11.foo=true;d3d11.preferredMaxFrameRate=60;"]
    NativeGameWindowSupport.applyFrameRate(.fps120, to: &environment)
    #expect(environment["DXMT_CONFIG"] == "d3d11.foo=true;d3d11.preferredMaxFrameRate=120;")
    NativeGameWindowSupport.applyFrameRate(.disabled, to: &environment)
    #expect(environment["DXMT_CONFIG"] == "d3d11.foo=true;d3d11.preferredMaxFrameRate=60;")
  }
}
