import Foundation
import Testing
@testable import BridgeStatus

@MainActor
struct IncompleteDownloadCleanupTests {
  @Test func confirmedCleanupRemovesOnlyIncompleteClientAndRetainsOtherRecords() async throws {
    let name = "CleanupFlow.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let partial = root.appending(path: "ZZZ Global")
    let installed = root.appending(path: "ZZZ CN")
    for url in [partial, installed] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    try Data("partial".utf8).write(to: partial.appending(path: "download.tmp"))
    try Data("keep".utf8).write(to: installed.appending(path: "ZenlessZoneZero.exe"))
    defaults.set(partial.path, forKey: "games.zenlessZoneZero-global.pendingInstall")
    defaults.set("install", forKey: "games.zenlessZoneZero-global.pendingOperation")
    MiHoYoGame.zenlessZoneZero.saveDirectory(installed, defaults: defaults)
    let path = "Z:" + partial.path.replacingOccurrences(of: "/", with: "\\")
    var removed = false
    var stops = 0
    let commands = OfficialEngineCommands(query: { action, arguments in
      #expect(arguments["gameBiz"] as? String == "nap_global")
      if action == "uninstallGame" {
        #expect(stops == 1)
        #expect(arguments["path"] as? String == path)
        try FileManager.default.removeItem(at: partial)
        removed = true
        return ["result": "success"]
      }
      #expect(action == "getLocalGameInfo")
      return [["gameBiz": "nap_global", "package": "", "installPath": removed ? "" : path,
        "status": removed ? "need_get_game" : "need_install"]]
    }, stop: { stops += 1 })
    let service = OfficialGameInstaller(region: .global, storageRoot: root, defaults: defaults, commands: commands)
    #expect(service.canDiscardDownload(.zenlessZoneZeroGlobal))
    let success = await service.discardIncompleteDownload(.zenlessZoneZeroGlobal, expectedDirectory: partial)
    #expect(success)
    #expect(stops == 2)
    #expect(!FileManager.default.fileExists(atPath: partial.path))
    #expect(try Data(contentsOf: installed.appending(path: "ZenlessZoneZero.exe")) == Data("keep".utf8))
    #expect(MiHoYoGame.zenlessZoneZero.configuredDirectory(defaults: defaults)?.path == installed.path)
    #expect(OfficialGameInstaller.pendingOperation(for: .zenlessZoneZeroGlobal, defaults: defaults) == nil)
  }

  @Test(arguments: ["ready", "need_update", "unknown", "need_install"])
  func mismatchOrCompletedGameCannotBeDeleted(status: String) async throws {
    let name = "CleanupReject.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appending(path: "Game")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: target.appending(path: "partial"))
    defaults.set(target.path, forKey: "games.genshin-global.pendingInstall")
    defaults.set("install", forKey: "games.genshin-global.pendingOperation")
    var uninstallCalled = false
    let commands = OfficialEngineCommands(query: { action, _ in
      if action == "uninstallGame" { uninstallCalled = true }
      let path = "Z:" + target.path.replacingOccurrences(of: "/", with: "\\")
      return [["gameBiz": "hk4e_global", "package": "", "status": status,
        "installPath": path + (status == "need_install" ? "-different" : "")]]
    }, stop: {})
    let service = OfficialGameInstaller(region: .global, storageRoot: root, defaults: defaults, commands: commands)
    #expect(await service.discardIncompleteDownload(.genshinGlobal, expectedDirectory: target) == false)
    #expect(!uninstallCalled)
    #expect(defaults.string(forKey: "games.genshin-global.pendingInstall") == target.path)
    #expect(try Data(contentsOf: target.appending(path: "partial")) == Data("keep".utf8))
  }
}
