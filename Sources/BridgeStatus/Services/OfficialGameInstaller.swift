import AppKit
import Foundation
import CryptoKit

/// Bridges the official install engine; each request is scoped to one CN game.
@MainActor
final class OfficialGameInstaller: ObservableObject {
  static let shared = OfficialGameInstaller()
  @Published private(set) var messages: [MiHoYoGame: String] = [:]
  @Published private(set) var busy: Set<MiHoYoGame> = []
  @Published private(set) var paused: Set<MiHoYoGame> = []
  @Published private(set) var changingDownloadState = false
  @Published private(set) var checking: Set<MiHoYoGame> = []
  @Published private(set) var updates: Set<MiHoYoGame> = []
  @Published private(set) var uninstalling: Set<MiHoYoGame> = []
  @Published private(set) var controllableDownloads: Set<MiHoYoGame> = []
  @Published private(set) var activeOperations: [MiHoYoGame: Operation] = [:]
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
    busy.isEmpty && checking.isEmpty && !UserDefaults.standard.bool(forKey: "games.\(game.rawValue).taskDetached") && (
      Self.pendingOperation(for: game) != nil || hasPendingUninstall(game))
  }

  func endTaskKeepingFiles(_ game: MiHoYoGame) {
    guard canEndTask(game) else { return }
    checking.insert(game)
    messages[game] = "正在停止后台任务，保留游戏文件…"
    Task {
      defer { checking.remove(game) }
      do {
        let runtime = try GameRuntimePaths.resolveRuntime()
        let server = runtime.wine.deletingLastPathComponent().appending(path: "wineserver")
        let prefix = GameRuntimePaths.userStorageRoot.appending(path: "Installer/prefix")
        resetConnection()
        for argument in ["-k", "-w"] {
          let process = Process()
          process.executableURL = server
          process.arguments = [argument]
          process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "WINEPREFIX": prefix.path]
          process.standardOutput = FileHandle.nullDevice
          process.standardError = FileHandle.nullDevice
          try process.run()
          for _ in 0..<100 {
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(100))
          }
          guard !process.isRunning else { process.terminate(); throw Failure("后台停止超时，任务保护保留，请查看后台诊断。") }
          diagnostics.record("engine_stop_result", code: process.terminationStatus)
          guard process.terminationStatus == 0 else { throw Failure("后台任务未确认停止，未解除保护。请查看后台诊断。") }
        }
        engine = nil
        UserDefaults.standard.set(true, forKey: "games.\(game.rawValue).taskDetached")
        messages[game] = "任务已结束，文件与续传记录保留；其他游戏可继续使用。"
        diagnostics.record("task_detached_" + game.rawValue)
      } catch { messages[game] = error.localizedDescription; diagnostics.record("task_stop_failed") }
    }
  }

  var isOccupied: Bool { !busy.isEmpty || !checking.isEmpty || !Self.outstandingGames().isEmpty }

  func blockingMessage(for game: MiHoYoGame) -> String? {
    let tasks = busy.union(checking).union(Self.outstandingGames())
    guard let other = MiHoYoGame.allCases.first(where: { $0 != game && tasks.contains($0) }) else { return nil }
    return "\(other.title)有进行中或待确认的任务，请先切换到该游戏处理。"
  }

  func canResume(_ game: MiHoYoGame) -> Bool {
    busy.isEmpty && checking.isEmpty && Self.outstandingGames().isSubset(of: [game])
      && UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingUninstall") == nil
  }

  func hasPendingUninstall(_ game: MiHoYoGame) -> Bool {
    UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingUninstall") != nil
  }

  func reconcileUninstall(_ game: MiHoYoGame) {
    guard busy.isEmpty, checking.isEmpty, Self.outstandingGames().isSubset(of: [game]),
      let path = UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingUninstall") else { return }
    checking.insert(game)
    Task {
      defer { checking.remove(game) }
      do {
        try await connect()
        let records = try await query("getLocalGameInfo", ["gameBiz": biz(game)]) as? [[String: Any]] ?? []
        let record = records.first { $0["gameBiz"] as? String == biz(game) }
        if UserDefaults.standard.bool(forKey: "games.\(game.rawValue).taskDetached"),
          Self.uninstallCanBeRestored(record, gameBiz: biz(game), path: path),
          game.executableNames.contains(where: { FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: path).appending(path: $0).path) }) {
          UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingUninstall")
          UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).taskDetached")
          messages[game] = "卸载未完成，已恢复管理入口；建议先校验并修复游戏。"
          return
        }
        guard record?["status"] as? String == "need_get_game",
          record?["installPath"] as? String == "",
          !game.executableNames.contains(where: { FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appending(path: $0).path) }) else {
          throw Failure("后台卸载状态尚未确认，安装记录与任务保护已保留，请稍后再检查。")
        }
        for key in ["pendingUninstall", "pendingInstall", "pendingOperation", "installationRoot", "taskDetached"] {
          UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).\(key)")
        }
        if game == .genshin { UserDefaults.standard.removeObject(forKey: "games.genshinCN.installationRoot") }
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

  init(resourceURL: URL? = Bundle.main.resourceURL) {
    windowSupport = NativeGameWindowSupport.resolve(resourceURL: resourceURL)
  }

  func togglePause() {
    guard !changingDownloadState, !controllableDownloads.isEmpty else { return }
    changingDownloadState = true
    toggleRequested = true
  }

  /// The confirmed directory must still match the official engine's record.
  func uninstall(_ game: MiHoYoGame, expectedDirectory: URL) async -> Bool {
    guard !isOccupied else { return false }
    UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).taskDetached")
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
      UserDefaults.standard.set(expectedDirectory.path, forKey: "games.\(game.rawValue).pendingUninstall")
      let reply = try await query("uninstallGame", ["gameBiz": biz(game), "package": "",
        "path": "Z:" + expectedDirectory.path.replacingOccurrences(of: "/", with: "\\"), "killProcess": false])
      guard (reply as? [String: Any])?["result"] as? String == "success" else {
        if (reply as? [String: Any])?["result"] as? String == "fail" {
          UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingUninstall")
        }
        throw Failure("官方服务未完成卸载，原目录记录已保留，请检查游戏是否仍在运行。")
      }
      guard !game.executableNames.contains(where: {
        FileManager.default.fileExists(atPath: expectedDirectory.appending(path: $0).path)
      }) else { throw Failure("卸载后仍检测到游戏文件，未清除安装记录。") }
      for key in ["installationRoot", "pendingInstall", "pendingOperation"] {
        UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).\(key)")
      }
      if game == .genshin { UserDefaults.standard.removeObject(forKey: "games.genshinCN.installationRoot") }
      updates.remove(game)
      UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingUninstall")
      messages[game] = "游戏已卸载，兼容环境与其他游戏保留。"
      return true
    } catch {
      messages[game] = error.localizedDescription
      resetConnection()
      return false
    }
  }

  private func biz(_ game: MiHoYoGame) -> String {
    switch game {
    case .genshin: "hk4e_cn"
    case .starRail: "hkrpg_cn"
    case .zenlessZoneZero: "nap_cn"
    case .honkaiImpact3: "bh3_cn"
    }
  }

  func checkForUpdates(_ game: MiHoYoGame) {
    guard !isOccupied else { return }
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
    guard let info = try await query("checkGameUpdate", ["gameBiz": biz(game), "package": ""]) as? [String: Any],
      info["result"] as? String == "success" else { throw Failure("官方更新检查未成功，请稍后重试。") }
    return info
  }

  func associateDirectory(_ game: MiHoYoGame) {
    guard !isOccupied else { return }
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

  enum DirectoryStatus: Equatable { case linked, unregistered, conflict, unavailable }

  static func matchingInstallation(_ found: [[String: Any]], biz: String, path: String) -> [String: Any]? {
    found.first {
      $0["gameBiz"] as? String == biz && $0["path"] as? String == path
        && $0["isFindDir"] as? Bool == true && $0["pathAvailable"] as? Bool == true
        && $0["package"] as? String == "" && $0["errorCode"] as? Int == 0
    }
  }

  private func linkExistingGame(_ game: MiHoYoGame, target: URL) async throws {
    let path = "Z:" + target.path.replacingOccurrences(of: "/", with: "\\")
    let found = try await query("findGame", ["gameBiz": biz(game), "dir": path]) as? [[String: Any]] ?? []
    guard let candidate = Self.matchingInstallation(found, biz: biz(game), path: path) else {
      throw Failure("官方服务未能识别此游戏目录，请确认客户端完整后重试。")
    }
    _ = try await query("updateGameSettings", ["gameBiz": biz(game), "data": ["autoUpdateWpf": false]])
    let linked = try await query("linkGame", ["games": [candidate]]) as? [[String: Any]] ?? []
    guard linked.contains(where: { $0["gameBiz"] as? String == biz(game) && $0["isLinked"] as? Bool == true }) else {
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
    let expected = "Z:" + target.path.replacingOccurrences(of: "/", with: "\\")
    var info: [String: Any]?
    for attempt in 0..<10 {
      let result = try await query("getLocalGameInfo", ["gameBiz": biz(game)])
      info = (result as? [[String: Any]])?.first { $0["gameBiz"] as? String == biz(game) }
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
    guard canResume(game), let operation = Self.pendingOperation(for: game) else { return }
    if UserDefaults.standard.bool(forKey: "games.\(game.rawValue).taskDetached") {
      UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).taskDetached")
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
        _ = try await query("pauseDownload", ["gameBiz": biz(game), "package": ""])
        for _ in 0..<30 {
          try await Task.sleep(for: .seconds(1))
          let event = try await evaluate("window.__mgbProductDownloads?.[\(encoded)[0]] ?? null") as? [String: Any]
          if Self.permitsResubmission(after: event?["status"] as? String) {
            checking.remove(game)
            install(game, operation: operation)
            return
          }
          if event?["status"] as? String == "success", let path = UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingInstall"),
            game.executableNames.contains(where: { FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: path).appending(path: $0).path) }) {
            game.saveDirectory(URL(fileURLWithPath: path))
            UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
            UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingOperation")
            messages[game] = "后台任务已完成"
            return
          }
          if event == nil, let path = UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingInstall") {
            let records = try await query("getLocalGameInfo", ["gameBiz": biz(game)]) as? [[String: Any]] ?? []
            let expected = "Z:" + path.replacingOccurrences(of: "/", with: "\\")
            if records.contains(where: {
              $0["gameBiz"] as? String == biz(game) && $0["installPath"] as? String == expected
                && $0["status"] as? String == "ready"
            }), game.executableNames.contains(where: {
              FileManager.default.isReadableFile(atPath: URL(fileURLWithPath: path).appending(path: $0).path)
            }) {
              game.saveDirectory(URL(fileURLWithPath: path))
              UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
              UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingOperation")
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
    let pendingPath = UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingInstall")
    let resumingMaintenance = operation != .install && Self.pendingOperation(for: game) == operation
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
    choice.messageText = "安装\(game.title)"
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
    guard panel.runModal() == .OK, let parent = panel.url else { return }
    target = parent.appending(path: game.defaultDirectory.lastPathComponent)
    } else { return }
    }
    guard canResume(game) else { return }
    UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).taskDetached")
    busy.insert(game)
    activeOperations[game] = operation
    messages[game] = "正在连接官方下载服务…"
    Task {
      defer { busy.remove(game); paused.remove(game); controllableDownloads.remove(game); activeOperations.removeValue(forKey: game); toggleRequested = false; changingDownloadState = false }
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
          UserDefaults.standard.set(target.path, forKey: "games.\(game.rawValue).pendingInstall")
          UserDefaults.standard.set(operation.rawValue, forKey: "games.\(game.rawValue).pendingOperation")
          _ = try await evaluate("if(window.__mgbProductDownloads)delete window.__mgbProductDownloads['\(identity)'];true")
          var arguments: [String: Any] = ["gameBiz": identity, "package": ""]
          if resumingMaintenance && operation == .update { arguments["isInterrupted"] = true }
          let result = try await query(operation == .repair ? "repairGame" : "startDownload", arguments)
          if let result = result as? [String: Any], let outcome = result["result"] as? String, outcome != "success" {
            throw Failure("官方服务拒绝任务，请检查更新状态后重试。")
          }
        } else {
        var linked: [String: Any]?
        for attempt in 0..<10 {
          let local = try await query("getLocalGameInfo", ["gameBiz": identity])
          linked = (local as? [[String: Any]])?.first { $0["gameBiz"] as? String == identity }
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
        guard let info = try await query("getGameInstallInfo", ["gameBiz": identity, "dir": windows]) as? [String: Any],
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
        UserDefaults.standard.set(target.path, forKey: "games.\(game.rawValue).pendingInstall")
        UserDefaults.standard.set(operation.rawValue, forKey: "games.\(game.rawValue).pendingOperation")
        let result = try await query("startDownload", resuming ? ["gameBiz": identity, "package": "", "isInterrupted": true] : [
          "gameBiz": identity, "package": info["package"] as? String ?? "", "path": windows,
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
            _ = try await query(wasPaused ? "resumeDownload" : "pauseDownload", ["gameBiz": identity, "package": ""])
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
            UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
            UserDefaults.standard.removeObject(forKey: "games.\(game.rawValue).pendingOperation")
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
    if socket != nil { return }
    guard !connecting else { throw Failure("官方下载服务正在启动，请稍后重试。") }
    connecting = true
    defer { connecting = false }
    let prefix = GameRuntimePaths.userStorageRoot.appending(path: "Installer/prefix")
    if OfficialEngineDiagnostics.portIsOccupied(19223) {
      if (try? await attachEngine()) == true { diagnostics.record("engine_reconnected"); return }
      diagnostics.record("debug_port_conflict", code: 19223)
      throw Failure("本机端口 19223 已被占用，无法连接下载服务。请关闭独立运行的米哈游启动器后重试；可在菜单查看后台诊断。")
    }
    let executable: URL
    do { executable = try await prepareEngine(prefix: prefix) }
    catch { diagnostics.record("engine_prepare_failed"); throw error }
    guard let window = windowSupport else { throw Failure("后台下载组件缺失，请重新下载完整应用包。") }
    let process = Process()
    process.executableURL = try GameRuntimePaths.resolveRuntime().wine
    process.arguments = [executable.path, "--remote-debugging-port=19223", "--remote-debugging-address=127.0.0.1"]
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
        guard await OfficialEngineOwnership.ownsListener(port: 19223,
          prefix: GameRuntimePaths.userStorageRoot.appending(path: "Installer/prefix").path) else { return false }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:19223/json/list")!)
        request.timeoutInterval = 2
        let (data, _) = try await URLSession.shared.data(for: request)
        let pages = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        if let page = pages.first(where: { ($0["url"] as? String ?? "").hasPrefix("https://hyp-api.mihoyo.com/hypfe/") }),
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
      guard let assets = RuntimePreparationAssets.resolve() else { throw Failure("运行组件缺失，请重新下载完整应用包。") }
      try await Task.detached { try RuntimeAssetInstaller.install(assets: assets) }.value
    }
    let destination = prefix.appending(path: "drive_c/MacGameBridge/miHoYo Launcher")
    let executable = destination.appending(path: "1.18.0.380/HYP.exe")
    if FileManager.default.isReadableFile(atPath: executable.path) { return executable }
    guard let extractor = Bundle.main.resourceURL?.appending(path: "RuntimeAssets/7zz"),
      FileManager.default.isExecutableFile(atPath: extractor.path) else { throw Failure("下载组件缺失，请重新下载完整应用包。") }
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    let url = URL(string: "https://hyp-webstatic.mihoyo.com/hyp-client/miHoYoLauncher_1.18.exe")!
    let (temporary, response) = try await URLSession.shared.download(from: url)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("官方下载组件暂时无法获取，请稍后重试。") }
    let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
    guard data.count == 209837072,
      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == "674ff7201b42058cd569889ccbdc15cdd97709b1442876757a0f81785d716517" else {
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
