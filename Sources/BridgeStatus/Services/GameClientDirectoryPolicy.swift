import Foundation

struct GameClientLocation: Sendable {
  let client: MiHoYoGame
  let directory: URL
}

enum GameClientDirectoryPolicy {
  static func locations(defaults: UserDefaults = .standard) -> [GameClientLocation] {
    MiHoYoGame.allCases.flatMap { game in
      var paths = [defaults.string(forKey: "games.\(game.rawValue).pendingInstall")]
      paths.append(game.configuredDirectory(defaults: defaults)?.path)
      return paths.compactMap { $0 }.map {
        GameClientLocation(client: game, directory: URL(fileURLWithPath: $0, isDirectory: true))
      }
    }
  }

  static func issue(for directory: URL, client: MiHoYoGame,
    locations: [GameClientLocation] = locations()) -> String? {
    let path = directory.standardizedFileURL.path
    guard directory.isFileURL, path.hasPrefix("/"), directory.pathComponents.count > 3,
      path == directory.resolvingSymlinksInPath().standardizedFileURL.path else {
      return "目录无法安全识别，请选择独立的游戏文件夹。"
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let protected = [home] + ["Desktop", "Documents", "Downloads", "Library", "Games"].map { home.appending(path: $0) }
    guard !protected.contains(where: { $0.standardizedFileURL.path == path || $0.path.hasPrefix(path + "/") }) else {
      return "不能把用户主目录或公共文件夹作为单个游戏目录。"
    }
    for other in locations where other.client != client {
      let otherPath = other.directory.resolvingSymlinksInPath().standardizedFileURL.path
      if path == otherPath || path.hasPrefix(otherPath + "/") || otherPath.hasPrefix(path + "/") {
        return "该位置与\(other.client.clientTitle)重叠，请为两个客户端分别选择独立目录。"
      }
    }
    if let content = try? String(contentsOf: directory.appending(path: "config.ini"), encoding: .utf8),
      let line = content.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("game_biz=") }),
      let recorded = line.split(separator: "=", maxSplits: 1).last,
      recorded.trimmingCharacters(in: .whitespacesAndNewlines) != client.officialBiz {
      return "目录中的客户端版本与\(client.region.title)不符，请重新选择。"
    }
    return nil
  }

  static func cleanupTarget(client: MiHoYoGame, defaults: UserDefaults = .standard,
    locations: [GameClientLocation]? = nil) -> URL? {
    let operation = defaults.string(forKey: "games.\(client.rawValue).pendingOperation")
    guard operation == nil || operation == "install",
      let path = defaults.string(forKey: "games.\(client.rawValue).pendingInstall") else { return nil }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    guard issue(for: url, client: client, locations: locations ?? self.locations(defaults: defaults)) == nil else { return nil }
    return url
  }
}
