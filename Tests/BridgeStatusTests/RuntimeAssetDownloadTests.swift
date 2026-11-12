import CryptoKit
import Foundation
import Testing
@testable import BridgeStatus

private final class RuntimeDownloadProtocol: URLProtocol, @unchecked Sendable {
  static let bytes = Data("verified runtime asset".utf8)
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.bytes)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

struct RuntimeAssetDownloadTests {
  @Test func downloadsRealExtractorWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["MGB_TEST_LIVE_RUNTIME"] == "1" else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let downloader = RuntimeAssetDownload(cache: root)
    let file = try await downloader.obtain(RuntimeDownloadCatalog.extractor)
    #expect(FileManager.default.isExecutableFile(atPath: file.path))
  }

  @Test func downloadsRealRuntimeAssetsWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["MGB_TEST_FULL_RUNTIME"] == "1" else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let downloader = RuntimeAssetDownload(cache: root)
    for asset in [RuntimeDownloadCatalog.wine, RuntimeDownloadCatalog.dxmt,
      RuntimeDownloadCatalog.steam64, RuntimeDownloadCatalog.steam32,
      RuntimeDownloadCatalog.client64, RuntimeDownloadCatalog.client32] {
      _ = try await downloader.obtain(asset)
    }
  }

  @Test func preparesRuntimeInIsolatedDirectoryWhenRequested() throws {
    guard ProcessInfo.processInfo.environment["MGB_TEST_RUNTIME_INSTALL"] == "1" else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let assets = try #require(RuntimePreparationAssets.resolve())
    try RuntimeAssetInstaller.install(assets: assets, storageRoot: root)
    #expect(FileManager.default.isExecutableFile(atPath:
      root.appending(path: "Runtimes/genshin-cn-crossover11-steam/wine/bin/wine").path))
    #expect(FileManager.default.fileExists(atPath:
      root.appending(path: "Prefixes/genshin-cn-crossover11-steam/.mgb-managed-runtime").path))
  }

  @Test func validatesBeforeCachingAndReusesVerifiedFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RuntimeDownloadProtocol.self]
    let downloader = RuntimeAssetDownload(cache: root, session: URLSession(configuration: configuration))
    let data = RuntimeDownloadProtocol.bytes
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let asset = DownloadableRuntimeAsset(name: "asset", url: URL(string: "https://example.com/asset")!,
      size: UInt64(data.count), sha256: digest, executable: true)
    let path = try await downloader.obtain(asset)
    #expect(try Data(contentsOf: path) == data)
    #expect(try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? Int == 0o755)
    #expect(try await downloader.obtain(asset) == path)
    try Data("corrupted".utf8).write(to: path)
    #expect(try Data(contentsOf: await downloader.obtain(asset)) == data)
  }

  @Test func rejectsWrongHashWithoutCaching() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RuntimeDownloadProtocol.self]
    let downloader = RuntimeAssetDownload(cache: root, session: URLSession(configuration: configuration))
    let asset = DownloadableRuntimeAsset(name: "asset", url: URL(string: "https://example.com/asset")!,
      size: UInt64(RuntimeDownloadProtocol.bytes.count), sha256: String(repeating: "0", count: 64))
    await #expect(throws: RuntimeAssetDownloadError.self) { try await downloader.obtain(asset) }
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "asset").path))
  }
}
