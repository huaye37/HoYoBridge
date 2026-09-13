import Foundation

enum GameRuntimePathError: Error, Equatable {
  case projectNotFound
  case runtimeNotFound
  case gameNotFound
  case installationIncomplete
}

enum GameInstallLocationPreference {
  static let key = "games.genshinCN.installationRoot"

  static func load(defaults: UserDefaults = .standard) -> URL? {
    guard let path = defaults.string(forKey: key), path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  }

  static func save(_ url: URL, defaults: UserDefaults = .standard) {
    guard url.isFileURL, url.path.hasPrefix("/") else { return }
    defaults.set(url.standardizedFileURL.path, forKey: key)
  }
}

struct GameRuntimePaths: Equatable, Sendable {
  let projectRoot: URL
  let runtimeRoot: URL
  let prefix: URL
  let gameExecutable: URL

  var wine: URL { runtimeRoot.appending(path: "wine/bin/wine") }
  var wineserver: URL { runtimeRoot.appending(path: "wine/bin/wineserver") }
  var diagnosticsDirectory: URL {
    Self.userStorageRoot.appending(
      path: "LocalRuntimes/Diagnostics",
      directoryHint: .isDirectory
    )
  }

  var windowsGamePath: String {
    "Z:" + gameExecutable.path.replacingOccurrences(of: "/", with: "\\")
  }

  var isRuntimeReady: Bool {
    FileManager.default.isExecutableFile(atPath: wine.path)
      && FileManager.default.isExecutableFile(atPath: wineserver.path)
      && FileManager.default.fileExists(atPath: prefix.path)
  }

  var isGameReady: Bool {
    let game = gameExecutable.deletingLastPathComponent()
    return !GameDownloadLock.isBusy(game: game) && GameInstallationRecord.isInstalled(at: game)
  }

  static var userStorageRoot: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "MacGameBridge", directoryHint: .isDirectory)
  }

  static var userRuntimeRoot: URL {
    userStorageRoot.appending(
      path: "Runtimes/genshin-cn-crossover11-steam",
      directoryHint: .isDirectory
    )
  }

  static var userPrefix: URL {
    userStorageRoot.appending(
      path: "Prefixes/genshin-cn-crossover11-steam",
      directoryHint: .isDirectory
    )
  }

  static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundleURL: URL = Bundle.main.bundleURL,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    userStorageRoot: URL = GameRuntimePaths.userStorageRoot,
    configuredGameRoot: URL? = GameInstallLocationPreference.load()
  ) throws -> Self {
    let paths = try resolveRuntime(
      environment: environment,
      bundleURL: bundleURL,
      currentDirectory: currentDirectory,
      userStorageRoot: userStorageRoot,
      configuredGameRoot: configuredGameRoot
    )
    let game = paths.gameExecutable.deletingLastPathComponent()
    if GameDownloadLock.isBusy(game: game) { throw GameRuntimePathError.installationIncomplete }
    switch GameInstallationRecord.state(at: game) {
    case .resumable, .recoveryRequired: throw GameRuntimePathError.installationIncomplete
    default: break
    }
    guard paths.isGameReady else { throw GameRuntimePathError.gameNotFound }
    return paths
  }

  static func resolveRuntime(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundleURL: URL = Bundle.main.bundleURL,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    userStorageRoot: URL = GameRuntimePaths.userStorageRoot,
    configuredGameRoot: URL? = GameInstallLocationPreference.load()
  ) throws -> Self {
    let gameRoot: URL
    if let override = environment["MGB_GENSHIN_CN_HOME"], !override.isEmpty {
      gameRoot = URL(fileURLWithPath: override, isDirectory: true)
    } else if let configuredGameRoot {
      gameRoot = configuredGameRoot
    } else {
      let legacyRoot = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Games/MacGameBridge/Genshin Impact",
        directoryHint: .isDirectory
      )
      gameRoot = FileManager.default.isReadableFile(atPath: legacyRoot.appending(path: "YuanShen.exe").path)
        ? legacyRoot : MiHoYoGame.genshin.defaultDirectory
    }

    let gameExecutable = gameRoot.appending(path: "YuanShen.exe")
    let userPaths = Self(
      projectRoot: userStorageRoot,
      runtimeRoot: userStorageRoot.appending(
        path: "Runtimes/genshin-cn-crossover11-steam",
        directoryHint: .isDirectory
      ),
      prefix: userStorageRoot.appending(
        path: "Prefixes/genshin-cn-crossover11-steam",
        directoryHint: .isDirectory
      ),
      gameExecutable: gameExecutable
    )
    if userPaths.isRuntimeReady,
      hasExactMarker(at: userPaths.runtimeRoot),
      hasExactMarker(at: userPaths.prefix)
    {
      return userPaths
    }

    guard
      let projectRoot = try? locateProjectRoot(
        environment: environment,
        bundleURL: bundleURL,
        currentDirectory: currentDirectory
      )
    else {
      throw GameRuntimePathError.runtimeNotFound
    }
    let projectPaths = Self(
      projectRoot: projectRoot,
      runtimeRoot: projectRoot.appending(
        path: "LocalRuntimes/Active/genshin-cn-crossover11-steam",
        directoryHint: .isDirectory
      ),
      prefix: projectRoot.appending(
        path: "LocalRuntimes/Prefixes/genshin-cn-7.0.0-crossover11-steam",
        directoryHint: .isDirectory
      ),
      gameExecutable: gameExecutable
    )
    guard projectPaths.isRuntimeReady else { throw GameRuntimePathError.runtimeNotFound }
    return projectPaths
  }

  private static func locateProjectRoot(
    environment: [String: String],
    bundleURL: URL,
    currentDirectory: URL
  ) throws -> URL {
    var candidates: [URL] = []
    if let override = environment["MGB_PROJECT_ROOT"], !override.isEmpty {
      candidates.append(URL(fileURLWithPath: override, isDirectory: true))
    }
    candidates.append(bundleURL)
    candidates.append(currentDirectory)

    for candidate in candidates {
      var cursor = candidate
      if !cursor.hasDirectoryPath {
        cursor.deleteLastPathComponent()
      }
      for _ in 0..<8 {
        let package = cursor.appending(path: "Package.swift")
        let runtime = cursor.appending(path: "LocalRuntimes")
        if FileManager.default.fileExists(atPath: package.path),
          FileManager.default.fileExists(atPath: runtime.path)
        {
          return cursor.standardizedFileURL
        }
        let parent = cursor.deletingLastPathComponent()
        guard parent.path != cursor.path else { break }
        cursor = parent
      }
    }
    throw GameRuntimePathError.projectNotFound
  }

  private static func hasExactMarker(at root: URL) -> Bool {
    let marker = root.appending(path: RuntimeAssetInstaller.markerName)
    return (try? String(contentsOf: marker, encoding: .utf8))
      == RuntimeAssetInstaller.markerContents
  }
}
