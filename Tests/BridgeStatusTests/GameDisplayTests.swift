import Testing
@testable import BridgeStatus

struct GameDisplayTests {
  let horizontal = GameDisplay(id: "external", displayID: 4, name: "273B1C", isBuiltIn: false, isPortrait: false)
  let laptop = GameDisplay(id: "builtin", displayID: 1, name: "Mac", isBuiltIn: true, isPortrait: false)
  let portrait = GameDisplay(id: "vertical", displayID: 5, name: "HX270S", isBuiltIn: false, isPortrait: true)

  @Test func threeScreensHaveTwoGameTargetsAndSelectionSurvivesReordering() {
    let screens = [horizontal, laptop, portrait]
    #expect(screens.filter { !$0.isPortrait }.count == 2)
    #expect(GameDisplayCatalog.selected(in: screens, preferredID: laptop.id) == laptop)
    #expect(GameDisplayCatalog.selected(in: [portrait, laptop, horizontal], preferredID: horizontal.id) == horizontal)
    #expect(GameDisplayCatalog.selected(in: screens, preferredID: portrait.id) == horizontal)
    #expect(GameDisplayCatalog.selected(in: [portrait, laptop], preferredID: horizontal.id) == laptop)
    #expect(GameDisplayCatalog.selected(in: [portrait], preferredID: "") == nil)
  }

  @Test func portraitModesAreNotGameResolutionPresets() {
    let options = GameResolutionCatalog.options(resolutions: [.init(width: 2160, height: 3840), .init(width: 3840, height: 2160)],
      currentDesktop: [], nativePixels: [])
    #expect(options.map(\.resolution.rawValue) == ["3840x2160"])
    let hidpi = GameResolutionOption(resolution: .init(width: 5120, height: 2880), isCurrentDesktop: false, isNativePixels: true, isCommon: true)
    #expect(hidpi.title.contains("当前渲染像素"))
    #expect(!hidpi.title.contains("原生像素"))
  }

  @Test func allGamesReceivePixelSizeNotLogicalPoints() {
    for game in MiHoYoGame.allCases {
      var env: [String: String] = [:]
      NativeGameWindowSupport(adapter: .init(fileURLWithPath: "/adapter"), helper: .init(fileURLWithPath: "/helper")).apply(to: &env, game: game)
      NativeGameWindowSupport.applyDisplayMode(.fullScreen, to: &env, resolution: .init(width: 3840, height: 2160))
      #expect(env["MGB_STARTUP_PIXEL_WIDTH"] == "3840")
      #expect(env["MGB_STARTUP_PIXEL_HEIGHT"] == "2160")
      #expect(env["MGB_NATIVE_FULLSCREEN"] == "1")
    }
  }
}
