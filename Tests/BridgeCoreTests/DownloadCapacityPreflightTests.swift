import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

struct DownloadCapacityPreflightTests {
  private let downloadRootURL = URL(fileURLWithPath: "/test/downloads", isDirectory: true)
  private let artifactStoreRootURL = URL(fileURLWithPath: "/test/store", isDirectory: true)

  @Test
  func sameVolumeIncludesPartialRemainderStagingAndMarginAtExactCapacity() throws {
    let preflight = makePreflight(
      safetyMarginBytes: 10,
      downloadCapacity: capacity(deviceID: 1, availableBytes: 170),
      artifactStoreCapacity: capacity(deviceID: 1, availableBytes: 170)
    )

    try preflight.check(
      downloadRootURL: downloadRootURL,
      artifactStoreRootURL: artifactStoreRootURL,
      expectedByteCount: 100,
      partialByteCount: 40
    )
  }

  @Test
  func separateVolumesAreCheckedIndependentlyAtExactCapacity() throws {
    let preflight = makePreflight(
      safetyMarginBytes: 10,
      downloadCapacity: capacity(deviceID: 1, availableBytes: 70),
      artifactStoreCapacity: capacity(deviceID: 2, availableBytes: 110)
    )

    try preflight.check(
      downloadRootURL: downloadRootURL,
      artifactStoreRootURL: artifactStoreRootURL,
      expectedByteCount: 100,
      partialByteCount: 40
    )
  }

  @Test
  func separateVolumesRejectEitherInsufficientVolume() {
    let downloadInsufficient = makePreflight(
      safetyMarginBytes: 10,
      downloadCapacity: capacity(deviceID: 1, availableBytes: 69),
      artifactStoreCapacity: capacity(deviceID: 2, availableBytes: 110)
    )
    #expect(
      throws: DownloadCapacityPreflightError.insufficientCapacity(
        scope: .download,
        required: 70,
        available: 69
      )
    ) {
      try downloadInsufficient.check(
        downloadRootURL: downloadRootURL,
        artifactStoreRootURL: artifactStoreRootURL,
        expectedByteCount: 100,
        partialByteCount: 40
      )
    }

    let artifactStoreInsufficient = makePreflight(
      safetyMarginBytes: 10,
      downloadCapacity: capacity(deviceID: 1, availableBytes: 70),
      artifactStoreCapacity: capacity(deviceID: 2, availableBytes: 109)
    )
    #expect(
      throws: DownloadCapacityPreflightError.insufficientCapacity(
        scope: .artifactStore,
        required: 110,
        available: 109
      )
    ) {
      try artifactStoreInsufficient.check(
        downloadRootURL: downloadRootURL,
        artifactStoreRootURL: artifactStoreRootURL,
        expectedByteCount: 100,
        partialByteCount: 40
      )
    }
  }

  @Test
  func rejectsAdditionAndAvailableByteMultiplicationOverflow() {
    let additionOverflow = makePreflight(
      safetyMarginBytes: 1,
      downloadCapacity: capacity(deviceID: 1, availableBytes: UInt64.max),
      artifactStoreCapacity: capacity(deviceID: 1, availableBytes: UInt64.max)
    )
    #expect(
      throws: DownloadCapacityPreflightError.arithmeticOverflow(scope: .sharedVolume)
    ) {
      try additionOverflow.check(
        downloadRootURL: downloadRootURL,
        artifactStoreRootURL: artifactStoreRootURL,
        expectedByteCount: UInt64.max,
        partialByteCount: UInt64.max
      )
    }

    let multiplicationOverflow = makePreflight(
      safetyMarginBytes: 0,
      downloadCapacity: DownloadFileSystemCapacity(
        deviceID: 1,
        availableBlocks: UInt64.max,
        blockSize: 2
      ),
      artifactStoreCapacity: capacity(deviceID: 1, availableBytes: UInt64.max)
    )
    #expect(
      throws: DownloadCapacityPreflightError.arithmeticOverflow(scope: .download)
    ) {
      try multiplicationOverflow.check(
        downloadRootURL: downloadRootURL,
        artifactStoreRootURL: artifactStoreRootURL,
        expectedByteCount: 1,
        partialByteCount: 0
      )
    }
  }

  @Test
  func rejectsInvalidPartialByteCountWithoutUnderflow() {
    let preflight = makePreflight(
      safetyMarginBytes: 0,
      downloadCapacity: capacity(deviceID: 1, availableBytes: 1),
      artifactStoreCapacity: capacity(deviceID: 1, availableBytes: 1)
    )

    #expect(
      throws: DownloadCapacityPreflightError.invalidPartialByteCount(
        expected: 1,
        actual: 2
      )
    ) {
      try preflight.check(
        downloadRootURL: downloadRootURL,
        artifactStoreRootURL: artifactStoreRootURL,
        expectedByteCount: 1,
        partialByteCount: 2
      )
    }
  }

  @Test
  func systemProviderRequiresAnExistingDirectoryAndDoesNotExposeItsPath() {
    let sensitiveComponent = "secret-token-\(UUID().uuidString)"
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(sensitiveComponent, isDirectory: true)
    let preflight = DownloadCapacityPreflight(
      safetyMarginBytes: 0,
      capacityProvider: .system
    )

    do {
      try preflight.check(
        downloadRootURL: missingURL,
        artifactStoreRootURL: artifactStoreRootURL,
        expectedByteCount: 1,
        partialByteCount: 0
      )
      Issue.record("Expected the missing directory to be rejected")
    } catch let error as DownloadCapacityPreflightError {
      #expect(
        error
          == .directoryUnavailable(
            scope: .download,
            code: ENOENT
          )
      )
      #expect(!String(reflecting: error).contains(sensitiveComponent))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func downloaderChecksCapacityBeforeStartingTransport() async throws {
    CapacityPreflightURLProtocol.reset()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacGameBridgeCapacityTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapacityPreflightURLProtocol.self]
    let unavailableCapacity = capacity(deviceID: 1, availableBytes: 0)
    let downloader = ManagedArtifactDownloader(
      downloadRootURL: directory.appendingPathComponent("downloads", isDirectory: true),
      allowedHosts: ["downloads.example.invalid"],
      configuration: configuration,
      capacitySafetyMarginBytes: 0,
      capacityProvider: DownloadCapacityProvider { _ in unavailableCapacity }
    )
    let sensitiveSourceURL =
      "https://downloads.example.invalid/runtime.bin?token=do-not-expose"
    let runtime = RuntimeDefinition(
      id: "capacity-runtime",
      backend: .dxmt,
      version: "1.0.0",
      verification: .candidate,
      acquisition: .managedDownload,
      sourceURL: sensitiveSourceURL,
      byteSize: 10,
      sha256: String(repeating: "a", count: 64),
      license: "MIT",
      redistributable: true
    )

    do {
      _ = try await downloader.download(
        runtime: runtime,
        into: ContentAddressedArtifactStore(
          rootURL: directory.appendingPathComponent("store", isDirectory: true)
        )
      )
      Issue.record("Expected insufficient capacity")
    } catch let error as DownloadCapacityPreflightError {
      #expect(
        error
          == .insufficientCapacity(
            scope: .sharedVolume,
            required: 20,
            available: 0
          )
      )
      #expect(!String(reflecting: error).contains(sensitiveSourceURL))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(!CapacityPreflightURLProtocol.hasStarted)
  }

  @Test
  func downloaderPreservesValidResumeWhenStoreRootPreparationFails() async throws {
    CapacityPreflightURLProtocol.reset()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "MacGameBridgeCapacityResumeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let downloadRoot = directory.appendingPathComponent("downloads", isDirectory: true)
    let partialDirectory = downloadRoot.appendingPathComponent(".partial", isDirectory: true)
    for path in [downloadRoot, partialDirectory] {
      try FileManager.default.createDirectory(
        at: path,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    }

    let completeData = Data("resumable-capacity-check".utf8)
    let prefix = Data(completeData.prefix(5))
    let artifactHash = sha256(completeData)
    let sourceURL = "https://downloads.example.invalid/runtime.bin"
    let sourceDigest = sha256(Data(sourceURL.utf8))
    let partialURL = partialDirectory.appendingPathComponent("\(artifactHash).part")
    let metadataURL = partialDirectory.appendingPathComponent("\(artifactHash).resume.json")
    try prefix.write(to: partialURL)
    let metadata: [String: Any] = [
      "schemaVersion": 1,
      "sourceURLSHA256": sourceDigest,
      "finalURLSHA256": sourceDigest,
      "expectedSize": completeData.count,
      "expectedSHA256": artifactHash,
      "byteCount": prefix.count,
      "validator": ["kind": "strongETag", "value": "\"v1\""],
    ]
    try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
    for path in [partialURL, metadataURL] {
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    let unsafeStore = directory.appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: unsafeStore, withIntermediateDirectories: false)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: unsafeStore.path)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapacityPreflightURLProtocol.self]
    let downloader = ManagedArtifactDownloader(
      downloadRootURL: downloadRoot,
      allowedHosts: ["downloads.example.invalid"],
      configuration: configuration,
      capacitySafetyMarginBytes: 0,
      capacityProvider: DownloadCapacityProvider { _ in
        DownloadFileSystemCapacity(deviceID: 1, availableBlocks: UInt64.max, blockSize: 1)
      }
    )
    let runtime = RuntimeDefinition(
      id: "resume-capacity-runtime",
      backend: .dxmt,
      version: "1.0.0",
      verification: .candidate,
      acquisition: .managedDownload,
      sourceURL: sourceURL,
      byteSize: UInt64(completeData.count),
      sha256: artifactHash,
      license: "MIT",
      redistributable: true
    )

    await #expect(throws: ArtifactStoreError.unsafeCacheDirectory(unsafeStore.path)) {
      try await downloader.download(
        runtime: runtime,
        into: .init(rootURL: unsafeStore)
      )
    }
    #expect(FileManager.default.fileExists(atPath: partialURL.path))
    #expect(FileManager.default.fileExists(atPath: metadataURL.path))
    #expect(!CapacityPreflightURLProtocol.hasStarted)
  }

  @Test
  func downloaderUsesBoundedOneGiBDefaultSafetyMargin() {
    #expect(
      ManagedArtifactDownloader.defaultCapacitySafetyMarginBytes
        == 1_073_741_824
    )
  }

  private func makePreflight(
    safetyMarginBytes: UInt64,
    downloadCapacity: DownloadFileSystemCapacity,
    artifactStoreCapacity: DownloadFileSystemCapacity
  ) -> DownloadCapacityPreflight {
    let capacities = [
      downloadRootURL.path: downloadCapacity,
      artifactStoreRootURL.path: artifactStoreCapacity,
    ]
    return DownloadCapacityPreflight(
      safetyMarginBytes: safetyMarginBytes,
      capacityProvider: DownloadCapacityProvider { url in
        guard let capacity = capacities[url.path] else {
          throw POSIXError(.ENOENT)
        }
        return capacity
      }
    )
  }

  private func capacity(
    deviceID: Int32,
    availableBytes: UInt64
  ) -> DownloadFileSystemCapacity {
    DownloadFileSystemCapacity(
      deviceID: deviceID,
      availableBlocks: availableBytes,
      blockSize: 1
    )
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private final class CapacityPreflightURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var started = false

  static var hasStarted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started
  }

  static func reset() {
    lock.lock()
    started = false
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.started = true
    Self.lock.unlock()
    client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
  }

  override func stopLoading() {}
}
