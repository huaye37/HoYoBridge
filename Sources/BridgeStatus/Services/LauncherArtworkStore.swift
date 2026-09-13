import AppKit
import Foundation
import OSLog

/// Official artwork is cosmetic and never changes the selected compatibility runtime.
@MainActor
final class LauncherArtworkStore: ObservableObject {
  static let shared = LauncherArtworkStore()
  @Published private(set) var images: [MiHoYoGame: NSImage] = [:]
  private var refreshing = false
  private var lastAttempt: Date?
  private let logger = Logger(subsystem: "cn.yeutech.MacGameBridge", category: "Artwork")
  private let directory: URL
  private let session: URLSession

  init() {
    directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "MacGameBridge/Artwork", directoryHint: .isDirectory)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    session = URLSession(configuration: configuration)
    for game in MiHoYoGame.allCases {
      images[game] = NSImage(contentsOf: directory.appending(path: "\(game.rawValue).image"))
    }
  }

  func refreshIfNeeded() async {
    guard !refreshing, lastAttempt.map({ Date().timeIntervalSince($0) >= 3600 }) ?? true else { return }
    refreshing = true
    lastAttempt = Date()
    defer { refreshing = false }
    do {
      let endpoint = URL(string: "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGames?launcher_id=jGHBHlcOq1&language=zh-cn")!
      let (data, response) = try await session.data(from: endpoint)
      guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { return }
      let catalog = try JSONDecoder().decode(Catalog.self, from: data)
      guard catalog.retcode == 0 else { return }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for item in catalog.data.games {
        guard let game = Self.game(for: item.biz), let url = URL(string: item.display.background.url),
          Self.isOfficialImageURL(url) else { continue }
        do {
          let imageFile = directory.appending(path: "\(game.rawValue).image")
          let sourceFile = directory.appending(path: "\(game.rawValue).source")
          if images[game] != nil,
            (try? String(contentsOf: sourceFile, encoding: .utf8)) == url.absoluteString { continue }
          let (temporary, imageResponse) = try await session.download(from: url)
          defer { try? FileManager.default.removeItem(at: temporary) }
          guard (imageResponse as? HTTPURLResponse)?.statusCode == 200,
            let finalURL = imageResponse.url, Self.isOfficialImageURL(finalURL),
            let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > 0, size <= 20_000_000 else { continue }
          let bytes = try Data(contentsOf: temporary)
          guard let image = NSImage(data: bytes), image.isValid,
            image.size.width >= 640, image.size.height >= 360 else { continue }
          try bytes.write(to: imageFile, options: .atomic)
          try url.absoluteString.write(to: sourceFile, atomically: true, encoding: .utf8)
          images[game] = image
          logger.info("Updated official artwork: \(game.rawValue, privacy: .public)")
        } catch {
          logger.notice("Artwork update failed; retaining cached image: \(game.rawValue, privacy: .public)")
        }
      }
    } catch {
      logger.notice("Artwork catalog unavailable; retaining cached images")
    }
  }

  static func isOfficialImageURL(_ url: URL) -> Bool {
    url.scheme == "https" && ["launcher-webstatic.mihoyo.com", "launcher-webstatic.hoyoverse.com"].contains(url.host ?? "")
  }

  static func game(for biz: String) -> MiHoYoGame? {
    switch biz {
    case "hk4e_cn": .genshin
    case "hkrpg_cn": .starRail
    case "nap_cn": .zenlessZoneZero
    case "bh3_cn": .honkaiImpact3
    default: nil
    }
  }

  private struct Catalog: Decodable {
    let retcode: Int
    let data: Payload
    struct Payload: Decodable { let games: [Game] }
    struct Game: Decodable {
      let biz: String
      let display: Display
    }
    struct Display: Decodable { let background: Background }
    struct Background: Decodable { let url: String }
  }
}
