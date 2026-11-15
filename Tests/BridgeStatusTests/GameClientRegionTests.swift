import Foundation
import Testing
@testable import BridgeStatus

struct GameClientRegionTests {
  @Test func regionalInstallationsAndSelectionSurviveReloadIndependently() throws {
    let name = "GameClientRegionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    for base in MiHoYoGame.navigationGames {
      let global = base.client(in: .global)
      base.saveDirectory(URL(fileURLWithPath: "/Games/China/\(base.rawValue)"), defaults: defaults)
      global.saveDirectory(URL(fileURLWithPath: "/Games/Global/\(base.rawValue)"), defaults: defaults)
      global.rememberRegion(defaults: defaults)
      let reloaded = try #require(UserDefaults(suiteName: name))
      #expect(base.configuredDirectory(defaults: reloaded)?.path == "/Games/China/\(base.rawValue)")
      #expect(global.configuredDirectory(defaults: reloaded)?.path == "/Games/Global/\(base.rawValue)")
      #expect(base.rememberedClient(defaults: reloaded) == global)
    }
    #expect(Set(MiHoYoGame.allCases.map(\.defaultDirectory)).count == 8)
    #expect(MiHoYoGame.genshinGlobal.executableNames == ["GenshinImpact.exe"])
  }

  @Test func directoriesCannotOverlapOtherClientsOrFollowLinks() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let china = root.appending(path: "CN")
    try FileManager.default.createDirectory(at: china, withIntermediateDirectories: true)
    let locations = [GameClientLocation(client: .starRail, directory: china)]
    #expect(GameClientDirectoryPolicy.issue(for: root, client: .starRailGlobal, locations: locations) != nil)
    #expect(GameClientDirectoryPolicy.issue(for: china, client: .starRailGlobal, locations: locations) != nil)
    #expect(GameClientDirectoryPolicy.issue(for: china.appending(path: "Global"), client: .starRailGlobal, locations: locations) != nil)
    #expect(GameClientDirectoryPolicy.issue(for: root.appending(path: "Global"), client: .starRailGlobal, locations: locations) == nil)
    let link = root.appending(path: "link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: china)
    #expect(GameClientDirectoryPolicy.issue(for: link, client: .starRailGlobal, locations: []) != nil)
  }

  @Test func maintenanceTasksNeverBecomeIncompleteDownloadCleanup() throws {
    let name = "CleanupTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let key = "games.zenlessZoneZero-global."
    defaults.set("/Users/player/Games/Zenless Global", forKey: key + "pendingInstall")
    for operation in ["update", "repair", "unknown"] {
      defaults.set(operation, forKey: key + "pendingOperation")
      #expect(GameClientDirectoryPolicy.cleanupTarget(client: .zenlessZoneZeroGlobal, defaults: defaults, locations: []) == nil)
    }
    defaults.set("install", forKey: key + "pendingOperation")
    #expect(GameClientDirectoryPolicy.cleanupTarget(client: .zenlessZoneZeroGlobal, defaults: defaults, locations: []) != nil)
    #expect(GameClientDirectoryPolicy.cleanupTarget(client: .zenlessZoneZero, defaults: defaults, locations: []) == nil)
  }

  @Test @MainActor func cleanupRequiresExactIncompleteBackendIdentity() {
    let path = "Z:\\Games\\Global"
    let valid: [String: Any] = ["gameBiz": "nap_global", "package": "", "status": "need_install", "installPath": path]
    #expect(OfficialGameInstaller.permitsIncompleteCleanup(valid, game: .zenlessZoneZeroGlobal, windowsPath: path))
    #expect(!OfficialGameInstaller.permitsIncompleteCleanup(valid, game: .zenlessZoneZero, windowsPath: path))
    #expect(!OfficialGameInstaller.permitsIncompleteCleanup(valid, game: .zenlessZoneZeroGlobal, windowsPath: path + "Other"))
    for status in ["ready", "need_update", "verifying", "", "unknown"] {
      var changed = valid; changed["status"] = status
      #expect(!OfficialGameInstaller.permitsIncompleteCleanup(changed, game: .zenlessZoneZeroGlobal, windowsPath: path))
    }
    #expect(!OfficialGameInstaller.permitsIncompleteCleanup(nil, game: .zenlessZoneZeroGlobal, windowsPath: path))
  }

  @Test func usageIncludesPartialAndHiddenFilesButNotLinkedOtherClient() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let game = root.appending(path: "game")
    try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
    try Data(repeating: 4, count: 10_000).write(to: game.appending(path: ".partial"))
    let before = try #require(try GameDiskUsage.measure(game))
    #expect(before.bytes > 0)
    let other = root.appending(path: "other")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try Data(repeating: 7, count: 100_000).write(to: other.appending(path: "keep"))
    try FileManager.default.createSymbolicLink(at: game.appending(path: "linked"), withDestinationURL: other)
    let after = try #require(try GameDiskUsage.measure(game))
    #expect(after.bytes == before.bytes)
    #expect(try Data(contentsOf: other.appending(path: "keep")).count == 100_000)
  }
}
