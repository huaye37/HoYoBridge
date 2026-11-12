import AppKit
import SwiftUI

/// Cached official artwork, with bundled fallback while offline or loading.
struct LauncherArtworkView: View {
  @ObservedObject private var artwork = LauncherArtworkStore.shared
  let game: MiHoYoGame

  init(game: MiHoYoGame = .genshin) {
    self.game = game
  }

  // SwiftPM's generated accessor searches beside the executable; packaged apps use Resources.
  private static let artworkBundle =
    Bundle.main.url(forResource: "MacGameBridge_BridgeStatus", withExtension: "bundle")
    .flatMap { Bundle(url: $0) } ?? .module

  private var landscape: NSImage? {
    if let cached = artwork.images[game] { return cached }
    let official: String? = switch game {
    case .genshin: nil
    case .starRail: "StarRailOfficial"
    case .zenlessZoneZero: "ZenlessOfficial"
    case .honkaiImpact3: "Honkai3Official"
    }
    if let official,
      let url = Self.artworkBundle.url(forResource: official, withExtension: "webp"),
      let image = NSImage(contentsOf: url) { return image }
    for name in [game.artworkResourceName, "LauncherLandscape"] {
      if let url = Self.artworkBundle.url(forResource: name, withExtension: "png"),
        let image = NSImage(contentsOf: url) { return image }
    }
    return nil
  }

  var body: some View {
    Color(red: 0.10, green: 0.22, blue: 0.27)
      .overlay {
        GeometryReader { geometry in
          if let landscape {
            Image(nsImage: landscape)
              .resizable()
              .scaledToFill()
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
          }
        }
      }
      .overlay {
        LinearGradient(
          colors: [.black.opacity(0.48), .clear], startPoint: .leading, endPoint: .trailing)
      }
      .overlay {
        LinearGradient(stops: [
          .init(color: .black.opacity(0.62), location: 0),
          .init(color: .clear, location: 0.22),
          .init(color: .clear, location: 0.58),
          .init(color: .black.opacity(0.5), location: 1),
        ], startPoint: .top, endPoint: .bottom)
      }
      .accessibilityHidden(true)
  }
}
