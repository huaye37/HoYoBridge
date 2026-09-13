import Foundation
import Testing

@testable import BridgeStatus

@Suite("Game storage")
struct GameStorageTests {
  @Test(
    "cross-volume migration on a mounted APFS validation volume",
    .enabled(if: ProcessInfo.processInfo.environment["MGB_TEST_STORAGE_VOLUME"] != nil)
  )
  func crossVolume() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let mounted = URL(
      fileURLWithPath: try #require(ProcessInfo.processInfo.environment["MGB_TEST_STORAGE_VOLUME"]))
    let destination = mounted.appending(path: "mgb-test-\(UUID())")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: destination) }
    let selection = try InstallVolumeProbe.inspect(destination, isDefaultPreview: false)
    #expect(selection.fileSystemName == "apfs")
    #expect(selection.supportsCloning)
    #expect(!selection.isNetwork)
    let result = try await GameStorageManager.migrate(source: fixture.game, to: destination)
    #expect(
      try Data(contentsOf: result.appending(path: "YuanShen_Data/payload"))
        == Data(contentsOf: fixture.game.appending(path: "YuanShen_Data/payload")))
    #expect(result.path.hasPrefix(mounted.path + "/"))
  }

  private func fixture() throws -> (root: URL, game: URL, destination: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "mgb-storage-test-\(UUID())")
    let game = root.appending(path: "原神 自定义目录")
    let destination = root.appending(path: "目标磁盘")
    try FileManager.default.createDirectory(
      at: game.appending(path: "YuanShen_Data/empty"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    try Data("executable".utf8).write(to: game.appending(path: "YuanShen.exe"))
    try Data("game_version=7.0.0\n".utf8).write(to: game.appending(path: "config.ini"))
    try Data(repeating: 42, count: 5 * 1024 * 1024).write(
      to: game.appending(path: "YuanShen_Data/payload"))
    return (root, game, destination)
  }

  @Test("migration verifies bytes, preserves custom name, empty directories and original")
  func migration() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await GameStorageManager.migrate(source: fixture.game, to: fixture.destination)
    #expect(result.lastPathComponent == fixture.game.lastPathComponent)
    #expect(try GameStorageManager.recognize(result) == result)
    #expect(
      FileManager.default.fileExists(atPath: result.appending(path: "YuanShen_Data/empty").path))
    for path in ["YuanShen.exe", "config.ini", "YuanShen_Data/payload"] {
      #expect(
        try Data(contentsOf: result.appending(path: path))
          == Data(contentsOf: fixture.game.appending(path: path)))
    }
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path) == [
        fixture.game.lastPathComponent
      ])
  }

  @Test("existing destination is never overwritten")
  func destinationConflict() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let occupied = fixture.destination.appending(path: fixture.game.lastPathComponent)
    try Data("keep".utf8).write(to: occupied)
    await #expect(throws: GameStorageError.self) {
      try await GameStorageManager.migrate(source: fixture.game, to: fixture.destination)
    }
    #expect(try Data(contentsOf: occupied) == Data("keep".utf8))
  }

  @Test("destination inside source is rejected")
  func nestedDestination() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    await #expect(throws: GameStorageError.self) {
      try await GameStorageManager.migrate(source: fixture.game, to: fixture.game)
    }
  }

  @Test("symlinks are rejected without following them")
  func symlink() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try FileManager.default.createSymbolicLink(
      at: fixture.game.appending(path: "external"), withDestinationURL: fixture.destination)
    await #expect(throws: GameStorageError.self) {
      try await GameStorageManager.migrate(source: fixture.game, to: fixture.destination)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
  }

  @Test("cancellation removes staging and preserves original")
  func cancellation() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let worker = Task {
      try await GameStorageManager.migrate(source: fixture.game, to: fixture.destination) {
        progress in
        if progress.completedBytes > 0 { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    await #expect(throws: CancellationError.self) { try await worker.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
    #expect(
      try GameStorageManager.recognize(fixture.game) == fixture.game.resolvingSymlinksInPath())
  }

  @Test("source changes prevent publication")
  func sourceChange() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    await #expect(throws: GameStorageError.self) {
      try await GameStorageManager.migrate(source: fixture.game, to: fixture.destination) {
        progress in
        if progress.phase == "正在校验新副本" {
          try? Data("changed externally".utf8).write(to: fixture.game.appending(path: "config.ini"))
        }
      }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
  }

  @Test("destination corruption fails verification")
  func corruptedCopy() async throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    await #expect(throws: GameStorageError.self) {
      try await GameStorageManager.migrate(source: fixture.game, to: fixture.destination) {
        progress in
        if progress.phase == "正在校验新副本",
          let staging = try? FileManager.default.contentsOfDirectory(
            at: fixture.destination, includingPropertiesForKeys: nil
          ).first
        {
          try? Data("corrupted".utf8).write(to: staging.appending(path: "YuanShen.exe"))
        }
      }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
  }

  @Test("recognition requires data directory, and update adoption keeps existing marker")
  func recognitionAndMarker() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    #expect(throws: (any Error).self) { try GameStorageManager.recognize(fixture.destination) }
    let marker = fixture.game.appending(path: ".mgb-managed-cn-download")
    try GameStorageManager.prepareManagedMarker(at: fixture.game)
    #expect(try String(contentsOf: marker, encoding: .utf8).contains("state=imported"))
    try Data("keep-existing-marker".utf8).write(to: marker)
    try GameStorageManager.prepareManagedMarker(at: fixture.game)
    #expect(try Data(contentsOf: marker) == Data("keep-existing-marker".utf8))
  }

  @MainActor
  @Test("saved custom game directory survives parent refresh")
  func savedCustomPath() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let selection = try InstallVolumeProbe.inspect(fixture.root, isDefaultPreview: false)
    #expect(
      GameInstallationService.targetURL(for: selection, savedRoot: fixture.game) == fixture.game)
    #expect(GameInstallationService.targetURL(for: nil, savedRoot: fixture.game) == fixture.game)
    let preview = try InstallVolumeProbe.inspect(fixture.root, isDefaultPreview: true)
    #expect(GameInstallationService.targetURL(for: preview, savedRoot: fixture.game) == fixture.game)
    #expect(GameInstallationService.targetURL(for: preview, savedRoot: nil) == MiHoYoGame.genshin.defaultDirectory)
    #expect(!selection.fileSystemName.isEmpty)
    #expect(selection.isWritable)
  }

  @Test("offline external disk never falls back to internal free space")
  func offlineDisk() {
    #expect(throws: InstallVolumeProbeError.self) {
      try GameInstallationService.liveInitialInstallReadiness(
        at: URL(fileURLWithPath: "/Volumes/mgb-offline-\(UUID())/Games"))
    }
  }

  @Test("network and non-cloning disks disclose update limitations")
  func volumeAdvice() {
    var volume = InstallVolumeSelection(
      url: URL(fileURLWithPath: "/tmp"), volumeName: "test", freeDiskBytes: 0,
      isDefaultPreview: false)
    volume.isNetwork = true
    #expect(volume.storageAdvice.contains("网络盘"))
    #expect(volume.storageAdvice.contains("更新前"))
    volume.isNetwork = false
    #expect(volume.storageAdvice.contains("不支持 APFS"))
    volume.isWritable = false
    #expect(volume.storageAdvice.contains("不可写"))
  }
}
