import Foundation
import Testing
@testable import BridgeStatus

struct GameStartupCompatibilityTests {
  @Test(arguments: MiHoYoGame.allCases)
  func freshServerRequirementIsLimitedToZenless(_ game: MiHoYoGame) {
    #expect(GameStartupReadiness.requiresFreshServer(for: game) == (game.baseGame == .zenlessZoneZero))
  }

  @Test func prefixWaiterFailsOnErrorOrTimeoutAndHonorsCancellation() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "startup-wait-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appending(path: "waiter")
    func prepare(_ code: String) throws {
      try Data(("#!/bin/sh\n[ \"$1\" = '-w' ] || exit 99\n" + code + "\n").utf8).write(to: script)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    }
    try prepare("exit 0")
    try await GameStartupReadiness.waitForPrefixIdle(wineserver: script, environment: [:])
    try prepare("exit 7")
    await #expect(throws: (any Error).self) {
      try await GameStartupReadiness.waitForPrefixIdle(wineserver: script, environment: [:])
    }
    try prepare("exec /bin/sleep 10")
    await #expect(throws: (any Error).self) {
      try await GameStartupReadiness.waitForPrefixIdle(wineserver: script, environment: [:], timeout: .milliseconds(100))
    }
    let task = Task { try await GameStartupReadiness.waitForPrefixIdle(wineserver: script, environment: [:]) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
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
