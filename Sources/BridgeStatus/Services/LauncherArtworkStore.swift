import AppKit
import Foundation
import OSLog

/// Official artwork is cosmetic and never changes the selected compatibility runtime.
@MainActor
final class LauncherArtworkStore: ObservableObject {
  static let shared = LauncherArtworkStore()
  @Published private(set) var images: [MiHoYoGame: NSImage] = [:]
  private var refreshing = false
  private var nextAttempt: [GameClientRegion: Date] = [:]
  private let logger = Logger(subsystem: "cn.yeutech.MacGameBridge", category: "Artwork")
  private let directory: URL
  private let session: URLSession

  init(directory: URL? = nil, session: URLSession? = nil) {
    self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "MacGameBridge/Artwork", directoryHint: .isDirectory)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    self.session = session ?? URLSession(configuration: configuration)
    for game in MiHoYoGame.allCases {
      images[game] = NSImage(contentsOf: self.directory.appending(path: "\(game.rawValue).image"))
    }
  }

  func refreshIfNeeded(regions: [GameClientRegion] = GameClientRegion.allCases) async {
    guard !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    for region in regions {
    guard nextAttempt[region].map({ Date() >= $0 }) ?? true else { continue }
    // A failed catalog or image can retry soon without blocking the other region.
    nextAttempt[region] = Date().addingTimeInterval(60)
    do {
      let launcher = region == .china ? "jGHBHlcOq1" : "VYTpXlbWo8"
      let endpoint = URL(string: "https://\(region.frontendHost)/hyp/hyp-connect/api/getGames?launcher_id=\(launcher)&language=zh-cn")!
      let (data, response) = try await session.data(from: endpoint)
      guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000 else { continue }
      let catalog = try JSONDecoder().decode(Catalog.self, from: data)
      guard catalog.retcode == 0 else { continue }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var readyGames: Set<MiHoYoGame> = []
      for item in catalog.data.games {
        guard let game = Self.game(for: item.biz), game.region == region,
          let url = URL(string: item.display.background.url),
          Self.isOfficialImageURL(url) else { continue }
        do {
          let imageFile = directory.appending(path: "\(game.rawValue).image")
          let sourceFile = directory.appending(path: "\(game.rawValue).source")
          if images[game] != nil,
            (try? String(contentsOf: sourceFile, encoding: .utf8)) == url.absoluteString {
            readyGames.insert(game)
            continue
          }
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
          readyGames.insert(game)
          logger.info("Updated official artwork: \(game.rawValue, privacy: .public)")
        } catch {
          logger.notice("Artwork update failed; retaining cached image: \(game.rawValue, privacy: .public)")
        }
      }
      if readyGames.count == MiHoYoGame.navigationGames.count {
        nextAttempt[region] = Date().addingTimeInterval(3600)
      }
    } catch {
      logger.notice("Artwork catalog unavailable; retaining cached images")
    }
    }
  }

  static func isOfficialImageURL(_ url: URL) -> Bool {
    url.scheme == "https" && url.user == nil && url.password == nil
      && (url.port == nil || url.port == 443)
      && ["launcher-webstatic.mihoyo.com", "launcher-webstatic.hoyoverse.com",
          "fastcdn.mihoyo.com", "fastcdn.hoyoverse.com"].contains(url.host ?? "")
  }

  static func game(for biz: String) -> MiHoYoGame? {
    switch biz {
    case "hk4e_cn": .genshin
    case "hkrpg_cn": .starRail
    case "nap_cn": .zenlessZoneZero
    case "bh3_cn": .honkaiImpact3
    case "hk4e_global": .genshinGlobal
    case "hkrpg_global": .starRailGlobal
    case "nap_global": .zenlessZoneZeroGlobal
    case "bh3_global": .honkaiImpact3Global
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
