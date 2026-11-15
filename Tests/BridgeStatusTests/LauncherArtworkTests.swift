import AppKit
import Foundation
import Testing
@testable import BridgeStatus

private final class ArtworkRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var hosts: [String] = []
  func record(_ host: String) { lock.lock(); defer { lock.unlock() }; hosts.append(host) }
  func values() -> [String] { lock.lock(); defer { lock.unlock() }; return hosts }
}

private final class FailingChinaArtworkProtocol: URLProtocol, @unchecked Sendable {
  static let requests = ArtworkRequestLog()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let url = request.url!
    Self.requests.record(url.host!)
    let status = url.host == "hyp-api.mihoyo.com" ? 500 : 200
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
      httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"retcode":0,"data":{"games":[]}}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@MainActor
struct LauncherArtworkTests {
  @Test func failedChinaCatalogStillRequestsInternationalCatalog() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FailingChinaArtworkProtocol.self]
    let store = LauncherArtworkStore(directory: directory, session: URLSession(configuration: configuration))
    await store.refreshIfNeeded()
    #expect(FailingChinaArtworkProtocol.requests.values() == ["hyp-api.mihoyo.com", "sg-hyp-api.hoyoverse.com"])
  }

  @Test func permitsOfficialCDNButNotLookalikesOrCredentialURLs() {
    for host in ["launcher-webstatic.hoyoverse.com", "launcher-webstatic.mihoyo.com", "fastcdn.hoyoverse.com", "fastcdn.mihoyo.com"] {
      #expect(LauncherArtworkStore.isOfficialImageURL(URL(string: "https://\(host)/cover.webp")!))
    }
    for url in ["http://fastcdn.hoyoverse.com/cover.webp", "https://fastcdn.hoyoverse.com.attacker.test/cover.webp",
      "https://user:secret@fastcdn.hoyoverse.com/cover.webp", "https://fastcdn.hoyoverse.com:1234/cover.webp"] {
      #expect(!LauncherArtworkStore.isOfficialImageURL(URL(string: url)!))
    }
  }

  @Test func loadsAllFourLiveInternationalCoversWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["MGB_TEST_ARTWORK_LIVE"] == "1" else { return }
    let directory = FileManager.default.temporaryDirectory.appending(path: "hoyobridge-artwork-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LauncherArtworkStore(directory: directory)
    await store.refreshIfNeeded(regions: [.global])
    for base in MiHoYoGame.navigationGames {
      let game = base.client(in: .global)
      let image = try #require(store.images[game], Comment(rawValue: game.rawValue))
      #expect(image.isValid && image.size.width >= 640 && image.size.height >= 360)
      let source = try String(contentsOf: directory.appending(path: "\(game.rawValue).source"), encoding: .utf8)
      #expect(LauncherArtworkStore.isOfficialImageURL(URL(string: source)!))
      #expect(store.images[base] == nil)
      print("ARTWORK_OK \(game.rawValue) \(image.size.width)x\(image.size.height)")
    }
  }
}
