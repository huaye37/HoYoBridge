import Foundation
import Testing
@testable import BridgeStatus

@MainActor
struct GameMigrationTests {
  @Test func retainedPartialIsRevalidatedAndOnlyIncompleteFilesAreRewritten() async throws {
    let game = MiHoYoGame.starRail
    let (root, source, container) = try fixture(game)
    defer { try? FileManager.default.removeItem(at: root) }
    let partial = container.appending(path: ".mgb-migration-retained-test")
    try FileManager.default.createDirectory(at: partial.appending(path: "StarRail_Data"), withIntermediateDirectories: true)
    let good = partial.appending(path: "StarRail.exe")
    try FileManager.default.copyItem(at: source.appending(path: "StarRail.exe"), to: good)
    let oldDate = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: good.path)
    try Data("truncated".utf8).write(to: partial.appending(path: "StarRail_Data/payload"))
    let result = try await GameStorageManager.migrate(source: source, to: container, game: game, resuming: partial)
    #expect(try result.appending(path: "StarRail.exe").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == oldDate)
    #expect(try Data(contentsOf: result.appending(path: "StarRail_Data/payload")) == Data(contentsOf: source.appending(path: "StarRail_Data/payload")))
    #expect(!FileManager.default.fileExists(atPath: partial.path))
  }

  @Test func realSMBPublicationWhenRequested() async throws {
    guard let path = ProcessInfo.processInfo.environment["MGB_TEST_MIGRATION_SMB_ROOT"] else { return }
    let parent = URL(fileURLWithPath: path, isDirectory: true)
    let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
    #expect(!MiHoYoGame.isInstallationDiskOffline(parent, mountedVolumes: volumes))
    let volume = try InstallVolumeProbe.inspect(parent, isDefaultPreview: false)
    #expect(volume.isNetwork)
    let (root, source, _) = try fixture(.starRail)
    defer { try? FileManager.default.removeItem(at: root) }
    let container = parent.appending(path: ".mgb-smb-validation-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: container) }
    let result = try await GameStorageManager.migrate(source: source, to: container, game: .starRail)
    #expect(try Data(contentsOf: result.appending(path: "StarRail_Data/payload")) == Data(contentsOf: source.appending(path: "StarRail_Data/payload")))
    #expect(FileManager.default.fileExists(atPath: source.appending(path: "StarRail.exe").path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: container.path) == [source.lastPathComponent])
  }

  @Test func publicationConflictRetainsVerifiedCopyAndCanBeRetried() async throws {
    let game = MiHoYoGame.starRail
    let (root, source, container) = try fixture(game)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = container.appending(path: source.lastPathComponent)
    do {
      _ = try await GameStorageManager.migrate(source: source, to: container, game: game) { progress in
        if progress.phase == "正在校验新副本" && !FileManager.default.fileExists(atPath: target.path) {
          try? Data("keep-other-file".utf8).write(to: target, options: .withoutOverwriting)
        }
      }
      Issue.record("Expected publication conflict")
    } catch let error as GameMigrationPublicationFailure {
      #expect(try Data(contentsOf: target) == Data("keep-other-file".utf8))
      #expect(try GameStorageManager.recognize(error.copy, game: game).path == error.copy.path)
      try FileManager.default.removeItem(at: target) // Only this test's deliberately injected file.
      try GameStorageManager.publishVerifiedCopy(error.copy, to: error.destination)
      #expect(try GameStorageManager.recognize(target, game: game).path == target.path)
      #expect(FileManager.default.fileExists(atPath: source.appending(path: "StarRail.exe").path))
    }
  }

  private func fixture(_ game: MiHoYoGame) throws -> (URL, URL, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID())").resolvingSymlinksInPath()
    let source = root.appending(path: "Source \(game.rawValue)")
    let container = root.appending(path: "Destination")
    let exe = game.executableNames[0]
    let data = String(exe.dropLast(4)) + "_Data"
    try FileManager.default.createDirectory(at: source.appending(path: data), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    try Data("exe".utf8).write(to: source.appending(path: exe))
    try Data(repeating: 42, count: 4096).write(to: source.appending(path: data + "/payload"))
    try Data("game_biz=\(game.officialBiz)\n".utf8).write(to: source.appending(path: "config.ini"))
    return (root, source, container)
  }

  @Test(arguments: MiHoYoGame.allCases)
  func eachClientCopiesAndVerifiesWithoutRemovingSource(_ game: MiHoYoGame) async throws {
    let (root, source, container) = try fixture(game)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = try await GameStorageManager.migrate(source: source, to: container, game: game)
    #expect(try GameStorageManager.recognize(destination, game: game) == destination)
    #expect(FileManager.default.fileExists(atPath: source.appending(path: game.executableNames[0]).path))
    #expect(try Data(contentsOf: source.appending(path: "config.ini")) == Data(contentsOf: destination.appending(path: "config.ini")))
  }

  @Test(arguments: [false, true])
  func pathCommitsOnlyAfterOfficialReadbackAndFailedAssociationCanResume(failFirst: Bool) async throws {
    let game = MiHoYoGame.zenlessZoneZeroGlobal
    let (root, source, container) = try fixture(game)
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "MigrationTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    game.saveDirectory(source, defaults: defaults)
    let other = root.appending(path: "CN untouched")
    MiHoYoGame.zenlessZoneZero.saveDirectory(other, defaults: defaults)
    let destination = container.appending(path: source.lastPathComponent)
    func win(_ url: URL) -> String { "Z:" + url.path.replacingOccurrences(of: "/", with: "\\") }
    var linkedPath = win(source)
    var fail = failFirst
    let commands = OfficialEngineCommands(query: { action, arguments in
      switch action {
      case "getLocalGameInfo":
        return [["gameBiz": game.officialBiz, "package": "", "status": "ready", "installPath": linkedPath]]
      case "findGame":
        #expect(arguments["dir"] as? String == win(destination))
        return [["gameBiz": game.officialBiz, "package": "", "path": win(destination), "isFindDir": true, "pathAvailable": true, "errorCode": 0]]
      case "updateGameSettings": return ["result": "success"]
      case "linkGame":
        if fail { throw NSError(domain: "simulated association failure", code: 1) }
        linkedPath = win(destination)
        return [["gameBiz": game.officialBiz, "package": "", "isLinked": true]]
      default: Issue.record("Unexpected mutation/query: \(action)"); return nil
      }
    }, stop: {})
    let service = OfficialGameInstaller(region: .global, storageRoot: root, defaults: defaults, commands: commands)
    service.migrateGame(game, from: source, to: container)
    #expect(service.blocksLaunch(for: game))
    #expect(try await service.preparePausedDownloadsForUpdate() == false)
    for _ in 0..<200 {
      if !service.isOccupied { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!service.isOccupied)
    if failFirst {
      #expect(game.configuredDirectory(defaults: defaults)?.path == source.path)
      #expect(service.migrationCopy(game)?.path == destination.path)
      fail = false
      let recreated = OfficialGameInstaller(region: .global, storageRoot: root, defaults: defaults, commands: commands)
      recreated.retryMigrationAssociation(game)
      for _ in 0..<200 {
        if !recreated.isOccupied { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(!recreated.isOccupied)
      #expect(recreated.migrationCopy(game) == nil)
    }
    #expect(game.configuredDirectory(defaults: defaults)?.path == destination.path)
    #expect(linkedPath == win(destination))
    #expect(MiHoYoGame.zenlessZoneZero.configuredDirectory(defaults: defaults)?.path == other.path)
    #expect(try Data(contentsOf: source.appending(path: "ZenlessZoneZero.exe")) == Data("exe".utf8))
  }

  @Test func destinationInsideAnotherClientIsRefused() async throws {
    let game = MiHoYoGame.zenlessZoneZeroGlobal
    let (root, source, container) = try fixture(game)
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "MigrationConflict.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    game.saveDirectory(source, defaults: defaults)
    MiHoYoGame.zenlessZoneZero.saveDirectory(container, defaults: defaults)
    let service = OfficialGameInstaller(region: .global, storageRoot: root, defaults: defaults,
      commands: .init(query: { _, _ in Issue.record("Must reject before engine mutation"); return nil }, stop: {}))
    service.migrateGame(game, from: source, to: container)
    for _ in 0..<50 { if !service.isOccupied { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(game.configuredDirectory(defaults: defaults)?.path == source.path)
    #expect(!FileManager.default.fileExists(atPath: container.appending(path: source.lastPathComponent).path))
  }
}
