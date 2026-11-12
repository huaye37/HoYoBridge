import CryptoKit
import Foundation

enum RuntimeAssetDownloadError: Error, LocalizedError {
  case unavailable, integrity
  var errorDescription: String? {
    switch self {
    case .unavailable: "无法下载运行组件，请检查网络后重试。"
    case .integrity: "运行组件校验失败，请稍后重试。"
    }
  }
}

struct DownloadableRuntimeAsset: Sendable {
  let name: String
  let url: URL
  let size: UInt64
  let sha256: String
  var executable = false
}

actor RuntimeAssetDownload {
  static let shared = RuntimeAssetDownload()
  private let cache: URL
  private let session: URLSession

  init(cache: URL = GameRuntimePaths.userStorageRoot.appending(path: "RuntimeDownloads/v1", directoryHint: .isDirectory),
       session: URLSession = .shared) {
    self.cache = cache
    self.session = session
  }

  func obtain(_ asset: DownloadableRuntimeAsset) async throws -> URL {
    let manager = FileManager.default
    try manager.createDirectory(at: cache, withIntermediateDirectories: true)
    let destination = cache.appending(path: asset.name)
    if (try? Self.matches(destination, asset: asset)) == true {
      if asset.executable { try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
      return destination
    }
    let temporary: URL
    let response: URLResponse
    do { (temporary, response) = try await session.download(from: asset.url) }
    catch is CancellationError { throw CancellationError() }
    catch { throw RuntimeAssetDownloadError.unavailable }
    defer { try? manager.removeItem(at: temporary) }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RuntimeAssetDownloadError.unavailable }
    guard try Self.matches(temporary, asset: asset) else { throw RuntimeAssetDownloadError.integrity }
    try Task.checkCancellation()
    let staging = cache.appending(path: ".\(asset.name).\(UUID().uuidString)")
    defer { try? manager.removeItem(at: staging) }
    try manager.copyItem(at: temporary, to: staging)
    if asset.executable { try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path) }
    // Concurrent callers may have already published the same verified asset.
    if (try? Self.matches(destination, asset: asset)) == true { return destination }
    if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
    do { try manager.moveItem(at: staging, to: destination) }
    catch {
      guard (try? Self.matches(destination, asset: asset)) == true else { throw error }
    }
    return destination
  }

  private static func matches(_ url: URL, asset: DownloadableRuntimeAsset) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let size = values.fileSize, UInt64(size) == asset.size else { return false }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined() == asset.sha256
  }
}

enum RuntimeDownloadCatalog {
  private static let upstream = "https://raw.githubusercontent.com/yaagl/yet-another-anime-game-launcher/ca78abc29c2fc236261d088c6907d28cab6e9476/sidecar/"
  private static func asset(_ name: String, _ url: String, _ expectation: RuntimeAssetExpectation, executable: Bool = false) -> DownloadableRuntimeAsset {
    DownloadableRuntimeAsset(name: name, url: URL(string: url)!, size: expectation.byteSize, sha256: expectation.sha256, executable: executable)
  }
  static let wine = asset("wine-crossover-11.0-1-osx64-signed.tar.xz", "https://github.com/yaagl/anime-game-wine/releases/download/wine-crossover-11.0-1-signed/wine-crossover-11.0-1-osx64-signed.tar.xz", RuntimeAssetExpectations.pinned.wine)
  static let dxmt = asset("dxmt-v0.80-builtin.tar.gz", "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz", RuntimeAssetExpectations.pinned.dxmt)
  static let steam64 = asset("steam64.exe", upstream + "protonextras/steam64.exe", RuntimeAssetExpectations.pinned.steam64)
  static let steam32 = asset("steam32.exe", upstream + "protonextras/steam32.exe", RuntimeAssetExpectations.pinned.steam32)
  static let client64 = asset("lsteamclient64.dll", upstream + "protonextras/lsteamclient64.dll", RuntimeAssetExpectations.pinned.lsteamclient64)
  static let client32 = asset("lsteamclient32.dll", upstream + "protonextras/lsteamclient32.dll", RuntimeAssetExpectations.pinned.lsteamclient32)
  static let extractor = asset("7zz", upstream + "7z/7zz", RuntimeAssetExpectation(byteSize: 5_229_328, sha256: "10bba361f87be5882e362df8f283646fb5fff1a7f63246149a5809be286897f5"), executable: true)
}
