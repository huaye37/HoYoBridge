import Foundation
import Testing
@testable import BridgeStatus

/// Destructive integration test, disabled unless an exact game directory is explicitly supplied.
@MainActor
struct OfficialEngineLiveTests {
  @Test func uninstallExplicitlyAuthorizedHonkaiInstallation() async throws {
    guard let path = ProcessInfo.processInfo.environment["HOYOBRIDGE_TEST_UNINSTALL_BH3_PATH"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    #expect(directory.lastPathComponent == "HonkaiImpact3")
    guard directory.lastPathComponent == "HonkaiImpact3" else { return }
    let service = OfficialGameInstaller(resourceURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appending(path: "dist/HoYoBridge.app/Contents/Resources"))
    let result = await service.uninstall(.honkaiImpact3, expectedDirectory: directory)
    #expect(result, Comment(rawValue: service.messages[.honkaiImpact3] ?? "No result"))
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "BH3.exe").path))
  }
}
