import Testing
import Foundation
@testable import BridgeStatus

@MainActor
struct OfficialGameMaintenanceTests {
  @Test func engineMustBelongToExactInstallerPrefix() {
    let prefix = "/Users/player/Library/Application Support/MacGameBridge/Installer/prefix"
    #expect(OfficialEngineOwnership.matches("wine HYP.exe WINEPREFIX=\(prefix) LANG=zh_CN.UTF-8", prefix: prefix))
    #expect(!OfficialEngineOwnership.matches("wine HYP.exe WINEPREFIX=\(prefix)-other LANG=C", prefix: prefix))
    #expect(!OfficialEngineOwnership.matches("wine HYP.exe LANG=C", prefix: prefix))
    let executable = prefix + "/drive_c/MacGameBridge/miHoYo Launcher/1.18.0.380/HYP.exe"
    #expect(OfficialEngineOwnership.matchesExecutable(executable, prefix: prefix))
    #expect(!OfficialEngineOwnership.matchesExecutable(executable, prefix: prefix + "-other"))
    #expect(!OfficialEngineOwnership.matchesExecutable("/Applications/HYP.exe", prefix: prefix))
    #expect(!OfficialEngineOwnership.matchesExecutable(nil, prefix: prefix))
  }
  @Test func interruptedUninstallOnlyRestoresExactReadyInstallation() {
    let record: [String: Any] = ["gameBiz": "hkrpg_cn", "status": "ready", "installPath": "Z:\\Games\\StarRail"]
    #expect(OfficialGameInstaller.uninstallCanBeRestored(record, gameBiz: "hkrpg_cn", path: "/Games/StarRail"))
    #expect(!OfficialGameInstaller.uninstallCanBeRestored(record, gameBiz: "bh3_cn", path: "/Games/StarRail"))
    #expect(!OfficialGameInstaller.uninstallCanBeRestored(record, gameBiz: "hkrpg_cn", path: "/Games/Other"))
    #expect(!OfficialGameInstaller.uninstallCanBeRestored(nil, gameBiz: "hkrpg_cn", path: "/Games/StarRail"))
    var unknown = record
    unknown["status"] = "uninstalling"
    #expect(!OfficialGameInstaller.uninstallCanBeRestored(unknown, gameBiz: "hkrpg_cn", path: "/Games/StarRail"))
  }
  @Test func offlineDiskIsNotAnUninstalledGame() {
    let external = URL(fileURLWithPath: "/Volumes/Lucian/Games/StarRail")
    #expect(MiHoYoGame.isInstallationDiskOffline(external, mountedVolumes: []))
    #expect(!MiHoYoGame.isInstallationDiskOffline(external, mountedVolumes: [URL(fileURLWithPath: "/Volumes/Lucian")]))
    #expect(MiHoYoGame.isInstallationDiskOffline(external, mountedVolumes: [URL(fileURLWithPath: "/Volumes/Lucian2")]))
    #expect(!MiHoYoGame.isInstallationDiskOffline(URL(fileURLWithPath: "/Users/player/Games/StarRail"), mountedVolumes: []))
    #expect(!MiHoYoGame.isInstallationDiskOffline(nil, mountedVolumes: []))
  }
  @Test func operationLabelsAreDistinct() {
    #expect(OfficialGameInstaller.Operation.install.label == "下载")
    #expect(OfficialGameInstaller.Operation.update.label == "更新")
    #expect(OfficialGameInstaller.Operation.repair.label == "修复")
  }
  @Test func outstandingTaskSurvivesServiceRestart() throws {
    let name = "OutstandingTaskTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("/fixture/StarRail", forKey: "games.starRail.pendingInstall")
    let reloaded = try #require(UserDefaults(suiteName: name))
    #expect(OfficialGameInstaller.outstandingGames(defaults: reloaded) == [.starRail])
    defaults.set("/fixture/BH3", forKey: "games.honkaiImpact3.pendingUninstall")
    #expect(OfficialGameInstaller.outstandingGames(defaults: reloaded) == [.starRail, .honkaiImpact3])
    defaults.set(true, forKey: "games.starRail.taskDetached")
    #expect(OfficialGameInstaller.outstandingGames(defaults: reloaded) == [.honkaiImpact3])
    #expect(reloaded.string(forKey: "games.starRail.pendingInstall") == "/fixture/StarRail")
    defaults.removeObject(forKey: "games.starRail.taskDetached")
    #expect(OfficialGameInstaller.outstandingGames(defaults: reloaded) == [.starRail, .honkaiImpact3])
    defaults.removeObject(forKey: "games.starRail.pendingInstall")
    #expect(OfficialGameInstaller.outstandingGames(defaults: reloaded) == [.honkaiImpact3])
  }

  @Test func unknownOrActiveTaskCannotBeResubmitted() {
    for status: String? in [nil, "progressing", "verifying", "success", "unknown", ""] {
      #expect(!OfficialGameInstaller.permitsResubmission(after: status))
    }
    #expect(OfficialGameInstaller.permitsResubmission(after: "cancelled"))
    #expect(OfficialGameInstaller.permitsResubmission(after: "failed"))
  }

  @Test func originalRuntimeFailureIsVisible() {
    #expect(MiHoYoGameLaunchService.runtimePreparationIssue(.failed("磁盘空间不足")).contains("磁盘空间不足"))
    #expect(MiHoYoGameLaunchService.runtimePreparationIssue(.unavailable("缺少运行组件")).contains("缺少运行组件"))
  }
  @Test func officialDiscoveryRetainsRequiredPackageAndVersion() {
    let path = "Z:\\Games\\StarRail"
    let candidate: [String: Any] = ["gameBiz": "hkrpg_cn", "path": path, "package": "", "version": "4.5.0", "isFindDir": true, "pathAvailable": true, "errorCode": 0]
    let found = OfficialGameInstaller.matchingInstallation([candidate], biz: "hkrpg_cn", path: path)
    #expect(found?["package"] as? String == "")
    #expect(found?["version"] as? String == "4.5.0")
    #expect(OfficialGameInstaller.matchingInstallation([candidate], biz: "bh3_cn", path: path) == nil)
    #expect(OfficialGameInstaller.matchingInstallation([candidate], biz: "hkrpg_cn", path: "Z:\\Other") == nil)
    var incomplete = candidate
    incomplete.removeValue(forKey: "package")
    #expect(OfficialGameInstaller.matchingInstallation([incomplete], biz: "hkrpg_cn", path: path) == nil)
  }
  @Test func associationOnlyAdoptsExplicitlyUnregisteredGame() {
    let path = "Z:\\Games\\StarRail"
    #expect(OfficialGameInstaller.directoryStatus(["gameBiz": "hkrpg_cn", "installPath": "", "status": "need_get_game"], biz: "hkrpg_cn", expected: path) == .unregistered)
    #expect(OfficialGameInstaller.directoryStatus(["gameBiz": "hkrpg_cn", "installPath": path], biz: "hkrpg_cn", expected: path) == .linked)
    #expect(OfficialGameInstaller.directoryStatus(["gameBiz": "hkrpg_cn", "installPath": "Z:\\Other"], biz: "hkrpg_cn", expected: path) == .conflict)
    #expect(OfficialGameInstaller.directoryStatus(["gameBiz": "hkrpg_cn", "installPath": "", "status": "loading"], biz: "hkrpg_cn", expected: path) == .unavailable)
    #expect(OfficialGameInstaller.directoryStatus(nil, biz: "hkrpg_cn", expected: path) == .unavailable)
    #expect(OfficialGameInstaller.directoryStatus(["gameBiz": "bh3_cn", "installPath": "", "status": "need_get_game"], biz: "hkrpg_cn", expected: path) == .unavailable)
  }
  @Test func playerDefaultsAreIndependentAndNotTrialDirectories() {
    let games: [MiHoYoGame] = [.genshin, .starRail, .zenlessZoneZero, .honkaiImpact3]
    let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Games/HoYoBridge")
    #expect(Set(games.map { $0.defaultDirectory.path }).count == 4)
    for game in games {
      #expect(game.defaultDirectory.deletingLastPathComponent().path == root.path)
      #expect(!game.defaultDirectory.pathComponents.contains("Trials"))
    }
  }
  @Test func interruptedTaskSurvivesReloadAndIsIsolated() throws {
    let name = "OfficialGameMaintenanceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let key = "games.starRail."
    #expect(OfficialGameInstaller.pendingOperation(for: .starRail, defaults: defaults) == nil)
    defaults.set("repair", forKey: key + "pendingOperation")
    #expect(OfficialGameInstaller.pendingOperation(for: .starRail, defaults: defaults) == nil)
    defaults.set("/test/StarRail", forKey: key + "pendingInstall")
    let reloaded = try #require(UserDefaults(suiteName: name))
    #expect(OfficialGameInstaller.pendingOperation(for: .starRail, defaults: reloaded) == .repair)
    #expect(OfficialGameInstaller.pendingOperation(for: .honkaiImpact3, defaults: reloaded) == nil)
    defaults.set("update", forKey: key + "pendingOperation")
    #expect(OfficialGameInstaller.pendingOperation(for: .starRail, defaults: defaults) == .update)
    defaults.removeObject(forKey: key + "pendingOperation")
    #expect(OfficialGameInstaller.pendingOperation(for: .starRail, defaults: defaults) == .install)
  }
  @Test func successfulStates() {
    #expect(OfficialGameInstaller.updateStatus(["result": "success", "status": "ready"]) == .current)
    #expect(OfficialGameInstaller.updateStatus(["result": "success", "status": "need_update"]) == .available)
  }

  @Test func unknownIsNeverLatest() {
    for status in ["need_install", "need_get_game", "waiting", "unexpected", ""] {
      #expect(OfficialGameInstaller.updateStatus(["result": "success", "status": status]) == .unknown)
    }
    #expect(OfficialGameInstaller.updateStatus(["status": "ready"]) == .unknown)
    #expect(OfficialGameInstaller.updateStatus(["result": "failed", "status": "ready"]) == .unknown)
    #expect(OfficialGameInstaller.updateStatus([:]) == .unknown)
  }
}
