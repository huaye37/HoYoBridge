import Foundation
import Testing

@testable import BridgeStatus

@Suite("Interrupted game updates")
struct GameRecoveryTests {
  @Test("cancelling before any writer starts keeps the original game launchable")
  @MainActor func cancelBeforeWriting() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let service = fixture.service()
    service.startOrResume(selectedLocation: nil)
    service.cancel()
    try await waitUntil { service.canChangeStorage }
    #expect(service.state == .installed(version: "7.0.0"))
    #expect(fixture.paths.isGameReady)
    #expect(try fixture.payload() == "good")
  }

  @Test("first-install interruption remains resumable without pretending a backup exists")
  @MainActor func firstInstallInterruption() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try FileManager.default.removeItem(at: fixture.game.appending(path: "YuanShen.exe"))
    try FileManager.default.removeItem(at: fixture.game.appending(path: "config.ini"))
    try GameInstallationRecord.begin(at: fixture.game)
    let service = fixture.service()
    #expect(service.state == .resumable)
    #expect(service.backupState == .none)
    #expect(!fixture.paths.isGameReady)
    service.createSafetyBackup()
    #expect(service.backupState == .none)
  }

  @Test("partial executable never overrides the downloading marker")
  func partialExecutable() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try GameInstallationRecord.begin(at: fixture.game)
    #expect(GameInstallationRecord.state(at: fixture.game) == .recoveryRequired)
    #expect(!fixture.paths.isGameReady)
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .recoveryRequired, runtime: .ready, launcher: .ready,
        storage: .insufficient(missingBytes: 1)) == .resumeRecovery)
  }

  @Test("missing executable does not hide interrupted update or rollback point")
  @MainActor func missingExecutable() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    _ = try GameAPFSBackupManager.createBackup(for: fixture.game)
    try GameInstallationRecord.begin(at: fixture.game)
    try FileManager.default.removeItem(at: fixture.game.appending(path: "YuanShen.exe"))
    let service = fixture.service()
    #expect(service.state == .recoveryRequired)
    guard case .available(let backup) = service.backupState else {
      Issue.record("Good backup was hidden")
      return
    }
    #expect(backup.isRestorable)
    service.rollbackToBackup()
    try await waitUntil { service.canChangeStorage }
    #expect(service.state == .installed(version: "7.0.0"))
    #expect(try fixture.payload() == "good")
    let discarded = try #require(GameAPFSBackupManager.loadBackup(for: fixture.game))
    #expect(!discarded.isRestorable)
    #expect(throws: (any Error).self) {
      try GameAPFSBackupManager.rollback(gameURL: fixture.game)
    }
    #expect(try fixture.payload() == "good")
  }

  @Test(
    "invalid marker fails closed",
    arguments: [
      "", "schema=1\n", "schema=9\nstate=complete\nversion=7.0.0\n",
      "schema=1\nstate=complete\nversion=7.1.0\n",
      "schema=1\nstate=complete\nstate=downloading\nversion=7.0.0\n",
    ])
  func damagedMarker(contents: String) throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try Data(contents.utf8).write(to: fixture.marker)
    #expect(GameInstallationRecord.state(at: fixture.game) == .recoveryRequired)
    #expect(!fixture.paths.isGameReady)
  }

  @Test("complete marker accepts ordinary config with empty SDK field and CRLF")
  func completedRecord() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try fixture.complete(version: "7.0.0")
    #expect(GameInstallationRecord.completedVersion(at: fixture.game) == "7.0.0")
    #expect(fixture.paths.isGameReady)
  }

  @Test("partial files cannot replace an existing good backup")
  func protectBackup() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let backup = try GameAPFSBackupManager.createBackup(for: fixture.game)
    try GameInstallationRecord.begin(at: fixture.game)
    try Data("partial".utf8).write(to: fixture.game.appending(path: "payload"))
    #expect(throws: (any Error).self) {
      try GameAPFSBackupManager.createBackup(for: fixture.game)
    }
    #expect(GameAPFSBackupManager.loadBackup(for: fixture.game) == backup)
    #expect(try fixture.payload(at: backup.gameURL) == "good")
  }

  @Test("failed child and resume preserve the same good backup across service recreation")
  @MainActor func failureAndResume() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try fixture.script("printf partial > \"$2/payload\"\nexit 1\n")
    let first = fixture.service()
    first.startOrResume(selectedLocation: nil)
    try await waitUntil { first.canChangeStorage }
    #expect(first.state == .recoveryRequired)
    let backup = try #require(GameAPFSBackupManager.loadBackup(for: fixture.game))
    #expect(try fixture.payload(at: backup.gameURL) == "good")
    let resumed = fixture.service()
    #expect(resumed.state == .recoveryRequired)
    resumed.startOrResume(selectedLocation: nil)
    try await waitUntil { resumed.canChangeStorage }
    #expect(resumed.state == .recoveryRequired)
    #expect(GameAPFSBackupManager.loadBackup(for: fixture.game) == backup)
    #expect(try fixture.payload(at: backup.gameURL) == "good")
  }

  @Test("successful resumed child commits version without replacing the original backup")
  @MainActor func resumeCompletes() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let backup = try GameAPFSBackupManager.createBackup(for: fixture.game)
    try GameInstallationRecord.begin(at: fixture.game)
    try fixture.script(
      """
      printf 'game_version=7.1.0\\n' > "$2/config.ini"
      printf 'schema=1\\nstate=complete\\nversion=7.1.0\\n' > "$2/.mgb-managed-cn-download"
      printf 'COMPLETE version=7.1.0\\n'
      """)
    let service = fixture.service()
    service.startOrResume(selectedLocation: nil)
    try await waitUntil { service.canChangeStorage }
    #expect(service.state == .installed(version: "7.1.0"))
    #expect(service.updateState == .current(version: "7.1.0"))
    #expect(GameAPFSBackupManager.loadBackup(for: fixture.game) == backup)
    #expect(fixture.paths.isGameReady)
    #expect(fixture.service().state == .installed(version: "7.1.0"))
  }

  @Test("zero exit and COMPLETE output without a committed marker cannot enable launch")
  @MainActor func falseSuccess() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try fixture.script("printf 'COMPLETE version=7.1.0\\n'\nexit 0\n")
    let service = fixture.service()
    service.startOrResume(selectedLocation: nil)
    try await waitUntil { service.canChangeStorage }
    #expect(service.state == .recoveryRequired)
    #expect(!fixture.paths.isGameReady)
  }

  @Test("pause waits for the writer to stop before permitting rollback or restart")
  @MainActor func pauseWriter() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    try fixture.script(
      """
      trap 'sleep 0.3; printf stopped > "$2/stopped"; exit 1' INT TERM
      printf started > "$2/started"
      while :; do printf 'tick\\n'; sleep 0.05; done
      """)
    let service = fixture.service()
    service.startOrResume(selectedLocation: nil)
    try await waitUntil {
      FileManager.default.fileExists(atPath: fixture.game.appending(path: "started").path)
    }
    service.cancel()
    #expect(service.state == .cancelling)
    #expect(!service.canChangeStorage)
    service.rollbackToBackup()
    service.startOrResume(selectedLocation: nil)
    #expect(!service.canChangeStorage)
    try await waitUntil { service.canChangeStorage }
    #expect(FileManager.default.fileExists(atPath: fixture.game.appending(path: "stopped").path))
    #expect(service.state == .recoveryRequired)
    #expect(!GameDownloadLock.isBusy(game: fixture.game))
  }

  @Test("child retains exclusive lock even when the launcher closes its handle")
  @MainActor func inheritedLock() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let lock = try GameDownloadLock(game: fixture.game)
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["0.5"]
    child.standardInput = lock.handle
    try child.run()
    try lock.handle.close()
    #expect(GameDownloadLock.isBusy(game: fixture.game))
    #expect(!fixture.paths.isGameReady)
    let reopened = fixture.service()
    guard case .unavailable = reopened.state else {
      Issue.record("Reopened launcher ignored live child lock")
      return
    }
    await GameInstallationService.waitForExit(child)
    #expect(!GameDownloadLock.isBusy(game: fixture.game))
    reopened.refresh()
    #expect(reopened.state == .installed(version: "7.0.0"))
  }

  @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<300 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Timed out waiting for isolated installation fixture")
    throw CancellationError()
  }

  private struct Fixture {
    let root: URL
    let game: URL
    let defaults: UserDefaults
    let suite: String
    var marker: URL { game.appending(path: GameInstallationRecord.markerName) }
    var paths: GameRuntimePaths {
      .init(
        projectRoot: root, runtimeRoot: root, prefix: root,
        gameExecutable: game.appending(path: "YuanShen.exe"))
    }

    init() throws {
      suite = "GameRecoveryTests.\(UUID().uuidString)"
      defaults = try #require(UserDefaults(suiteName: suite))
      root = FileManager.default.temporaryDirectory.appending(
        path: suite, directoryHint: .isDirectory)
      game = root.appending(path: "Genshin Impact", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(
        at: game.appending(path: "YuanShen_Data"), withIntermediateDirectories: true)
      try Data("exe".utf8).write(to: game.appending(path: "YuanShen.exe"))
      try Data("good".utf8).write(to: game.appending(path: "payload"))
      try Data("[General]\r\ngame_version=7.0.0\r\nsdk_version=\r\n".utf8).write(
        to: game.appending(path: "config.ini"))
      GameInstallLocationPreference.save(game, defaults: defaults)
    }

    func cleanUp() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }

    func payload(at directory: URL? = nil) throws -> String {
      try String(contentsOf: (directory ?? game).appending(path: "payload"), encoding: .utf8)
    }

    func complete(version: String) throws {
      try Data("schema=1\nstate=complete\nversion=\(version)\n".utf8).write(to: marker)
    }

    func script(_ contents: String) throws {
      try Data(contents.utf8).write(to: root.appending(path: "installer.sh"))
    }

    @MainActor func service() -> GameInstallationService {
      GameInstallationService(
        defaults: defaults, automaticallyChecksForUpdates: false,
        installerToolchain: .init(
          python: URL(fileURLWithPath: "/bin/sh"), pythonPackages: nil,
          script: root.appending(path: "installer.sh"), upstream: root, isBundled: false),
        logDirectory: root.appending(path: "logs"))
    }
  }
}
