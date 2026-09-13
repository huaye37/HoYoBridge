import Foundation
import Testing

@testable import BridgeCore

struct GPTKDetectorTests {
  @Test
  func explicitEnvironmentPathTakesPriority() {
    let status = GPTKDetector.detect(
      environment: ["GPTK_HOME": "/custom/gptk"],
      candidates: ["/fallback/gptk"],
      fileExists: { $0 == "/custom/gptk" },
      versionAtPath: { _ in "4.0" }
    )

    #expect(status.availability == .installed)
    #expect(status.path == "/custom/gptk")
    #expect(status.version == "4.0")
  }

  @Test
  func reportsMissingWhenNoCandidateExists() {
    let status = GPTKDetector.detect(
      environment: [:],
      candidates: ["/missing/gptk"],
      fileExists: { _ in false }
    )

    #expect(status.availability == .missing)
    #expect(status.path == nil)
  }

  @Test
  func readsVersionFromAFrameworkVersionsDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "MacGameBridge-GPTKDetectorTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = root.appending(
      path: "D3DMetal.framework/Versions/A/Resources",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: root.appending(path: "D3DMetal.framework/Versions/Current").path,
      withDestinationPath: "A"
    )
    let info = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleShortVersionString": "4.0b2"],
      format: .xml,
      options: 0
    )
    try info.write(to: resources.appending(path: "Info.plist"))

    #expect(
      GPTKDetector.detectedVersion(
        at: root.appending(path: "D3DMetal.framework").path
      ) == "4.0b2")
  }
}
