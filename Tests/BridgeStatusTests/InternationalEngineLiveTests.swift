import Foundation
import Testing
@testable import BridgeStatus

@MainActor
struct InternationalEngineLiveTests {
  @Test func cancelsAndCleansIsolatedRealPartialDownload() async throws {
    guard ProcessInfo.processInfo.environment["MGB_TEST_GLOBAL_CLEANUP"] == "1" else { return }
    let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let root = project.appending(path: "LocalRuntimes/Experiments/global-cleanup-validation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let name = "GlobalCleanupLive.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let target = root.appending(path: "HonkaiGlobal-\(UUID().uuidString)", directoryHint: .isDirectory)
    let engine = OfficialGameInstaller(resourceURL: project.appending(path: "dist/public-update-0.1.7/HoYoBridge.app/Contents/Resources"),
      region: .global, storageRoot: root, port: 19235,
      engineArchive: project.appending(path: "LocalRuntimes/Downloads/HoYoPlay-1.18.0.380-global.exe"), defaults: defaults)
    do {
      try await engine.startIsolatedDiagnosticDownload(.honkaiImpact3Global, directory: target)
      print("GLOBAL_PARTIAL_CREATED \(FileManager.default.fileExists(atPath: target.path))")
      // The launcher updater must release a paused engine without clearing its files or resume state.
      #expect(engine.paused.contains(.honkaiImpact3Global))
      let before = try FileManager.default.contentsOfDirectory(atPath: target.path).sorted()
      #expect(try await engine.preparePausedDownloadsForUpdate())
      #expect(!engine.isOccupied)
      #expect(defaults.string(forKey: "games.honkaiImpact3-global.pendingInstall") == target.path)
      #expect(defaults.bool(forKey: "games.honkaiImpact3-global.taskDetached"))
      #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).sorted() == before)
      print("GLOBAL_PAUSED_UPDATE_HANDOFF files-and-resume-record-preserved")
      print("GLOBAL_ENGINE_ALREADY_STOPPED true")
      let cleaned = await engine.discardIncompleteDownload(.honkaiImpact3Global, expectedDirectory: target)
      #expect(cleaned, Comment(rawValue: engine.messages[.honkaiImpact3Global] ?? "No cleanup result"))
      #expect(!FileManager.default.fileExists(atPath: target.path))
      print("GLOBAL_PARTIAL_CLEANUP \(cleaned)")
      try await engine.stopIsolatedDiagnosticEngine()
    } catch {
      try? await engine.stopIsolatedDiagnosticEngine()
      throw error
    }
  }

  @Test func readsAllFourPackagesUsingIsolatedOfficialEngine() async throws {
    guard ProcessInfo.processInfo.environment["MGB_TEST_GLOBAL_ENGINE"] == "1" else { return }
    let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let root = project.appending(path: "LocalRuntimes/Experiments/global-engine-validation")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let engine = OfficialGameInstaller(resourceURL: project.appending(path: "dist/public-update-0.1.7/HoYoBridge.app/Contents/Resources"),
      region: .global, storageRoot: root, port: 19234,
      engineArchive: project.appending(path: "LocalRuntimes/Downloads/HoYoPlay-1.18.0.380-global.exe"))
    do {
      for base in MiHoYoGame.navigationGames {
        let game = base.client(in: .global)
        let result = try await engine.inspectInstallMetadata(game, directory: root.appending(path: game.rawValue))
        #expect(result["result"] as? String == "success", Comment(rawValue: game.rawValue + ": " + String(describing: result["result"])))
        #expect(result["gamePackage"] is [String: Any], Comment(rawValue: game.rawValue))
        print("GLOBAL_METADATA \(game.officialBiz) package=\(game.officialPackage) result=\(result["result"] ?? "nil")")
      }
      try await engine.stopIsolatedDiagnosticEngine()
    } catch {
      try? await engine.stopIsolatedDiagnosticEngine()
      throw error
    }
  }
}
