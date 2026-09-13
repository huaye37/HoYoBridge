import Foundation
import Testing
import Sparkle
@testable import BridgeStatus

struct LauncherUpdateTests {
  let key = Data(repeating: 1, count: 32).base64EncodedString()
  @Test func rejectsIncompleteConfiguration() {
    #expect(!LauncherUpdateConfiguration.isValid(feed: nil, publicKey: key))
    #expect(!LauncherUpdateConfiguration.isValid(feed: "https://example.com/appcast.xml", publicKey: nil))
    #expect(!LauncherUpdateConfiguration.isValid(feed: "https://example.com/appcast.xml", publicKey: "placeholder"))
  }
  @Test func validatesTransportAndKey() {
    #expect(LauncherUpdateConfiguration.isValid(feed: "https://example.com/appcast.xml", publicKey: key))
    #expect(!LauncherUpdateConfiguration.isValid(feed: "http://example.com/appcast.xml", publicKey: key))
    #expect(!LauncherUpdateConfiguration.isValid(feed: "https://user:password@example.com/appcast.xml", publicKey: key))
    #expect(!LauncherUpdateConfiguration.isValid(feed: "file:///tmp/appcast.xml", publicKey: key))
  }
  @Test @MainActor func busyTasksBlockUpdateCheck() throws {
    let service = LauncherUpdateService()
    let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    service.isBusy = { true }
    #expect(throws: (any Error).self) {
      try service.updater(controller.updater, mayPerform: .updates)
    }
    service.isBusy = { false }
    try service.updater(controller.updater, mayPerform: .updates)
  }
}
