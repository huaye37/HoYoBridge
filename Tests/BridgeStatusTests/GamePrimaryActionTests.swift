import Testing

@testable import BridgeStatus

@Suite("Launcher primary action")
struct GamePrimaryActionTests {
  private let installed = GameInstallationState.installed(version: "7.0.0")
  private let newVersion = GameUpdateState.available(installed: "7.0.0", target: "7.1.0")
  private let downloading = GameInstallationState.installing(
    .init(fraction: 0.5, downloadedBytes: 50, totalBytes: 100, bytesPerSecond: 5, etaSeconds: 10))

  @Test("published update replaces launch without requiring initial install free space")
  func update() {
    let action = GamePrimaryActionResolver.resolve(
      installation: installed, runtime: .ready, launcher: .ready,
      storage: .insufficient(missingBytes: 10), update: newVersion)
    #expect(action == .update(version: "7.1.0"))
    #expect(action.title == "更新至 7.1.0")
  }

  @Test("new version is handled before preparing and auto-launching a runtime")
  func updateBeforeAutoLaunch() {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: installed, runtime: .available, launcher: .unavailable("runtime"),
        storage: .unknown, update: newVersion) == .update(version: "7.1.0"))
  }

  @Test("failed metadata check does not pretend an update exists or block an installed game")
  func checkFailure() {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: installed, runtime: .ready, launcher: .ready,
        storage: .unknown, update: .failed("offline")) == .launch)
  }

  @Test("running game cannot trigger a second launch or update")
  func running() {
    let action = GamePrimaryActionResolver.resolve(
      installation: installed, runtime: .ready, launcher: .running,
      storage: .unknown, update: newVersion)
    #expect(action == .running)
    #expect(!action.isEnabled)
  }

  @Test(
    "offline disk takes precedence over installed or resumable snapshots", arguments: [true, false])
  func offlineDisk(hasGame: Bool) {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: hasGame ? installed : .resumable, runtime: .ready, launcher: .ready,
        storage: .unknown, update: newVersion, storageIsAccessible: false) == .reconnectStorage)
  }

  @Test("active download remains pausable with unavailable disk and runtime")
  func pause() {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: downloading, runtime: .unavailable("missing"), launcher: .ready,
        storage: .unknown, storageIsAccessible: false) == .pauseInstall)
  }

  @Test("migration exposes cancel instead of launch even after a disk disappears")
  func migration() {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: installed, runtime: .ready, launcher: .ready,
        storage: .unknown, update: newVersion, storageIsAccessible: false,
        isMigrating: true) == .cancelMigration)
  }

  @Test(
    "backup and rollback expose progress instead of conflicting actions", arguments: [true, false])
  func backup(creating: Bool) {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: downloading, runtime: .ready, launcher: .ready,
        storage: .unknown, update: newVersion, backup: creating ? .creating : .restoring)
        == .showRecovery)
  }

  @Test("pending download cancellation cannot restart installation")
  func cancelling() {
    let action = GamePrimaryActionResolver.resolve(
      installation: .cancelling, runtime: .ready, launcher: .ready,
      storage: .unknown, update: newVersion)
    #expect(action == .disabled)
    #expect(!action.isEnabled)
  }

  @Test("all actionable states carry distinct user-facing titles and icons")
  func labels() {
    let actions: [GamePrimaryAction] = [
      .install, .resumeInstall, .update(version: "7.1.0"), .reviewStorage,
      .reconnectStorage, .showInstallation, .showRecovery, .pauseInstall,
      .cancelMigration, .prepareAndLaunch, .launch,
    ]
    #expect(Set(actions.map(\.title)).count == actions.count)
    #expect(actions.allSatisfy { $0.isEnabled && !$0.symbol.isEmpty })
  }
}
