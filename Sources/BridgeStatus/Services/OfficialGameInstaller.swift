import AppKit
import Foundation
import CryptoKit

@MainActor
struct OfficialEngineCommands {
  var query: @MainActor (String, [String: Any]) async throws -> Any?
  var stop: @MainActor () async throws -> Void
}

/// Bridges the official install engine; each request is scoped to one game client and region.
@MainActor
final class OfficialGameInstaller: ObservableObject {
  static let shared = OfficialGameInstaller()
  static let international = OfficialGameInstaller(region: .global)
  static func service(for game: MiHoYoGame) -> OfficialGameInstaller {
    game.region == .china ? shared : international
  }
  private static var occupiedGames: Set<MiHoYoGame> {
    shared.busy.union(shared.checking).union(shared.cleaningDownloads)
      .union(international.busy).union(international.checking).union(international.cleaningDownloads)
      .union(outstandingGames())
  }
  let region: GameClientRegion
  private let engineStorageRoot: URL
  private let enginePort: UInt16
  private let engineArchiveOverride: URL?
  private let defaults: UserDefaults
  private let commands: OfficialEngineCommands?
  private var taskGames: Set<MiHoYoGame> {
    if engineStorageRoot.standardizedFileURL != GameRuntimePaths.userStorageRoot.standardizedFileURL {
      return busy.union(checking).union(cleaningDownloads).union(Self.outstandingGames(defaults: defaults))
    }
    return Self.occupiedGames
  }
  private var downloadTasks: [MiHoYoGame: Task<Void, Never>] = [:]
  private var enginePrefix: URL { engineStorageRoot.appending(path: region.engineDirectory + "/prefix") }
  @Published private(set) var messages: [MiHoYoGame: String] = [:]
  @Published private(set) var busy: Set<MiHoYoGame> = []
  @Published private(set) var paused: Set<MiHoYoGame> = []
  @Published private(set) var changingDownloadState = false
  @Published private(set) var checking: Set<MiHoYoGame> = []
  @Published private(set) var updates: Set<MiHoYoGame> = []
  @Published private(set) var uninstalling: Set<MiHoYoGame> = []
  @Published private(set) var cleaningDownloads: Set<MiHoYoGame> = []
  @Published private(set) var controllableDownloads: Set<MiHoYoGame> = []
  @Published private(set) var activeOperations: [MiHoYoGame: Operation] = [:]
  @Published private(set) var migrationProgress: [MiHoYoGame: GameMigrationProgress] = [:]
  @Published private(set) var retainedMigrationSources: [MiHoYoGame: URL] = [:]
  private var migrationTasks: [MiHoYoGame: Task<Void, Never>] = [:]
  private let diagnostics = OfficialEngineDiagnostics()

  func openDiagnostics() { diagnostics.record("diagnostics_opened"); NSWorkspace.shared.open(diagnostics.url) }

  static func outstandingGames(defaults: UserDefaults = .standard) -> Set<MiHoYoGame> {
    Set(MiHoYoGame.allCases.filter {
      !defaults.bool(forKey: "games.\($0.rawValue).taskDetached") && (
      defaults.string(forKey: "games.\($0.rawValue).pendingInstall") != nil
        || defaults.string(forKey: "games.\($0.rawValue).pendingUninstall") != nil
      )
    })
  }

  func canEndTask(_ game: MiHoYoGame) -> Bool {
    game.region == region && taskGames.isSubset(of: [game])
      && (busy.isEmpty || paused.contains(game)) && checking.isEmpty && cleaningDownloads.isEmpty
      && !defaults.bool(forKey: "games.\(game.rawValue).taskDetached") && (
      Self.pendingOperation(for: game, defaults: defaults) != nil || hasPendingUninstall(game))
  }

  func endTaskKeepingFiles(_ game: MiHoYoGame) {
    guard canEndTask(game) else { return }
    checking.insert(game)
    messages[game] = "正在停止后台任务，保留游戏文件…"
    Task {
      defer { checking.remove(game) }
      do {
        try await detachDownloadKeepingFiles(game)
        messages[game] = "任务已结束，文件与续传记录保留；其他游戏可继续使用。"
        diagnostics.record("task_detached_" + game.rawValue)
      } catch { messages[game] = error.localizedDescription; diagnostics.record("task_stop_failed") }
    }
  }

  func incompleteDownloadDirectory(_ game: MiHoYoGame) -> URL? {
    guard game.region == region else { return nil }
    return GameClientDirectoryPolicy.cleanupTarget(client: game, defaults: defaults)
  }

  static func preparePausedDownloadsForLauncherUpdate() async throws -> Bool {
    guard try await shared.preparePausedDownloadsForUpdate() else { return false }
    guard try await international.preparePausedDownloadsForUpdate() else { return false }
    return !shared.isOccupied
  }

  /// Invoked only after the user accepts installation of a launcher update.
  func preparePausedDownloadsForUpdate() async throws -> Bool {
    guard checking.isEmpty, cleaningDownloads.isEmpty, uninstalling.isEmpty,
      !changingDownloadState, busy.isSubset(of: paused) else { return false }
    let unconfirmed = Self.outstandingGames(defaults: defaults)
      .filter { $0.region == region && !paused.contains($0) }
    guard unconfirmed.isEmpty else { return false }
    for game in paused.sorted(by: { $0.rawValue < $1.rawValue }) {
      checking.insert(game)
      defer { checking.remove(game) }
      messages[game] = "正在保留下载进度，准备更新启动器…"
      try await detachDownloadKeepingFiles(game)
      messages[game] = "下载文件和续传记录已保留，启动器更新后可继续。"
      diagnostics.record("paused_download_detached_for_launcher_update_" + game.rawValue)
    }
    return true
  }

  private func detachDownloadKeepingFiles(_ game: MiHoYoGame) async throws {
    let monitor = downloadTasks[game]
    monitor?.cancel()
    resetConnection()
    await monitor?.value
    try await stopDownloadEngine()
    defaults.set(true, forKey: "games.\(game.rawValue).taskDetached")
    busy.remove(game)
    paused.remove(game)
    controllableDownloads.remove(game)
    activeOperations.removeValue(forKey: game)
  }

  func canDiscardDownload(_ game: MiHoYoGame) -> Bool {
    game.region == region && incompleteDownloadDirectory(game) != nil
      && taskGames.isSubset(of: [game]) && !checking.contains(game)
      && !cleaningDownloads.contains(game) && !uninstalling.contains(game)
  }

  /// Only a confirmed incomplete FIRST install may enter this path; updates/repairs never do.
  func discardIncompleteDownload(_ game: MiHoYoGame, expectedDirectory: URL) async -> Bool {
    guard canDiscardDownload(game),
      incompleteDownloadDirectory(game)?.standardizedFileURL.path == expectedDirectory.standardizedFileURL.path else { return false }
    cleaningDownloads.insert(game)
    defer { cleaningDownloads.remove(game); checking.remove(game) }
    messages[game] = "正在取消\(game.clientTitle)下载…"
    let monitor = downloadTasks[game]
    monitor?.cancel()
    resetConnection()
    await monitor?.value
    checking.insert(game)
    do {
      guard incompleteDownloadDirectory(game)?.standardizedFileURL.path == expectedDirectory.standardizedFileURL.path,
        !MiHoYoGame.isInstallationDiskOffline(expectedDirectory,
          mountedVolumes: FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []) else {
        throw Failure("原下载目录已变化或磁盘未连接，未删除文件。")
      }
      // Stop only this region's dedicated installer prefix, never a game prefix.
      try await stopDownloadEngine()
      try await connect()
      var record: [String: Any]?
      for attempt in 0..<10 {
        let reply = try await query("getLocalGameInfo", ["gameBiz": biz(game), "package": game.officialPackage])
        record = (reply as? [[String: Any]])?.first { Self.matchesClient($0, game: game) }
          ?? (reply as? [String: Any])
        if let state = record?["status"] as? String, !state.isEmpty { break }
        if attempt < 9 { try await Task.sleep(for: .milliseconds(500)) }
      }
      let windowsPath = "Z:" + expectedDirectory.path.replacingOccurrences(of: "/", with: "\\")
      guard Self.permitsIncompleteCleanup(record, game: game, windowsPath: windowsPath),
        let path = record?["installPath"] as? String else {
        throw Failure("后台记录与未完成下载不一致，或游戏已安装完成，未执行清理。请重新检查游戏状态。")
      }
      if !path.isEmpty {
        let result = try await query("uninstallGame", ["gameBiz": biz(game), "package": game.officialPackage,
          "path": windowsPath, "killProcess": false]) as? [String: Any]
        guard result?["result"] as? String == "success" else {
          throw Failure("官方服务未确认取消下载，文件与记录已保留，请重试。")
        }
        let reply = try await query("getLocalGameInfo", ["gameBiz": biz(game), "package": game.officialPackage])
        let after = (reply as? [[String: Any]])?.first { Self.matchesClient($0, game: game) }
          ?? (reply as? [String: Any])
        guard after?["status"] as? String == "need_get_game", after?["installPath"] as? String == "" else {
          throw Failure("后台任务尚未完全退出，未继续删除残留文件。请稍后重试。")
        }
      }
      try await stopDownloadEngine()
      defaults.set(true, forKey: "games.\(game.rawValue).taskDetached")
      if let issue = GameClientDirectoryPolicy.issue(for: expectedDirectory, client: game, locations: GameClientDirectoryPolicy.locations(defaults: defaults)) { throw Failure(issue) }
      var movedToTrash = false
      if FileManager.default.fileExists(atPath: expectedDirectory.path) {
        do {
          try FileManager.default.trashItem(at: expectedDirectory, resultingItemURL: nil)
          movedToTrash = true
        } catch {
          let choice = NSAlert()
          choice.messageText = "此磁盘无法将下载文件移到废纸篓"
          choice.informativeText = "可以永久删除以下未完成下载目录以释放空间，也可以保留文件。不会清理其他客户端。\n\(expectedDirectory.path)"
          choice.addButton(withTitle: "保留文件")
          choice.addButton(withTitle: "永久删除").hasDestructiveAction = true
          guard choice.runModal() == .alertSecondButtonReturn else {
            messages[game] = "下载任务已取消，文件保留；可再次选择清理。"
            return false
          }
          try FileManager.default.removeItem(at: expectedDirectory)
        }
      }
      guard !FileManager.default.fileExists(atPath: expectedDirectory.path) else { throw Failure("清理未完成，下载记录已保留。") }
      for key in ["pendingInstall", "pendingOperation", "pendingUninstall", "taskDetached"] {
        defaults.removeObject(forKey: "games.\(game.rawValue).\(key)")
      }
      let directoryKey = game == .genshin ? "games.genshinCN.installationRoot" : "games.\(game.rawValue).installationRoot"
      if defaults.string(forKey: directoryKey) == expectedDirectory.path { defaults.removeObject(forKey: directoryKey) }
      updates.remove(game)
      messages[game] = movedToTrash ? "下载已取消，文件已移到废纸篓；清空废纸篓可释放空间。" : "下载已取消，已下载文件已清理。"
      diagnostics.record("incomplete_download_cleaned_" + game.rawValue)
      return true
    } catch {
      messages[game] = error.localizedDescription
      diagnostics.record("incomplete_cleanup_failed_" + game.rawValue)
      return false
    }
  }

  private func stopDownloadEngine() async throws {
    if let commands { try await commands.stop(); return }
    resetConnection()
    let server = try GameRuntimePaths.resolveRuntime().wine.deletingLastPathComponent().appending(path: "wineserver")
    for argument in ["-k", "-w"] {
      let process = Process()
      process.executableURL = server
      process.arguments = [argument]
      process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        "WINEPREFIX": enginePrefix.path]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      for _ in 0..<100 {
        if !process.isRunning { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      guard !process.isRunning else {
        if process.isRunning { process.terminate() }
        diagnostics.record("engine_stop_timeout")
        throw Failure("下载服务尚未确认停止，未删除文件；请稍后重试。")
      }
      let status = process.terminationStatus
      diagnostics.record(argument == "-k" ? "engine_stop_request" : "engine_stop_wait", code: status)
      // Wine returns 1 for -k when this prefix has no server. Always run -w
      // afterwards: only its successful exit confirms no server is still running.
      guard status == 0 || (argument == "-k" && status == 1) else {
        throw Failure("下载服务停止确认失败（\(status)），文件已保留，请重试。")
      }
    }
    guard !OfficialEngineDiagnostics.portIsOccupied(enginePort) else {
      diagnostics.record("engine_listener_remains_after_stop", code: Int32(enginePort))
      throw Failure("下载服务端口仍被占用，未继续清理文件；请稍后重试。")
    }
    engine = nil
  }

  static func permitsIncompleteCleanup(_ record: [String: Any]?, game: MiHoYoGame, windowsPath: String) -> Bool {
    guard let record, record["gameBiz"] as? String == game.officialBiz,
      (record["package"] as? String ?? "") == game.officialPackage,
      let path = record["installPath"] as? String,
      let status = record["status"] as? String else { return false }
    return (status == "need_install" && path == windowsPath)
      || (status == "need_get_game" && path.isEmpty)
  }

  var isOccupied: Bool { !busy.isEmpty || !checking.isEmpty || !taskGames.isEmpty }

  /// Playing uses a separate prefix from the download engine. Only this
  /// client's maintenance (including detached unfinished work) blocks launch.
  func blocksLaunch(for game: MiHoYoGame) -> Bool {
    taskGames.contains(game) || busy.contains(game) || checking.contains(game)
      || cleaningDownloads.contains(game) || uninstalling.contains(game)
      || defaults.string(forKey: "games.\(game.rawValue).pendingInstall") != nil
      || defaults.string(forKey: "games.\(game.rawValue).pendingUninstall") != nil
  }

  func blockingMessage(for game: MiHoYoGame) -> String? {
    let tasks = taskGames
    guard let other = MiHoYoGame.allCases.first(where: { $0 != game && tasks.contains($0) }) else { return nil }
    if game.executableURL != nil && !blocksLaunch(for: game) {
      return "\(other.clientTitle)有下载或维护任务，仍可启动当前游戏。"
    }
    return "\(other.clientTitle)有进行中或待确认的任务，请先切换到该游戏处理。"
  }

  func canResume(_ game: MiHoYoGame) -> Bool {
    game.region == region && taskGames.isSubset(of: [game]) && busy.isEmpty && checking.isEmpty
      && cleaningDownloads.isEmpty
      && defaults.string(forKey: "games.\(game.rawValue).pendingUninstall") == nil
  }

  func hasPendingUninstall(_ game: MiHoYoGame) -> Bool {
    defaults.string(forKey: "games.\(game.rawValue).pendingUninstall") != nil
  }

  func reconcileUninstall(_ game: MiHoYoGame) {
    guard game.region == region, busy.isEmpty, checking.isEmpty, cleaningDownloads.isEmpty,
      taskGames.isSubset(of: [game]),
      let path = defaults.string(forKey: "games.\(game.rawValue).pendingUninstall") else { return }
    checking.insert(game)
    Task {
      defer { checking.remove(game) }
      do {
        try await connect()
        let records = try await query("getLocalGameInfo", ["gameBiz": biz(game), "package": game.officialPackage]) as? [[String: Any]] ?? []
        let record = records.first { Self.matchesClient($0, game: game) }
        if defaults.bool(forKey: "games.\(game.rawValue).taskDetached"),
          Self.uninstallCanBeRestored(record, gameBiz: biz(game), path: path),
          game.executableNames.contains(where: { FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: path).appending(path: $0).path) }) {
          defaults.removeObject(forKey: "games.\(game.rawValue).pendingUninstall")
          defaults.removeObject(forKey: "games.\(game.rawValue).taskDetached")
          messages[game] = "卸载未完成，已恢复管理入口；建议先校验并修复游戏。"
          return
        }
        guard record?["status"] as? String == "need_get_game",
          record?["installPath"] as? String == "",
          !game.executableNames.contains(where: { FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appending(path: $0).path) }) else {
          throw Failure("后台卸载状态尚未确认，安装记录与任务保护已保留，请稍后再检查。")
        }
        for key in ["pendingUninstall", "pendingInstall", "pendingOperation", "installationRoot", "taskDetached"] {
          defaults.removeObject(forKey: "games.\(game.rawValue).\(key)")
        }
        if game == .genshin { defaults.removeObject(forKey: "games.genshinCN.installationRoot") }
        messages[game] = "已确认卸载完成"
      } catch { resetConnection(); messages[game] = error.localizedDescription }
    }
  }
  private var toggleRequested = false

  static func uninstallCanBeRestored(_ record: [String: Any]?, gameBiz: String, path: String) -> Bool {
    record?["gameBiz"] as? String == gameBiz
      && record?["status"] as? String == "ready"
      && record?["installPath"] as? String == "Z:" + path.replacingOccurrences(of: "/", with: "\\")
  }
  private var engine: Process?
  private var socket: URLSessionWebSocketTask?
  private var requestID = 0
  private var connecting = false
  private let windowSupport: NativeGameWindowSupport?

  init(resourceURL: URL? = Bundle.main.resourceURL, region: GameClientRegion = .china,
    storageRoot: URL = GameRuntimePaths.userStorageRoot, port: UInt16? = nil, engineArchive: URL? = nil,
    defaults: UserDefaults = .standard, commands: OfficialEngineCommands? = nil) {
    self.region = region
    self.engineStorageRoot = storageRoot
    self.enginePort = port ?? region.enginePort
    self.engineArchiveOverride = engineArchive
    self.defaults = defaults
    self.commands = commands
    windowSupport = NativeGameWindowSupport.resolve(resourceURL: resourceURL)
  }

  func togglePause() {
    guard !changingDownloadState, !controllableDownloads.isEmpty else { return }
    changingDownloadState = true
    toggleRequested = true
  }

  /// The confirmed directory must still match the official engine's record.
  func uninstall(_ game: MiHoYoGame, expectedDirectory: URL) async -> Bool {
    guard game.region == region, !isOccupied else { return false }
    if let issue = GameClientDirectoryPolicy.issue(for: expectedDirectory, client: game, locations: GameClientDirectoryPolicy.locations(defaults: defaults)) {
      messages[game] = issue
      return false
    }
    defaults.removeObject(forKey: "games.\(game.rawValue).taskDetached")
    busy.insert(game)
    uninstalling.insert(game)
    defer { busy.remove(game); uninstalling.remove(game) }
    do {
      guard expectedDirectory.pathComponents.count > 3,
        expectedDirectory.standardizedFileURL == expectedDirectory.resolvingSymlinksInPath().standardizedFileURL,
        game.executableNames.contains(where: {
          FileManager.default.isReadableFile(atPath: expectedDirectory.appending(path: $0).path)
        }) else { throw Failure("目录无法安全识别，未执行卸载。") }
      try await connect()
      try await requireLinkedDirectory(game, target: expectedDirectory, automaticallyAssociate: false)
      messages[game] = "正在卸载游戏…"
      defaults.set(expectedDirectory.path, forKey: "games.\(game.rawValue).pendingUninstall")
      let reply = try await query("uninstallGame", ["gameBiz": biz(game), "package": game.officialPackage,
        "path": "Z:" + expectedDirectory.path.replacingOccurrences(of: "/", with: "\\"), "killProcess": false])
      guard (reply as? [String: Any])?["result"] as? String == "success" else {
        if (reply as? [String: Any])?["result"] as? String == "fail" {
          defaults.removeObject(forKey: "games.\(game.rawValue).pendingUninstall")
        }
        throw Failure("官方服务未完成卸载，原目录记录已保留，请检查游戏是否仍在运行。")
      }
      guard !game.executableNames.contains(where: {
        FileManager.default.fileExists(atPath: expectedDirectory.appending(path: $0).path)
      }) else { throw Failure("卸载后仍检测到游戏文件，未清除安装记录。") }
      for key in ["installationRoot", "pendingInstall", "pendingOperation"] {
        defaults.removeObject(forKey: "games.\(game.rawValue).\(key)")
      }
      if game == .genshin { defaults.removeObject(forKey: "games.genshinCN.installationRoot") }
      updates.remove(game)
      defaults.removeObject(forKey: "games.\(game.rawValue).pendingUninstall")
      messages[game] = "游戏已卸载，兼容环境与其他游戏保留。"
      return true
    } catch {
      messages[game] = error.localizedDescription
      resetConnection()
      return false
    }
  }

  private func biz(_ game: MiHoYoGame) -> String { game.officialBiz }

  static func matchesClient(_ record: [String: Any], game: MiHoYoGame) -> Bool {
    record["gameBiz"] as? String == game.officialBiz
      && (record["package"] as? String ?? "") == game.officialPackage
  }

  /// Read-only diagnostic used to validate the pinned regional engine without downloading a game.
  func inspectInstallMetadata(_ game: MiHoYoGame, directory: URL) async throws -> [String: Any] {
    guard game.region == region else { throw Failure("客户端版本与下载服务不匹配。") }
    try await connect()
    return try await query("getGameInstallInfo", ["gameBiz": biz(game), "package": game.officialPackage,
      "dir": "Z:" + directory.path.replacingOccurrences(of: "/", with: "\\")]) as? [String: Any] ?? [:]
  }

  func stopIsolatedDiagnosticEngine() async throws {
    guard engineStorageRoot.standardizedFileURL != GameRuntimePaths.userStorageRoot.standardizedFileURL,
      enginePort != GameClientRegion.china.enginePort, enginePort != GameClientRegion.global.enginePort else {
      throw Failure("仅可停止独立诊断目录的下载服务。")
    }
    if engine == nil && !OfficialEngineDiagnostics.portIsOccupied(enginePort) { return }
    try await stopDownloadEngine()
  }

  #if DEBUG
  /// Integration-test entry point restricted to a disposable prefix and its child directory.
  func startIsolatedDiagnosticDownload(_ game: MiHoYoGame, directory: URL) async throws {
    guard engineStorageRoot.standardizedFileURL != GameRuntimePaths.userStorageRoot.standardizedFileURL,
      enginePort != GameClientRegion.china.enginePort, enginePort != GameClientRegion.global.enginePort,
      directory.resolvingSymlinksInPath().path.hasPrefix(engineStorageRoot.resolvingSymlinksInPath().path + "/"),
      !FileManager.default.fileExists(atPath: directory.path), game.region == region else {
      throw Failure("诊断下载仅允许写入独立目录的新子文件夹。")
    }
    _ = try await inspectInstallMetadata(game, directory: directory)
    defaults.set(directory.path, forKey: "games.\(game.rawValue).pendingInstall")
    defaults.set("install", forKey: "games.\(game.rawValue).pendingOperation")
    let response = try await query("startDownload", ["gameBiz": game.officialBiz,
      "package": game.officialPackage, "path": "Z:" + directory.path.replacingOccurrences(of: "/", with: "\\"),
      "voiceLangList": [], "packageType": "FULL", "createShortcut": false, "createShortcutInStartMenu": false]) as? [String: Any]
    if let outcome = response?["result"] as? String, outcome != "success" {
      throw Failure("诊断下载未创建成功：result=\(outcome), errorCode=\(response?["errorCode"] ?? "missing")")
    }
    // The frontend may reload during initialization. Reattach the listener and
    // repeat pause until an actual stopped-download event arrives.
    var lastStatus: String?
    for attempt in 0..<80 {
      try await Task.sleep(for: .milliseconds(500))
      let status = try await evaluate("(()=>{if(!window.HYPClient)return null;window.__mgbProductDownloads ??= {};if(!window.__mgbProductDownloadListener){window.__mgbProductDownloadListener=d=>{if(typeof d==='string')d=JSON.parse(d);if(d.gameBiz)window.__mgbProductDownloads[d.gameBiz]=d};window.HYPClient.addEventListener('updateDownloadStatus',window.__mgbProductDownloadListener)}return window.__mgbProductDownloads['\(game.officialBiz)']?.status ?? null})()") as? String
      if status != lastStatus { print("DIAGNOSTIC_DOWNLOAD_STATUS \(status ?? "pending")"); lastStatus = status }
      if status == "cancelled" {
        busy.insert(game)
        paused.insert(game)
        activeOperations[game] = .install
        return
      }
      if attempt % 4 == 0 {
        _ = try await query("pauseDownload", ["gameBiz": game.officialBiz, "package": game.officialPackage])
      }
    }
    throw Failure("诊断下载未确认暂停。")
  }
  #endif

  func checkForUpdates(_ game: MiHoYoGame) {
    guard game.region == region, !isOccupied else { return }
    checking.insert(game)
    updates.remove(game)
    messages[game] = "正在检查更新…"
    Task {
      defer { checking.remove(game) }
      do {
        try await connect()
        guard let target = game.configuredDirectory else { throw Failure("请先定位游戏目录。") }
        try await requireLinkedDirectory(game, target: target)
        let info = try await checkedUpdate(game)
        if Self.updateStatus(info) == .available {
          updates.insert(game)
          messages[game] = "发现新版本，可在游戏管理中更新"
        } else if Self.updateStatus(info) == .current {
          messages[game] = "当前游戏已是最新版本"
        } else {
          messages[game] = "当前状态需要校验修复，未确认已是最新版本"
        }
      } catch {
        resetConnection()
        messages[game] = error.localizedDescription
      }
    }
  }

  enum UpdateStatus: Equatable { case available, current, unknown }

  static func updateStatus(_ info: [String: Any]) -> UpdateStatus {
    guard info["result"] as? String == "success" else { return .unknown }
    switch info["status"] as? String {
    case "need_update": return .available
    case "ready": return .current
    default: return .unknown
    }
  }

  private func checkedUpdate(_ game: MiHoYoGame) async throws -> [String: Any] {
    guard let info = try await query("checkGameUpdate", ["gameBiz": biz(game), "package": game.officialPackage]) as? [String: Any],
      info["result"] as? String == "success" else { throw Failure("官方更新检查未成功，请稍后重试。") }
    return info
  }

  func associateDirectory(_ game: MiHoYoGame) {
    guard game.region == region, !isOccupied else { return }
    guard let target = game.configuredDirectory,
      game.executableNames.contains(where: { FileManager.default.isReadableFile(atPath: target.appending(path: $0).path) }) else {
      messages[game] = "未找到游戏文件，请连接安装磁盘或重新定位游戏目录。"
      return
    }
    checking.insert(game)
    messages[game] = "正在关联已有安装…"
    Task {
      defer { checking.remove(game) }
      do {
        try await connect()
        try await linkExistingGame(game, target: target)
        try await requireLinkedDirectory(game, target: target, automaticallyAssociate: false)
        updates.remove(game)
        messages[game] = "已关联当前目录，可以检查更新；关联不代表文件校验通过"
      } catch {
        resetConnection()
        messages[game] = error.localizedDescription
      }
    }
  }

  func migrationCopy(_ game: MiHoYoGame) -> URL? {
    defaults.string(forKey: "games.\(game.rawValue).migrationCopy").map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  func migrateGame(_ game: MiHoYoGame, from source: URL, to container: URL) {
    guard game.region == region, !isOccupied, !blocksLaunch(for: game),
      game.configuredDirectory(defaults: defaults)?.standardizedFileURL.path == source.standardizedFileURL.path,
      migrationCopy(game) == nil else { return }
    busy.insert(game)
    migrationProgress[game] = .init(completedBytes: 0, totalBytes: 0, phase: "正在准备迁移")
    messages[game] = "正在准备迁移，原文件保留"
    migrationTasks[game] = Task {
      defer {
        busy.remove(game); migrationProgress.removeValue(forKey: game)
        migrationTasks.removeValue(forKey: game)
      }
      do {
        let destination = container.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        for directory in [source, destination] {
          if let issue = GameClientDirectoryPolicy.issue(for: directory, client: game,
            locations: GameClientDirectoryPolicy.locations(defaults: defaults)) { throw Failure(issue) }
        }
        try await connect()
        try await requireLinkedDirectory(game, target: source, automaticallyAssociate: false)
        let records = try await query("getLocalGameInfo", ["gameBiz": biz(game), "package": game.officialPackage]) as? [[String: Any]] ?? []
        guard let record = records.first(where: { Self.matchesClient($0, game: game) }),
          ["ready", "need_update"].contains(record["status"] as? String ?? "") else {
          throw Failure("后台客户端尚未空闲，请完成下载、校验或更新后再迁移。")
        }
        let copier = Task.detached(priority: .utility) {
          try await GameStorageManager.migrate(source: source, to: container, game: game) { value in
            await MainActor.run { self.migrationProgress[game] = value }
          }
        }
        let copied = try await withTaskCancellationHandler { try await copier.value } onCancel: { copier.cancel() }
        // Keep a recovery pointer before touching the official installation record.
        defaults.set(copied.path, forKey: "games.\(game.rawValue).migrationCopy")
        defaults.set(source.path, forKey: "games.\(game.rawValue).migrationSource")
        try Task.checkCancellation()
        try await completeMigrationAssociation(game, source: source, target: copied)
      } catch is CancellationError {
        messages[game] = migrationCopy(game) == nil ? "迁移已取消，原文件和启动路径未改变。" : "复制已完成，尚未切换位置；可从菜单完成迁移关联。"
      } catch {
        messages[game] = "迁移未完成：\(error.localizedDescription) 原文件保留。" + (migrationCopy(game) == nil ? "" : " 新副本已校验，可从菜单重试迁移关联。")
      }
    }
  }

  func cancelMigration(_ game: MiHoYoGame) { migrationTasks[game]?.cancel() }

  func retryMigrationAssociation(_ game: MiHoYoGame) {
    guard game.region == region, !isOccupied, !blocksLaunch(for: game), let target = migrationCopy(game),
      let path = defaults.string(forKey: "games.\(game.rawValue).migrationSource") else { return }
    busy.insert(game)
    migrationTasks[game] = Task {
      defer { busy.remove(game); migrationProgress.removeValue(forKey: game); migrationTasks.removeValue(forKey: game) }
      do { try await completeMigrationAssociation(game, source: URL(fileURLWithPath: path), target: target) }
      catch { messages[game] = "迁移关联未完成：\(error.localizedDescription) 两份文件均已保留。" }
    }
  }

  private func completeMigrationAssociation(_ game: MiHoYoGame, source: URL, target: URL) async throws {
    guard game.configuredDirectory(defaults: defaults)?.standardizedFileURL.path == source.standardizedFileURL.path else {
      throw Failure("原安装路径已经改变，未自动切换。")
    }
    _ = try GameStorageManager.recognize(target, game: game)
    if let issue = GameClientDirectoryPolicy.issue(for: target, client: game,
      locations: GameClientDirectoryPolicy.locations(defaults: defaults)) { throw Failure(issue) }
    migrationProgress[game] = .init(completedBytes: 0, totalBytes: 0, phase: "正在切换启动和更新路径")
    messages[game] = "文件校验完成，正在关联新位置…"
    try await connect()
    try await linkExistingGame(game, target: target)
    try await requireLinkedDirectory(game, target: target, automaticallyAssociate: false)
    // Once the official engine has accepted the new path, commit even if cancellation arrived.
    game.saveDirectory(target, defaults: defaults)
    retainedMigrationSources[game] = source
    defaults.removeObject(forKey: "games.\(game.rawValue).migrationCopy")
    defaults.removeObject(forKey: "games.\(game.rawValue).migrationSource")
    updates.remove(game)
    messages[game] = "迁移完成，启动和更新已切换到新位置；原副本保留，可在确认游戏正常后自行清理。"
  }

  enum DirectoryStatus: Equatable { case linked, unregistered, conflict, unavailable }

  static func matchingInstallation(_ found: [[String: Any]], biz: String, path: String, package: String = "") -> [String: Any]? {
    found.first {
      $0["gameBiz"] as? String == biz && $0["path"] as? String == path
        && $0["isFindDir"] as? Bool == true && $0["pathAvailable"] as? Bool == true
        && $0["package"] as? String == package && $0["errorCode"] as? Int == 0
    }
  }

  private func linkExistingGame(_ game: MiHoYoGame, target: URL) async throws {
    let path = "Z:" + target.path.replacingOccurrences(of: "/", with: "\\")
    let found = try await query("findGame", ["gameBiz": biz(game), "package": game.officialPackage, "dir": path]) as? [[String: Any]] ?? []
    guard let candidate = Self.matchingInstallation(found, biz: biz(game), path: path, package: game.officialPackage) else {
      throw Failure("官方服务未能识别此游戏目录，请确认客户端完整后重试。")
    }
    _ = try await query("updateGameSettings", ["gameBiz": biz(game), "package": game.officialPackage, "data": ["autoUpdateWpf": false]])
    let linked = try await query("linkGame", ["games": [candidate]]) as? [[String: Any]] ?? []
    guard linked.contains(where: { Self.matchesClient($0, game: game) && $0["isLinked"] as? Bool == true }) else {
      throw Failure("官方服务未完成目录关联，游戏文件保留，请稍后重试。")
    }
  }

  static func directoryStatus(_ info: [String: Any]?, biz: String, expected: String) -> DirectoryStatus {
    guard let info, info["gameBiz"] as? String == biz,
      let path = info["installPath"] as? String else { return .unavailable }
    if path == expected { return .linked }
    if !path.isEmpty { return .conflict }
    return info["status"] as? String == "need_get_game" ? .unregistered : .unavailable
  }

  private func requireLinkedDirectory(_ game: MiHoYoGame, target: URL, automaticallyAssociate: Bool = true) async throws {
    if let issue = GameClientDirectoryPolicy.issue(for: target, client: game) { throw Failure(issue) }
    let expected = "Z:" + target.path.replacingOccurrences(of: "/", with: "\\")
    var info: [String: Any]?
    for attempt in 0..<10 {
      let result = try await query("getLocalGameInfo", ["gameBiz": biz(game), "package": game.officialPackage])
      info = (result as? [[String: Any]])?.first { Self.matchesClient($0, game: game) }
        ?? (result as? [String: Any])
      if Self.directoryStatus(info, biz: biz(game), expected: expected) != .unavailable { break }
      if attempt < 9 { try await Task.sleep(for: .milliseconds(500)) }
    }
    guard Self.directoryStatus(info, biz: biz(game), expected: expected) != .unavailable else {
      throw Failure("后台安装记录尚未就绪，请稍后重试；当前游戏目录未改变。")
    }
    if automaticallyAssociate && Self.directoryStatus(info, biz: biz(game), expected: expected) == .unregistered {
      guard target.standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL,
        game.executableNames.contains(where: {
          FileManager.default.isReadableFile(atPath: target.appending(path: $0).path)
        }) else { throw Failure("未找到可关联的完整游戏目录，请重新定位。") }
      messages[game] = "正在识别已有游戏，无需重新下载…"
      try await linkExistingGame(game, target: target)
      // Re-read the engine record; a callback alone does not establish association.
      try await requireLinkedDirectory(game, target: target, automaticallyAssociate: false)
      game.saveDirectory(target)
      return
    }
    guard info?["installPath"] as? String == expected else {
      throw Failure("后台安装记录与当前目录不一致，未修改游戏。请先关联目录。\n当前：\(expected)\n后台：\(info?["installPath"] as? String ?? "未登记")")
    }
  }

  enum Operation: String {
    case install, update, repair
    var label: String {
      switch self { case .install: "下载"; case .update: "更新"; case .repair: "修复" }
    }
  }

  static func pendingOperation(for game: MiHoYoGame, defaults: UserDefaults = .standard) -> Operation? {
    guard defaults.string(forKey: "games.\(game.rawValue).pendingInstall") != nil else { return nil }
    return Operation(rawValue: defaults.string(forKey: "games.\(game.rawValue).pendingOperation") ?? "install") ?? .install
  }

  func resume(_ game: MiHoYoGame) {
    guard canResume(game), let operation = Self.pendingOperation(for: game, defaults: defaults) else { return }
    if defaults.bool(forKey: "games.\(game.rawValue).taskDetached") {
      defaults.removeObject(forKey: "games.\(game.rawValue).taskDetached")
      install(game, operation: operation)
      return
    }
    checking.insert(game)
    messages[game] = "正在确认后台任务状态…"
    Task {
      defer { checking.remove(game) }
      do {
        try await connect()
        let encoded = String(data: try JSONSerialization.data(withJSONObject: [biz(game)]), encoding: .utf8)!
        _ = try await evaluate("if(window.__mgbProductDownloads)delete window.__mgbProductDownloads[\(encoded)[0]];true")
        _ = try await query("pauseDownload", ["gameBiz": biz(game), "package": game.officialPackage])
        for _ in 0..<30 {
          try await Task.sleep(for: .seconds(1))
          let event = try await evaluate("window.__mgbProductDownloads?.[\(encoded)[0]] ?? null") as? [String: Any]
          if Self.permitsResubmission(after: event?["status"] as? String) {
            checking.remove(game)
            install(game, operation: operation)
            return
          }
          if event?["status"] as? String == "success", let path = defaults.string(forKey: "games.\(game.rawValue).pendingInstall"),
            game.executableNames.contains(where: { FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: path).appending(path: $0).path) }) {
            game.saveDirectory(URL(fileURLWithPath: path))
            defaults.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
            defaults.removeObject(forKey: "games.\(game.rawValue).pendingOperation")
            messages[game] = "后台任务已完成"
            return
          }
          if event == nil, let path = defaults.string(forKey: "games.\(game.rawValue).pendingInstall") {
            let records = try await query("getLocalGameInfo", ["gameBiz": biz(game), "package": game.officialPackage]) as? [[String: Any]] ?? []
            let expected = "Z:" + path.replacingOccurrences(of: "/", with: "\\")
            if records.contains(where: {
              $0["gameBiz"] as? String == biz(game) && $0["installPath"] as? String == expected
                && $0["status"] as? String == "ready"
            }), game.executableNames.contains(where: {
              FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: path).appending(path: $0).path)
            }) {
              game.saveDirectory(URL(fileURLWithPath: path))
              defaults.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
              defaults.removeObject(forKey: "games.\(game.rawValue).pendingOperation")
              messages[game] = "官方服务确认当前游戏已就绪，已恢复操作；可重新检查更新或校验文件。"
              return
            }
          }
        }
        throw Failure("尚未确认后台任务已暂停或结束，未重复提交。请稍后重新连接任务。")
      } catch {
        resetConnection()
        messages[game] = error.localizedDescription
      }
    }
  }

  private func resetConnection() {
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
  }

  static func permitsResubmission(after status: String?) -> Bool {
    status == "cancelled" || status == "failed"
  }

  func install(_ game: MiHoYoGame, operation: Operation = .install) {
    guard canResume(game) else { return }
    let pendingPath = defaults.string(forKey: "games.\(game.rawValue).pendingInstall")
    let resumingMaintenance = operation != .install && Self.pendingOperation(for: game, defaults: defaults) == operation
    let target: URL
    if operation != .install {
      guard let directory = resumingMaintenance ? pendingPath.map({ URL(fileURLWithPath: $0) }) : game.configuredDirectory,
        FileManager.default.fileExists(atPath: directory.path) else {
        messages[game] = "游戏目录不可访问，请检查磁盘连接。"
        return
      }
      target = directory
    } else if let pendingPath {
      target = URL(fileURLWithPath: pendingPath)
      guard FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path) else {
        messages[game] = "原安装磁盘不可访问，请连接磁盘后继续；不会改到本机重新下载。"
        return
      }
    } else {
    let choice = NSAlert()
    choice.messageText = "安装\(game.clientTitle)"
    choice.informativeText = "推荐位置：\(game.defaultDirectory.path)\n只安装当前游戏，也可以选择外置硬盘。"
    choice.addButton(withTitle: "使用推荐位置")
    choice.addButton(withTitle: "更改位置…")
    choice.addButton(withTitle: "取消")
    let response = choice.runModal()
    if response == .alertFirstButtonReturn {
      target = game.defaultDirectory
    } else if response == .alertSecondButtonReturn {
    let panel = NSOpenPanel()
    panel.title = "选择\(game.title)安装位置"
    panel.message = "只安装当前游戏，文件将存放在所选位置的独立子文件夹。"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Games")
    guard let parent = InstallFolderPicker.runWithStorageNotice(panel) else { return }
    target = parent.appending(path: game.defaultDirectory.lastPathComponent)
    } else { return }
    }
    guard canResume(game) else { return }
    if let issue = GameClientDirectoryPolicy.issue(for: target, client: game) {
      messages[game] = issue
      return
    }
    defaults.removeObject(forKey: "games.\(game.rawValue).taskDetached")
    busy.insert(game)
    activeOperations[game] = operation
    messages[game] = "正在连接官方下载服务…"
    downloadTasks[game] = Task {
      defer { downloadTasks.removeValue(forKey: game); busy.remove(game); paused.remove(game); controllableDownloads.remove(game); activeOperations.removeValue(forKey: game); toggleRequested = false; changingDownloadState = false }
      do {
        if operation == .install && target == game.defaultDirectory {
          try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try await connect()
        let identity = biz(game)
        if operation != .install {
          try await requireLinkedDirectory(game, target: target)
          var required: UInt64 = 10_000_000_000
          if operation == .update && !resumingMaintenance {
            let info = try await checkedUpdate(game)
            guard Self.updateStatus(info) == .available else {
              messages[game] = "未发现可执行的更新，请检查游戏状态。"
              updates.remove(game)
              return
            }
            required += Self.bytes(info["unzipSpace"]) + Self.bytes(info["extraStagingSize"])
          }
          let disk = try FileManager.default.attributesOfFileSystem(forPath: target.path)
          guard let free = (disk[.systemFreeSize] as? NSNumber)?.uint64Value, free >= required else {
            throw Failure("剩余空间不足，任务尚未开始；至少需要 \(StatusFormatting.bytes(required)) 可用空间。")
          }
          defaults.set(target.path, forKey: "games.\(game.rawValue).pendingInstall")
          defaults.set(operation.rawValue, forKey: "games.\(game.rawValue).pendingOperation")
          _ = try await evaluate("if(window.__mgbProductDownloads)delete window.__mgbProductDownloads['\(identity)'];true")
          var arguments: [String: Any] = ["gameBiz": identity, "package": game.officialPackage]
          if resumingMaintenance && operation == .update { arguments["isInterrupted"] = true }
          let result = try await query(operation == .repair ? "repairGame" : "startDownload", arguments)
          if let result = result as? [String: Any], let outcome = result["result"] as? String, outcome != "success" {
            throw Failure("官方服务拒绝任务，请检查更新状态后重试。")
          }
        } else {
        var linked: [String: Any]?
        for attempt in 0..<10 {
          let local = try await query("getLocalGameInfo", ["gameBiz": identity, "package": game.officialPackage])
          linked = (local as? [[String: Any]])?.first { Self.matchesClient($0, game: game) }
            ?? (local as? [String: Any])
          if linked?["gameBiz"] as? String == identity,
            linked?["installPath"] is String,
            let status = linked?["status"] as? String, !status.isEmpty { break }
          if attempt < 9 { try await Task.sleep(for: .seconds(1)) }
        }
        guard linked?["gameBiz"] as? String == identity,
          linked?["installPath"] is String,
          let localStatus = linked?["status"] as? String, !localStatus.isEmpty else {
          throw Failure("后台安装记录尚未就绪，未开始下载。请稍后重试。")
        }
        let windows = "Z:" + target.path.replacingOccurrences(of: "/", with: "\\")
        let recordedPath = linked?["installPath"] as? String ?? ""
        let resuming = recordedPath == windows && linked?["status"] as? String == "need_install"
        guard recordedPath.isEmpty || resuming else {
          throw Failure("官方服务已有此游戏的安装记录，请先定位已有目录，避免覆盖。")
        }
        if !resuming, FileManager.default.fileExists(atPath: target.path),
          try !FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty {
          throw Failure("目标游戏文件夹非空，请选择其他位置或定位已有游戏。")
        }
        guard let info = try await query("getGameInstallInfo", ["gameBiz": identity, "package": game.officialPackage, "dir": windows]) as? [String: Any],
          info["result"] as? String == "success",
          let package = info["gamePackage"] as? [String: Any] else {
          throw Failure("官方服务未返回安装信息，请稍后重试。")
        }
        let voices = (info["voicePackages"] as? [[String: Any]] ?? []).filter { $0["lang"] as? String == "zh-cn" }
        let required = Self.bytes(package["unzipSpace"]) + voices.reduce(0) { $0 + Self.bytes($1["unzipSpace"]) }
          + Self.bytes(info["extraStagingSize"]) + 10_000_000_000
        let disk = try FileManager.default.attributesOfFileSystem(forPath: target.deletingLastPathComponent().path)
        let free = (disk[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        guard required > 10_000_000_000, free >= required else {
          throw Failure("此游戏安装需要约 \(StatusFormatting.bytes(required)) 可用空间，当前位置只有 \(StatusFormatting.bytes(free))。请选择其他磁盘。")
        }
        messages[game] = "正在创建官方下载任务…"
        defaults.set(target.path, forKey: "games.\(game.rawValue).pendingInstall")
        defaults.set(operation.rawValue, forKey: "games.\(game.rawValue).pendingOperation")
        let result = try await query("startDownload", resuming ? ["gameBiz": identity, "package": game.officialPackage, "isInterrupted": true] : [
          "gameBiz": identity, "package": game.officialPackage, "path": windows,
          "voiceLangList": voices.compactMap { $0["lang"] as? String }, "packageType": "FULL",
          "createShortcut": false, "createShortcutInStartMenu": false,
        ])
        if let result = result as? [String: Any], let outcome = result["result"] as? String, outcome != "success" {
          throw Failure("官方服务拒绝创建下载任务，请检查安装位置后重试。")
        }
        }
        messages[game] = "官方下载任务已提交，等待进度…"
        controllableDownloads.insert(game)
        var connectionFailures = 0
        for _ in 0..<28800 {
          try await Task.sleep(for: .seconds(3))
          if toggleRequested {
            toggleRequested = false
            let wasPaused = paused.contains(game)
            _ = try await evaluate("if(window.__mgbProductDownloads)delete window.__mgbProductDownloads['\(identity)'];true")
            _ = try await query(wasPaused ? "resumeDownload" : "pauseDownload", ["gameBiz": identity, "package": game.officialPackage])
          }
          let encoded = String(data: try JSONSerialization.data(withJSONObject: [identity]), encoding: .utf8)!
          // The official frontend can reload after startup. Reinstall the listener
          // in the new document instead of treating navigation as download failure.
          let snapshot: [String: Any]?
          do {
            snapshot = try await evaluate("(()=>{if(!window.HYPClient)return null;if(!window.__mgbProductDownloads){window.__mgbProductDownloads={};window.HYPClient.addEventListener('updateDownloadStatus',d=>{if(typeof d==='string')d=JSON.parse(d);if(d.gameBiz)window.__mgbProductDownloads[d.gameBiz]=d})}return window.__mgbProductDownloads[\(encoded)[0]] || null})()") as? [String: Any]
            connectionFailures = 0
          } catch {
            connectionFailures += 1
            guard connectionFailures < 3 else { throw Failure("下载进度连接中断，文件已保留。重新点击安装并选择同一位置可接回任务。") }
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            try await connect()
            continue
          }
          guard let snapshot else { continue }
          let status = snapshot["status"] as? String ?? ""
          if status == "cancelled" {
            paused.insert(game)
            changingDownloadState = false
          } else if ["progressing", "verifying", "success"].contains(status), !changingDownloadState || paused.contains(game) {
            paused.remove(game)
            changingDownloadState = false
          }
          let percent = (snapshot["percent"] as? NSNumber)?.doubleValue ?? 0
          let speed = Self.bytes(snapshot["downloadSpeed"])
          if changingDownloadState {
            messages[game] = paused.contains(game) ? "正在恢复下载…" : "正在暂停下载…"
          } else if paused.contains(game) {
            messages[game] = "已暂停，下载文件保留"
          } else if status == "verifying" {
            messages[game] = "正在校验文件 \(String(format: "%.1f", percent))%"
          } else {
            messages[game] = "正在下载 \(String(format: "%.1f", percent))% · \(StatusFormatting.bytes(speed))/s"
          }
          if status == "success" {
            guard game.executableNames.contains(where: { FileManager.default.isReadableFile(atPath: target.appending(path: $0).path) }) else {
              throw Failure("官方任务结束，但没有找到游戏主程序，请检查安装结果。")
            }
            game.saveDirectory(target)
            defaults.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
            defaults.removeObject(forKey: "games.\(game.rawValue).pendingOperation")
            updates.remove(game)
            messages[game] = operation == .repair ? "校验修复完成" : operation == .update ? "更新完成" : "安装完成"
            return
          }
          if status == "failed" { throw Failure("下载失败（\(snapshot["errorCode"] ?? "未知错误")），已下载文件保留，可选择同一位置继续。") }
        }
        throw Failure("未收到下载完成状态，游戏文件已保留。")
      } catch {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        messages[game] = "\(error.localizedDescription)"
      }
    }
  }

  private static func bytes(_ value: Any?) -> UInt64 {
    if let number = value as? NSNumber { return number.uint64Value }
    return UInt64(value as? String ?? "") ?? 0
  }

  private func connect() async throws {
    if commands != nil { return }
    if socket != nil { return }
    guard !connecting else { throw Failure("官方下载服务正在启动，请稍后重试。") }
    connecting = true
    defer { connecting = false }
    let prefix = enginePrefix
    if OfficialEngineDiagnostics.portIsOccupied(enginePort) {
      if (try? await attachEngine()) == true { diagnostics.record("engine_reconnected"); return }
      diagnostics.record("debug_port_conflict", code: Int32(enginePort))
      throw Failure("本机端口 \(enginePort) 已被占用，无法连接下载服务。请关闭独立运行的米哈游启动器后重试；可在菜单查看后台诊断。")
    }
    let executable: URL
    do { executable = try await prepareEngine(prefix: prefix) }
    catch { diagnostics.record("engine_prepare_failed"); throw error }
    guard let window = windowSupport else { throw Failure("后台下载组件缺失，请重新下载完整应用包。") }
    let process = Process()
    process.executableURL = try GameRuntimePaths.resolveRuntime().wine
    process.arguments = [executable.path, "--remote-debugging-port=\(enginePort)", "--remote-debugging-address=127.0.0.1"]
    process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
      "TMPDIR": NSTemporaryDirectory(), "LANG": "zh_CN.UTF-8", "WINEPREFIX": prefix.path, "WINEDEBUG": "-all",
      "MGB_BACKGROUND_ENGINE": "1", "DYLD_INSERT_LIBRARIES": window.adapter.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    diagnostics.record("engine_started", code: process.processIdentifier)
    process.terminationHandler = { [weak self] process in
      let status = process.terminationStatus
      Task { @MainActor [weak self] in self?.diagnostics.record("engine_exited", code: status) }
    }
    engine = process
    for _ in 0..<30 {
      do {
        if try await attachEngine() { diagnostics.record("engine_connected"); return }
      } catch { socket?.cancel(with: .goingAway, reason: nil); socket = nil }
      try await Task.sleep(for: .seconds(1))
    }
    diagnostics.record("engine_connect_timeout")
    throw Failure("官方下载服务启动超时，未开始下载。请在菜单查看后台诊断后重试。")
  }

  private func attachEngine() async throws -> Bool {
    do {
        guard await OfficialEngineOwnership.ownsListener(port: enginePort,
          prefix: enginePrefix.path) else { return false }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(enginePort)/json/list")!)
        request.timeoutInterval = 2
        let (data, _) = try await URLSession.shared.data(for: request)
        let pages = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        if let page = pages.first(where: { ($0["url"] as? String ?? "").hasPrefix("https://" + region.frontendHost + "/hypfe/") }),
          let address = page["webSocketDebuggerUrl"] as? String, let url = URL(string: address), url.host == "127.0.0.1" {
          let connection = URLSession.shared.webSocketTask(with: url)
          connection.resume()
          socket = connection
          _ = try await evaluate("(()=>{window.__mgbProductDownloads ??= {}; if(!window.__mgbProductDownloadListener){window.__mgbProductDownloadListener=d=>{if(typeof d==='string')d=JSON.parse(d);if(d.gameBiz)window.__mgbProductDownloads[d.gameBiz]=d};window.HYPClient.addEventListener('updateDownloadStatus',window.__mgbProductDownloadListener)}return true})()")
          _ = try await evaluate("(()=>{CefViewQuery({request:JSON.stringify({action:'hideWindow',data:{}}),onSuccess:()=>{},onFailure:()=>{}});return true})()")
          return true
        }
      return false
    } catch {
      socket?.cancel(with: .goingAway, reason: nil); socket = nil
      throw error
    }
  }

  private func prepareEngine(prefix: URL) async throws -> URL {
    if (try? GameRuntimePaths.resolveRuntime()) == nil {
      let assets = try await RuntimePreparationAssets.resolveOrDownload()
      try await Task.detached { try RuntimeAssetInstaller.install(assets: assets) }.value
    }
    let destination = prefix.appending(path: "drive_c/MacGameBridge/miHoYo Launcher")
    let executable = destination.appending(path: "1.18.0.380/HYP.exe")
    if FileManager.default.isReadableFile(atPath: executable.path) { return executable }
    let bundledExtractor = Bundle.main.resourceURL?.appending(path: "RuntimeAssets/7zz")
    let extractor: URL
    if let bundledExtractor, FileManager.default.isExecutableFile(atPath: bundledExtractor.path) {
      extractor = bundledExtractor
    } else {
      extractor = try await RuntimeAssetDownload.shared.obtain(RuntimeDownloadCatalog.extractor)
    }
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let url = region.engineDownloadURL
    let temporary: URL
    if let engineArchiveOverride {
      temporary = engineArchiveOverride
    } else {
      let (download, response) = try await URLSession.shared.download(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        try? FileManager.default.removeItem(at: download)
        throw Failure("官方下载组件暂时无法获取，请稍后重试。")
      }
      temporary = download
    }
    defer { if engineArchiveOverride == nil { try? FileManager.default.removeItem(at: temporary) } }
    let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
    guard data.count == region.engineByteSize,
      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == region.engineSHA256 else {
      throw Failure("官方下载组件校验不匹配，已停止安装。请更新 MacGameBridge 后重试。")
    }
    let wine = try GameRuntimePaths.resolveRuntime().wine
    try await Task.detached {
      func run(_ program: URL, _ arguments: [String], warningAllowed: Bool = false) throws {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "WINEPREFIX": prefix.path, "WINEDEBUG": "-all"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || (warningAllowed && process.terminationStatus == 1) else { throw Failure("下载组件准备失败（\(process.terminationStatus)），请重试。") }
      }
      try run(wine, ["wineboot", "-u"])
      try run(extractor, ["x", temporary.path, "-o" + destination.path, "-y"], warningAllowed: true)
    }.value
    guard FileManager.default.isReadableFile(atPath: executable.path) else { throw Failure("下载组件解压不完整，请重试。") }
    return executable
  }

  private func query(_ action: String, _ arguments: [String: Any]) async throws -> Any? {
    if let commands { return try await commands.query(action, arguments) }
    let json = String(data: try JSONSerialization.data(withJSONObject: ["action": action, "data": arguments]), encoding: .utf8)!
    let literal = String(data: try JSONSerialization.data(withJSONObject: [json]), encoding: .utf8)!
    return try await evaluate("Promise.race([new Promise((resolve,reject)=>window.CefViewQuery({request:\(literal)[0],onSuccess:r=>resolve(r?JSON.parse(r):null),onFailure:c=>reject(Error(String(c)))})),new Promise((_,reject)=>setTimeout(()=>reject(Error('official-query-timeout')),180000))])", timeoutSeconds: 190)
  }

  private func evaluate(_ expression: String, timeoutSeconds: Int = 20) async throws -> Any? {
    guard let socket else { throw Failure("官方下载连接已断开。") }
    let timeout = Task { @MainActor in
      do { try await Task.sleep(for: .seconds(timeoutSeconds)); socket.cancel(with: .goingAway, reason: nil) }
      catch {}
    }
    defer { timeout.cancel() }
    requestID += 1
    let id = requestID
    let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": "Runtime.evaluate", "params": ["expression": expression, "awaitPromise": true, "returnByValue": true]])
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    while true {
      let message = try await socket.receive()
      let bytes: Data
      switch message { case .data(let data): bytes = data; case .string(let text): bytes = Data(text.utf8); @unknown default: continue }
      guard let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], response["id"] as? Int == id else { continue }
      guard response["error"] == nil, let result = response["result"] as? [String: Any], result["exceptionDetails"] == nil else { throw Failure("官方接口调用失败，请重新打开应用后重试。") }
      return (result["result"] as? [String: Any])?["value"]
    }
  }

  private struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }
}
