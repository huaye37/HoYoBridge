import AppKit
import Foundation

@MainActor
final class GameLibraryStore: ObservableObject {
  @Published private(set) var games: [GameLibraryItem]

  private let defaults: UserDefaults
  private let storageKey = "launcher.customGames"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let customGames: [GameLibraryItem]
    if let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([GameLibraryItem].self, from: data)
    {
      customGames = decoded.filter { !Self.builtInProfiles.contains($0.profile) }.map { item in
        guard item.profile == .unconfigured else { return item }
        return GameLibraryItem(
          id: item.id,
          title: item.title,
          subtitle: "通用实验配置 · CrossOver 11 + DXMT",
          executablePath: item.executablePath,
          profile: .genericCrossOverDXMT,
          profileRevision: 1
        )
      }
    } else {
      customGames = []
    }
    games = GameLibraryItem.miHoYoCN + customGames
  }

  func addGame() {
    let panel = NSOpenPanel()
    panel.title = "添加 Windows 游戏"
    panel.message = "选择游戏的 .exe 文件。添加后可以为它建立独立兼容配置。"
    panel.prompt = "添加到游戏库"
    panel.allowedContentTypes = [.exe]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let path = url.standardizedFileURL.path
    if let existing = games.first(where: { $0.executablePath == path }) {
      games.removeAll { $0.id == existing.id }
      games.append(existing)
      return
    }
    let item = GameLibraryItem(
      id: UUID().uuidString,
      title: url.deletingPathExtension().lastPathComponent,
      subtitle: "通用实验配置 · CrossOver 11 + DXMT",
      executablePath: path,
      profile: .genericCrossOverDXMT,
      profileRevision: 1
    )
    games.append(item)
    persist()
  }

  func remove(_ game: GameLibraryItem) {
    guard !Self.builtInProfiles.contains(game.profile) else { return }
    games.removeAll { $0.id == game.id }
    persist()
  }

  private func persist() {
    let customGames = games.filter { !Self.builtInProfiles.contains($0.profile) }
    if let data = try? JSONEncoder().encode(customGames) {
      defaults.set(data, forKey: storageKey)
    }
  }

  private static let builtInProfiles: Set<GameCompatibilityProfile> = [
    .genshinCN, .starRailCN, .zenlessZoneZeroCN, .honkaiImpact3CN,
  ]
}
