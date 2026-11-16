import Testing
@testable import BridgeStatus

struct GameStartupCompatibilityTests {
  @Test(arguments: MiHoYoGame.allCases)
  func timeoutCompatibilityIsScopedToZenlessClients(_ game: MiHoYoGame) {
    var environment = ["WINEPREFIX": "/private/client", "WINEESYNC": "1", "DXMT_CONFIG": "keep", "WINE_ENABLE_TIMEOUT_FIX": "0"]
    MiHoYoLaunchPlan.applyStartupCompatibility(for: game, to: &environment)
    #expect(environment["WINE_ENABLE_TIMEOUT_FIX"] == (game.baseGame == .zenlessZoneZero ? "1" : "0"))
    #expect(environment["WINEPREFIX"] == "/private/client")
    #expect(environment["WINEESYNC"] == "1")
    #expect(environment["DXMT_CONFIG"] == "keep")
  }
}
