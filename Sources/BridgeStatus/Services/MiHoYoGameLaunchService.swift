import AppKit
import Foundation
import Combine

@MainActor
final class MiHoYoGameLaunchService: ObservableObject {
  @Published private(set) var state: GameLaunchState = .ready
  @Published private(set) var activeGame: MiHoYoGame?
  @Published private(set) var stateGame: MiHoYoGame?
  @Published private(set) var latestLogURL: URL?

  private var gameProcess: Process?
  private var helperProcess: Process?
  private var logHandle: FileHandle?
  private var launchTask: Task<Void, Never>?
  private let genshin = GameLaunchService()
  private let genshinRuntime = RuntimePreparationService()
  private var subscriptions = Set<AnyCancellable>()

  init() {
    genshin.$state.sink { [weak self] state in
      guard let self, self.stateGame == .genshin else { return }
      self.state = state
      self.activeGame = state == .running ? .genshin : nil
    }.store(in: &subscriptions)
    genshin.$latestLogURL.sink { [weak self] url in
      guard self?.stateGame == .genshin else { return }
      self?.latestLogURL = url
    }.store(in: &subscriptions)
  }

  func launch(_ game: MiHoYoGame) {
    guard launchTask == nil, gameProcess?.isRunning != true, state != .running else { return }
    stateGame = game
    guard let executable = game.executableURL else {
      state = .unavailable("未找到\(game.title)的完整游戏目录")
      return
    }
    state = .preparing
    launchTask = Task { [weak self] in
      guard let self else { return }
      do {
        if game == .genshin {
          genshinRuntime.refresh()
          if genshinRuntime.state != .ready {
            genshinRuntime.prepare()
            while genshinRuntime.state == .preparing || genshinRuntime.state == .checking {
              try await Task.sleep(for: .milliseconds(200))
            }
          }
          guard genshinRuntime.state == .ready else {
            state = .failed(Self.runtimePreparationIssue(genshinRuntime.state))
            launchTask = nil
            return
          }
          try Task.checkCancellation()
          genshin.launchGenshin(preferences: .load())
          launchTask = nil
          return
        }
        let plan = try MiHoYoLaunchPlan.resolve(game: game, executable: executable)
        try await Task.detached(priority: .userInitiated) {
          try plan.prepareIfNeeded()
        }.value
        if game == .starRail {
          try await StarRailDispatchWindow.activate(using: plan.dispatchScript)
        }
        try Task.checkCancellation()
        try start(plan)
      } catch is CancellationError {
        state = .ready
        stateGame = nil
      } catch {
        state = .failed(error.localizedDescription)
      }
      launchTask = nil
    }
  }

  func stop() {
    if stateGame == .genshin {
      launchTask?.cancel()
      genshin.stopGame()
      return
    }
    launchTask?.cancel()
    launchTask = nil
    helperProcess?.terminate()
    gameProcess?.terminate()
    state = .stopping
    guard let game = activeGame,
      let executable = game.executableURL,
      let plan = try? MiHoYoLaunchPlan.resolve(game: game, executable: executable)
    else {
      finish()
      return
    }
    Task { [weak self] in
      let server = plan.wine.deletingLastPathComponent().appending(path: "wineserver")
      let process = Process()
      process.executableURL = server
      process.arguments = ["-k"]
      process.environment = plan.environment
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        for _ in 0..<100 {
          if !process.isRunning { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard !process.isRunning else {
          process.terminate()
          self?.state = .failed("停止游戏超时，请确认游戏窗口已关闭后重试。")
          return
        }
        guard process.terminationStatus == 0 else {
          self?.state = .failed("停止游戏失败，请关闭游戏窗口后重试。")
          return
        }
        self?.finish()
      } catch { self?.state = .failed("无法停止游戏：\(error.localizedDescription)") }
    }
  }

  static func runtimePreparationIssue(_ state: RuntimePreparationState) -> String {
    switch state {
    case .failed(let reason), .unavailable(let reason): return "运行环境准备失败：\(reason)"
    default: return "运行环境尚未准备完成，请重试。"
    }
  }

  func openLatestLog() {
    guard let latestLogURL else { return }
    NSWorkspace.shared.open(latestLogURL)
  }

  private func start(_ plan: MiHoYoLaunchPlan) throws {
    try FileManager.default.createDirectory(
      at: plan.diagnosticsDirectory, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let logURL = plan.diagnosticsDirectory.appending(
      path: "\(plan.game.rawValue)-\(formatter.string(from: Date())).log")
    guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
      throw MiHoYoLaunchError.cannotCreateLog
    }
    let handle = try FileHandle(forWritingTo: logURL)
    var started = false
    defer {
      if !started {
        helperProcess?.terminate()
        helperProcess = nil
        try? handle.close()
      }
    }
    try handle.write(contentsOf: Data("MGB_GAME id=\(plan.game.rawValue) profile=\(plan.profileName)\n".utf8))

    let launched = Process()
    launched.executableURL = plan.wine
    launched.currentDirectoryURL = plan.executable.deletingLastPathComponent()
    launched.arguments = plan.arguments
    var environment = plan.environment
    let preferences = GameLaunchPreferences.load()
    environment["MTL_HUD_ENABLED"] = preferences.metalHUDEnabled ? "1" : "0"
    environment["MGB_NATIVE_FULLSCREEN"] = preferences.windowMode == .fullScreen ? "1" : "0"
    launched.environment = environment
    launched.standardInput = FileHandle.nullDevice
    launched.standardOutput = handle
    launched.standardError = handle
    if let helperArguments = plan.windowHelperArguments {
      let helper = Process()
      helper.executableURL = plan.wine
      helper.arguments = helperArguments
      helper.environment = environment
      helper.standardInput = FileHandle.nullDevice
      helper.standardOutput = handle
      helper.standardError = handle
      try helper.run()
      helperProcess = helper
    }

    try launched.run()
    started = true
    gameProcess = launched
    logHandle = handle
    latestLogURL = logURL
    activeGame = plan.game
    stateGame = plan.game
    state = .running
    if preferences.hideAfterLaunch { NSApp.hide(nil) }

    Task { [weak self, weak launched] in
      guard let launched else { return }
      while launched.isRunning { try? await Task.sleep(for: .seconds(1)) }
      guard self?.state != .stopping, self?.gameProcess === launched else { return }
      self?.finish(exitStatus: launched.terminationStatus)
    }
  }

  private func finish(exitStatus: Int32? = nil) {
    let finishedGame = activeGame ?? stateGame
    helperProcess?.terminate()
    helperProcess = nil
    gameProcess = nil
    try? logHandle?.close()
    logHandle = nil
    activeGame = nil
    if let exitStatus, exitStatus != 0 {
      stateGame = finishedGame
      state = .failed("游戏兼容进程异常退出（退出码 \(exitStatus)），请查看启动日志。")
    } else {
      stateGame = nil
      state = .ready
    }
  }
}

struct MiHoYoLaunchPlan {
  let game: MiHoYoGame
  let wine: URL
  let prefix: URL
  let executable: URL
  let arguments: [String]
  let environment: [String: String]
  let diagnosticsDirectory: URL
  let dispatchScript: URL?
  let windowHelperArguments: [String]?
  let profileName: String

  func prepareIfNeeded() throws {
    if game == .starRail {
      guard profileName == "hkrpg-managed-native-window-r1" else { return }
      try prepareManagedStarRailPrefix()
      return
    }
    let custom = CustomGameLaunchPlan(
      wine: wine,
      wineboot: wine.deletingLastPathComponent().appending(path: "wineboot"),
      prefix: prefix,
      executable: executable,
      diagnosticsDirectory: diagnosticsDirectory
    )
    try CustomGamePrefixPreparer.prepare(custom)
    guard let assets = RuntimePreparationAssets.resolve() else {
      throw MiHoYoLaunchError.runtimeAssetsMissing
    }
    try RuntimeAssetInstaller.installSteamStubs(assets: assets, prefix: prefix)
  }

  private func prepareManagedStarRailPrefix() throws {
    let plan = CustomGameLaunchPlan(
      wine: wine,
      wineboot: wine.deletingLastPathComponent().appending(path: "wineboot"),
      prefix: prefix,
      executable: executable,
      diagnosticsDirectory: diagnosticsDirectory
    )
    try CustomGamePrefixPreparer.prepare(plan)
    guard let assets = StarRailRuntimeAssets.resolve() else {
      throw MiHoYoLaunchError.starRailProfileMissing
    }
    let jadeiteTarget = prefix.appending(path: "drive_c/mgb-jadeite", directoryHint: .isDirectory)
    if !FileManager.default.fileExists(atPath: jadeiteTarget.appending(path: "jadeite.exe").path) {
      try FileManager.default.createDirectory(
        at: jadeiteTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: assets.jadeiteDirectory, to: jadeiteTarget)
    }
    try runWine([
      "reg", "add", "HKLM\\SOFTWARE\\NVIDIA Corporation\\Global", "/v",
      "{41FCC608-8496-4DEF-B43E-7D9BD675A6FF}", "/t", "REG_BINARY", "/d", "1", "/f",
    ])
    try runWine([
      "reg", "add", "HKLM\\SYSTEM\\ControlSet001\\Services\\nvlddmkm", "/v",
      "{41FCC608-8496-4DEF-B43E-7D9BD675A6FF}", "/t", "REG_BINARY", "/d", "1", "/f",
    ])
    try runWine([
      "reg", "add", "HKLM\\SOFTWARE\\NVIDIA Corporation\\Global\\NGXCore", "/v",
      "FullPath", "/t", "REG_SZ", "/d", "C:\\Windows\\System32", "/f",
    ])
    try runWine([
      "reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode", "/t",
      "REG_SZ", "/d", "y", "/f",
    ])
  }

  private func runWine(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = wine
    process.arguments = arguments
    process.environment = environment.merging(["WINEDEBUG": "-all"]) { _, new in new }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw MiHoYoLaunchError.prefixPreparationFailed }
  }

  static func resolve(game: MiHoYoGame, executable: URL) throws -> Self {
    guard game != .genshin else { throw MiHoYoLaunchError.unsupportedProfile }
    if game == .starRail,
      let project = locateProjectRoot(),
      let plan = starRailDevelopmentPlan(project: project, executable: executable)
    {
      return plan
    }
    if game == .starRail, let plan = try starRailManagedPlan(executable: executable) {
      return plan
    }

    let generic = try CustomGameLaunchPlan.make(
      gameID: game.rawValue, executablePath: executable.path)
    let steam = "C:\\windows\\system32\\steam.exe"
    guard let window = NativeGameWindowSupport.resolve() else { throw MiHoYoLaunchError.runtimeAssetsMissing }
    var environment = generic.environment
    window.apply(to: &environment, game: game)
    return Self(
      game: game,
      wine: generic.wine,
      prefix: generic.prefix,
      executable: executable,
      arguments: [steam, generic.windowsExecutablePath, "-screen-fullscreen", "0"],
      environment: environment,
      diagnosticsDirectory: generic.diagnosticsDirectory,
      dispatchScript: nil,
      windowHelperArguments: window.arguments(for: game),
      profileName: "crossover11-dxmt-steam-r1"
    )
  }

  private static func starRailManagedPlan(executable: URL) throws -> Self? {
    guard let assets = StarRailRuntimeAssets.resolve() else { return nil }
    let runtime = try GameRuntimePaths.resolveRuntime()
    let prefix = GameRuntimePaths.userStorageRoot.appending(
      path: "Prefixes/starrail-cn-crossover11-dxmt-r1", directoryHint: .isDirectory)
    var environment: [String: String] = [:]
    let inherited = ProcessInfo.processInfo.environment
    for key in ["HOME", "LOGNAME", "PATH", "TMPDIR", "USER"] {
      environment[key] = inherited[key]
    }
    environment["WINEPREFIX"] = prefix.path
    environment["WINEMSYNC"] = "1"
    environment["DXMT_ENABLE_NVEXT"] = "1"
    environment["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;"
    environment["GST_PLUGIN_FEATURE_RANK"] = "atdec:MAX,avdec_h264:MAX"
    environment["WINEDEBUG"] = "-all"
    environment["LANG"] = "zh_CN.UTF-8"
    environment["LC_ALL"] = "zh_CN.UTF-8"
    environment["MGB_NATIVE_WINDOW"] = "1"
    environment["MGB_NATIVE_WINDOW_TITLE"] = "Honkai: Star Rail"
    environment["DYLD_INSERT_LIBRARIES"] = assets.windowAdapter.path
    return Self(
      game: .starRail,
      wine: runtime.wine,
      prefix: prefix,
      executable: executable,
      arguments: [
        "C:\\mgb-jadeite\\jadeite.exe", windowsPath(executable), "--",
        "-disable-gpu-skinning", "-screen-fullscreen", "0",
      ],
      environment: environment,
      diagnosticsDirectory: GameRuntimePaths.userStorageRoot.appending(
        path: "Diagnostics/StarRail", directoryHint: .isDirectory),
      dispatchScript: assets.dispatchScript,
      windowHelperArguments: [windowsPath(assets.windowFlags), "Honkai: Star Rail", "--watch"],
      profileName: "hkrpg-managed-native-window-r1"
    )
  }

  private static func starRailDevelopmentPlan(project: URL, executable: URL) -> Self? {
    let experiment = project.appending(
      path: "LocalRuntimes/Experiments/hkrpg-dxmt-nv-20260905",
      directoryHint: .isDirectory)
    let adapter = project.appending(
      path: "LocalRuntimes/Experiments/native-window-adapter",
      directoryHint: .isDirectory)
    let wine = experiment.appending(path: "wine/bin/wine")
    let prefix = adapter.appending(path: "starrail-prefix", directoryHint: .isDirectory)
    let jadeite = prefix.appending(path: "drive_c/mgb-jadeite/jadeite.exe")
    let dylib = adapter.appending(path: "libMGBWindowAdapter.dylib")
    let helper = prefix.appending(path: "drive_c/window-flags.exe")
    let dispatch = experiment.appending(path: "temporary-dispatch-block.rb")
    guard [wine, jadeite, dylib, helper, dispatch].allSatisfy({
      FileManager.default.fileExists(atPath: $0.path)
    }) else { return nil }

    var environment: [String: String] = [:]
    let inherited = ProcessInfo.processInfo.environment
    for key in ["HOME", "LOGNAME", "PATH", "TMPDIR", "USER"] {
      environment[key] = inherited[key]
    }
    environment["WINEPREFIX"] = prefix.path
    environment["WINEMSYNC"] = "1"
    environment["DXMT_ENABLE_NVEXT"] = "1"
    environment["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;"
    environment["GST_PLUGIN_FEATURE_RANK"] = "atdec:MAX,avdec_h264:MAX"
    environment["WINEDEBUG"] = "-all"
    environment["LANG"] = "zh_CN.UTF-8"
    environment["LC_ALL"] = "zh_CN.UTF-8"
    environment["MGB_NATIVE_WINDOW"] = "1"
    environment["MGB_NATIVE_WINDOW_TITLE"] = "Honkai: Star Rail"
    environment["DYLD_INSERT_LIBRARIES"] = dylib.path

    let windowsGame = windowsPath(executable)
    return Self(
      game: .starRail,
      wine: wine,
      prefix: prefix,
      executable: executable,
      arguments: [
        "C:\\mgb-jadeite\\jadeite.exe", windowsGame, "--", "-disable-gpu-skinning",
        "-screen-fullscreen", "0", "-screen-width", "3840", "-screen-height", "2160",
      ],
      environment: environment,
      diagnosticsDirectory: GameRuntimePaths.userStorageRoot.appending(
        path: "Diagnostics/StarRail", directoryHint: .isDirectory),
      dispatchScript: dispatch,
      windowHelperArguments: ["C:\\window-flags.exe", "Honkai: Star Rail", "--watch"],
      profileName: "hkrpg-dxmt-nv-jadeite-native-window-r1"
    )
  }

  private static func windowsPath(_ url: URL) -> String {
    "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
  }

  private static func locateProjectRoot() -> URL? {
    let candidates = [
      Bundle.main.bundleURL,
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
    ]
    for candidate in candidates {
      var cursor = candidate
      for _ in 0..<8 {
        if FileManager.default.fileExists(atPath: cursor.appending(path: "Package.swift").path) {
          return cursor
        }
        let parent = cursor.deletingLastPathComponent()
        guard parent.path != cursor.path else { break }
        cursor = parent
      }
    }
    return nil
  }
}

struct StarRailRuntimeAssets {
  let jadeiteDirectory: URL
  let windowAdapter: URL
  let windowFlags: URL
  let dispatchScript: URL

  static func resolve(resourceURL: URL? = Bundle.main.resourceURL) -> Self? {
    guard let resourceURL else { return nil }
    let root = resourceURL.appending(path: "RuntimeAssets", directoryHint: .isDirectory)
    let assets = Self(
      jadeiteDirectory: root.appending(path: "Jadeite", directoryHint: .isDirectory),
      windowAdapter: root.appending(path: "libMGBWindowAdapter.dylib"),
      windowFlags: root.appending(path: "window-flags.exe"),
      dispatchScript: root.appending(path: "temporary-starrail-dispatch.rb")
    )
    let required = [
      assets.jadeiteDirectory.appending(path: "jadeite.exe"), assets.windowAdapter,
      assets.windowFlags, assets.dispatchScript,
    ]
    return required.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } ? assets : nil
  }
}

enum StarRailDispatchWindow {
  static func activate(using script: URL?) async throws {
    guard let script else { throw MiHoYoLaunchError.starRailProfileMissing }
    let command = "/usr/bin/ruby \(shellQuote(script.path)) >/tmp/mgb-starrail-dispatch.log 2>&1 &"
    let appleScript = "do shell script \(appleScriptLiteral(command)) with administrator privileges"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", appleScript]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw MiHoYoLaunchError.administratorAuthorizationCancelled }

    for _ in 0..<30 {
      try Task.checkCancellation()
      if (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8))?
        .contains("mgb-hsr-dispatch-test-20260905") == true { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw MiHoYoLaunchError.dispatchWindowUnavailable
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func appleScriptLiteral(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

enum MiHoYoLaunchError: LocalizedError {
  case unsupportedProfile
  case starRailProfileMissing
  case administratorAuthorizationCancelled
  case dispatchWindowUnavailable
  case cannotCreateLog
  case runtimeAssetsMissing
  case prefixPreparationFailed

  var errorDescription: String? {
    switch self {
    case .unsupportedProfile: "该游戏的启动配置不可用。"
    case .starRailProfileMissing: "星铁兼容组件不完整，请重新安装启动器。"
    case .administratorAuthorizationCancelled: "未完成星铁启动所需的系统验证。"
    case .dispatchWindowUnavailable: "星铁启动窗口未能安全建立，未修改游戏文件。"
    case .cannotCreateLog: "无法创建启动日志，请检查本地磁盘权限。"
    case .runtimeAssetsMissing: "启动器缺少已验证的 CrossOver / DXMT / Steam 运行组件。"
    case .prefixPreparationFailed: "星铁独立兼容环境准备失败，原游戏文件未修改。"
    }
  }
}
