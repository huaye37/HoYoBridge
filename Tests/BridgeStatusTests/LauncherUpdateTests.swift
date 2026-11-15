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
  @Test @MainActor func busyTasksDoNotBlockCheckingForUpdates() throws {
    let service = LauncherUpdateService()
    let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    service.isBusy = { true }
    try service.updater(controller.updater, mayPerform: .updates)
    service.isBusy = { false }
    try service.updater(controller.updater, mayPerform: .updates)
  }

  @Test @MainActor func confirmedInstallationPreparesPausedTasksThenContinuesOnce() async throws {
    let service = LauncherUpdateService()
    var busy = true
    var prepares = 0
    var installs = 0
    service.isBusy = { busy }
    service.prepareForInstallation = { prepares += 1; busy = false; return true }
    #expect(service.postponeInstallationIfNeeded { installs += 1 })
    for _ in 0..<30 {
      if installs > 0 { break }
      await Task.yield()
    }
    #expect(prepares == 1)
    #expect(installs == 1)
  }

  @Test @MainActor func failedPreparationNeverInvokesInstaller() async throws {
    let service = LauncherUpdateService()
    var prepares = 0
    var installs = 0
    service.isBusy = { true }
    service.prepareForInstallation = {
      prepares += 1
      throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "停止确认失败"])
    }
    #expect(service.postponeInstallationIfNeeded { installs += 1 })
    for _ in 0..<30 { if prepares > 0 { break }; await Task.yield() }
    #expect(prepares == 1)
    #expect(installs == 0)
    #expect(service.message.contains("停止确认失败"))
  }

  @Test @MainActor func activeWorkDefersInstallationAndAbortCancelsPendingHandler() async throws {
    let service = LauncherUpdateService()
    var prepares = 0
    var installs = 0
    service.isBusy = { true }
    service.prepareForInstallation = { prepares += 1; return false }
    #expect(service.postponeInstallationIfNeeded { installs += 1 })
    for _ in 0..<30 { if prepares > 0 { break }; await Task.yield() }
    #expect(installs == 0)
    let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    service.updater(controller.updater, didAbortWithError: NSError(domain: "Test", code: 2))
    service.isBusy = { false }
    await Task.yield()
    #expect(installs == 0)
  }
}
