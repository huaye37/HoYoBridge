import AppKit
import BridgeCore
import Foundation

enum GameLaunchState: Equatable {
  case checking
  case ready
  case preparing
  case running
  case stopping
  case unavailable(String)
  case failed(String)

  var isBusy: Bool {
    switch self {
    case .preparing, .stopping: true
    default: false
    }
  }
}

enum GameBenchmarkState: Equatable {
  case idle
  case preparing
  case waitingForScene
  case warmingUp(secondsRemaining: Int)
  case measuring(secondsRemaining: Int)
  case finishing
  case completed
  case failed(String)

  var isActive: Bool {
    switch self {
    case .preparing, .waitingForScene, .warmingUp, .measuring, .finishing: true
    case .idle, .completed, .failed: false
    }
  }

  var statusText: String? {
    switch self {
    case .idle: nil
    case .preparing: "正在准备基准运行环境"
    case .waitingForScene: "请先进入大世界固定场景，然后返回点击开始采样"
    case .warmingUp(let seconds): "场景稳定中，还剩 \(seconds) 秒"
    case .measuring(let seconds): "正在采集游戏内逐帧数据，还剩 \(seconds) 秒"
    case .finishing: "采样完成，正在关闭游戏并生成报告"
    case .completed: "游戏内基准已完成"
    case .failed(let message): message
    }
  }
}

@MainActor
final class GameLaunchService: ObservableObject {
  @Published private(set) var state: GameLaunchState = .checking
  @Published private(set) var paths: GameRuntimePaths?
  @Published private(set) var latestLogURL: URL?
  @Published private(set) var performance: GamePerformanceSnapshot?
  @Published private(set) var latestPerformanceReport: GamePerformanceReport?
  @Published private(set) var latestLaunchNotice: String?
  @Published private(set) var benchmarkState: GameBenchmarkState = .idle
  @Published private(set) var benchmarkReports: [GameGraphicsBackend: GamePerformanceReport] = [:]

  private var gameProcess: Process?
  private var windowHelperProcess: Process?
  private var activeRunPaths: GameRuntimePaths?
  private var logHandle: FileHandle?
  private var launchTask: Task<Void, Never>?
  private var monitorTask: Task<Void, Never>?
  private var benchmarkTask: Task<Void, Never>?
  private var reportRefreshTask: Task<Void, Never>?
  private var peakMemoryBytes: UInt64 = 0
  private var runStartedAt: Date?

  init() {
    refreshReadiness()
  }

  func refreshReadiness() {
    guard gameProcess?.isRunning != true else {
      state = .running
      return
    }
    do {
      let resolved = try GameRuntimePaths.resolve()
      paths = resolved
      state = .ready
      refreshReports(paths: resolved)
    } catch GameRuntimePathError.installationIncomplete {
      paths = nil
      state = .unavailable("游戏安装或更新尚未完成，请继续修复或恢复安全备份")
    } catch GameRuntimePathError.gameNotFound {
      paths = nil
      state = .unavailable("未找到国服游戏文件")
    } catch GameRuntimePathError.runtimeNotFound {
      paths = nil
      state = .unavailable("兼容运行时尚未准备完成")
    } catch {
      paths = nil
      state = .unavailable("无法定位 MacGameBridge 运行目录")
    }
  }

  func launchGenshin(preferences: GameLaunchPreferences) {
    benchmarkTask?.cancel()
    benchmarkTask = nil
    benchmarkState = .idle
    launch(preferences: preferences, benchmark: false)
  }

  func launchBenchmark(preferences: GameLaunchPreferences) {
    guard launchTask == nil, gameProcess?.isRunning != true else { return }
    benchmarkState = .preparing
    launch(preferences: preferences, benchmark: true)
  }

  func beginGameplayBenchmark() {
    guard benchmarkState == .waitingForScene,
      let process = gameProcess,
      process.isRunning
    else { return }
    startBenchmarkCapture(process: process)
  }

  private func launch(preferences: GameLaunchPreferences, benchmark: Bool) {
    let preferences = preferences.usingGraphicsBackend(.dxmt)
    guard launchTask == nil, gameProcess?.isRunning != true else { return }
    refreshReadiness()
    guard let paths else {
      refreshReadiness()
      if benchmark { benchmarkState = .failed("基准测试环境尚未准备完成") }
      return
    }

    latestLaunchNotice = nil
    state = .preparing
    launchTask = Task { [weak self] in
      guard let self else { return }
      do {
        let launchPaths = paths
        if preferences.fpsUnlockMode.targetFPS != nil {
          try GenshinFPSUnlock.prepareDXMTPrefix(paths: launchPaths)
        }
        try GenshinPrefixConfigurator().prepare(paths: launchPaths, preferences: preferences)
        try Task.checkCancellation()
        try await self.startGame(
          paths: launchPaths,
          preferences: preferences,
          backend: preferences.graphicsBackend,
          benchmark: benchmark
        )
      } catch is CancellationError {
        self.state = .ready
        if benchmark { self.benchmarkState = .failed("基准测试已取消") }
      } catch {
        self.state = .failed(LauncherFailureDescription.describe(error))
        if benchmark {
          self.benchmarkState = .failed("基准测试启动失败：\(String(describing: error))")
        }
      }
      self.launchTask = nil
    }
  }

  func stopGame() {
    launchTask?.cancel()
    launchTask = nil
    if benchmarkState.isActive {
      benchmarkState = .failed("基准测试已停止")
    }
    benchmarkTask?.cancel()
    benchmarkTask = nil
    gameProcess?.terminate()
    guard let stopPaths = activeRunPaths ?? paths else {
      state = .ready
      return
    }

    state = .stopping
    Task { [weak self] in
      do {
        try await Task.detached(priority: .userInitiated) {
          try GenshinPrefixConfigurator().stop(paths: stopPaths)
        }.value
        self?.finishRun()
      } catch {
        self?.state = .failed("停止游戏失败")
      }
    }
  }

  func openGameFolder() {
    guard let paths else { return }
    NSWorkspace.shared.activateFileViewerSelecting([paths.gameExecutable])
  }

  func openLatestLog() {
    guard let latestLogURL else { return }
    NSWorkspace.shared.open(latestLogURL)
  }

  private func startGame(
    paths: GameRuntimePaths,
    preferences: GameLaunchPreferences,
    backend: GameGraphicsBackend,
    benchmark: Bool
  ) async throws {
    guard let window = NativeGameWindowSupport.resolve() else {
      throw GenshinPrefixConfigurationError.commandFailed("原生窗口组件缺失，请重新下载完整应用包")
    }
    try FileManager.default.createDirectory(
      at: paths.diagnosticsDirectory,
      withIntermediateDirectories: true
    )
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let logURL = paths.diagnosticsDirectory.appending(
      path: "launcher-\(formatter.string(from: Date())).log"
    )
    guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
      throw GenshinPrefixConfigurationError.commandFailed("diagnostics-log")
    }
    let handle = try FileHandle(forWritingTo: logURL)
    let launchRecord =
      "MGB_CONFIG backend=\(backend.rawValue) graphics=\(preferences.graphicsProfile.rawValue) resolution="
      + "\(preferences.resolution.rawValue) window=\(preferences.windowMode.rawValue) "
      + "fps_unlock=\(preferences.fpsUnlockMode.rawValue) "
      + "wine_debug=\(preferences.detailedWineLoggingEnabled) "
      + "metal_hud=\(preferences.metalHUDEnabled)\n"
    try handle.write(contentsOf: Data(launchRecord.utf8))
    GenshinFPSUnlock.clearStatus(paths: paths)

    let process = Process()
    process.executableURL = paths.wine
    process.currentDirectoryURL = paths.gameExecutable.deletingLastPathComponent()
    process.arguments = launchArguments(paths: paths, preferences: preferences)
    process.environment = launchEnvironment(
      paths: paths,
      preferences: preferences,
      benchmark: benchmark
    )
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = handle
    process.standardError = handle
    try process.run()

    let helper = Process()
    helper.executableURL = paths.wine
    helper.arguments = window.arguments(for: .genshin)
    helper.environment = process.environment
    helper.standardInput = FileHandle.nullDevice
    helper.standardOutput = handle
    helper.standardError = handle
    do { try helper.run() } catch { process.terminate(); throw error }
    windowHelperProcess = helper

    gameProcess = process
    activeRunPaths = paths
    logHandle = handle
    latestLogURL = logURL
    peakMemoryBytes = 0
    performance = nil
    runStartedAt = Date()
    state = .running

    monitorTask?.cancel()
    monitorTask = Task { [weak self] in
      var lastFPSStatus: GenshinFPSUnlockStatus?
      while !Task.isCancelled {
        guard process.isRunning else { break }
        if preferences.fpsUnlockMode.targetFPS != nil,
          let fpsStatus = await Task.detached(
            priority: .utility,
            operation: { GenshinFPSUnlock.readStatus(paths: paths) }
          ).value,
          fpsStatus != lastFPSStatus
        {
          lastFPSStatus = fpsStatus
          self?.recordFPSUnlockStatus(fpsStatus)
        }
        if let sample = try? await Task.detached(
          priority: .utility,
          operation: { try GamePerformanceSampler.sample(paths: paths) }
        ).value {
          self?.record(sample)
        }
        try? await Task.sleep(for: .seconds(2))
      }
      guard !Task.isCancelled else { return }
      self?.finishRun(exitStatus: process.terminationStatus)
    }

    if benchmark {
      benchmarkState = .waitingForScene
    } else if preferences.hideAfterLaunch {
      NSApp.hide(nil)
    }
  }

  private func startBenchmarkCapture(process: Process) {
    let warmUpSeconds = 10
    let measurementSeconds = 60
    benchmarkTask?.cancel()
    benchmarkTask = Task { [weak self] in
      guard let self else { return }
      for remaining in stride(from: warmUpSeconds, through: 1, by: -1) {
        guard !Task.isCancelled, process.isRunning else {
          self.benchmarkState = .failed("游戏在预热完成前退出")
          return
        }
        self.benchmarkState = .warmingUp(secondsRemaining: remaining)
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return
        }
      }

      try? self.logHandle?.write(contentsOf: Data("MGB_BENCHMARK kind=gameplay\n".utf8))
      try? self.logHandle?.write(contentsOf: Data("MGB_FRAME_CAPTURE_START\n".utf8))
      for remaining in stride(from: measurementSeconds, through: 1, by: -1) {
        guard !Task.isCancelled, process.isRunning else {
          self.benchmarkState = .failed("游戏在采样完成前退出")
          return
        }
        self.benchmarkState = .measuring(secondsRemaining: remaining)
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return
        }
      }
      try? self.logHandle?.write(contentsOf: Data("MGB_FRAME_CAPTURE_END\n".utf8))
      self.benchmarkState = .finishing
      self.benchmarkTask = nil
      self.stopGameAfterBenchmark()
    }
  }

  private func stopGameAfterBenchmark() {
    guard let stopPaths = activeRunPaths ?? paths else {
      benchmarkState = .failed("基准测试完成，但无法定位运行环境")
      return
    }
    state = .stopping
    gameProcess?.terminate()
    Task { [weak self] in
      do {
        try await Task.detached(priority: .userInitiated) {
          try GenshinPrefixConfigurator().stop(paths: stopPaths)
        }.value
        self?.finishRun()
      } catch {
        self?.benchmarkState = .failed("采样完成，但自动关闭游戏失败")
        self?.state = .failed("停止游戏失败")
      }
    }
  }

  private func record(_ sample: GamePerformanceSample) {
    guard sample.processCount > 0 else { return }
    peakMemoryBytes = max(peakMemoryBytes, sample.memoryBytes)
    performance = GamePerformanceSnapshot(
      memoryBytes: sample.memoryBytes,
      peakMemoryBytes: peakMemoryBytes,
      cpuPercent: sample.cpuPercent,
      processCount: sample.processCount
    )
    let record = String(
      format:
        "MGB_PERF elapsed_seconds=%d rss_bytes=%llu peak_rss_bytes=%llu cpu_percent=%.1f processes=%d\n",
      Int(Date().timeIntervalSince(runStartedAt ?? Date())),
      sample.memoryBytes,
      peakMemoryBytes,
      sample.cpuPercent,
      sample.processCount
    )
    try? logHandle?.write(contentsOf: Data(record.utf8))
  }

  private func recordFPSUnlockStatus(_ status: GenshinFPSUnlockStatus) {
    switch status {
    case .scanning:
      try? logHandle?.write(contentsOf: Data("MGB_FPS_UNLOCK status=scanning\n".utf8))
    case .active(let fps):
      latestLaunchNotice = "\(fps) FPS 解锁已应用（实验）"
      try? logHandle?.write(contentsOf: Data("MGB_FPS_UNLOCK status=active fps=\(fps)\n".utf8))
    case .failed:
      latestLaunchNotice = "当前游戏版本未匹配解帧特征，已安全保持默认帧率。"
      try? logHandle?.write(contentsOf: Data("MGB_FPS_UNLOCK status=failed\n".utf8))
    }
  }

  private func launchArguments(
    paths: GameRuntimePaths,
    preferences: GameLaunchPreferences
  ) -> [String] {
    return [
      "C:\\windows\\system32\\steam.exe",
      paths.windowsGamePath,
      "-screen-fullscreen", "0",
      "-screen-width", String(preferences.resolution.width),
      "-screen-height", String(preferences.resolution.height),
    ]
  }

  private func launchEnvironment(
    paths: GameRuntimePaths,
    preferences: GameLaunchPreferences,
    benchmark: Bool
  ) -> [String: String] {
    let inherited = ProcessInfo.processInfo.environment
    var environment: [String: String] = [:]
    for key in ["HOME", "LOGNAME", "PATH", "TMPDIR", "USER"] {
      environment[key] = inherited[key]
    }
    environment["WINEPREFIX"] = paths.prefix.path
    environment["WINEESYNC"] = "1"
    environment["WINE_ENABLE_TIMEOUT_FIX"] = "0"
    environment["WINEDLLOVERRIDES"] =
      preferences.fpsUnlockMode.targetFPS == nil ? "" : "version=n;versi0n=b;"
    environment["DXMT_CONFIG"] =
      "d3d11.preferredMaxFrameRate=\(preferences.fpsUnlockMode.targetFPS ?? 60);"
    if let targetFPS = preferences.fpsUnlockMode.targetFPS {
      environment["MGB_FPS_LIMIT"] = String(targetFPS)
    }
    environment["GST_PLUGIN_FEATURE_RANK"] = "atdec:MAX,avdec_h264:MAX"
    environment["WINEDEBUG"] =
      preferences.detailedWineLoggingEnabled ? "fixme-all,err-unwind,+timestamp" : "-all"
    environment["LANG"] = "zh_CN.UTF-8"
    environment["LC_ALL"] = "zh_CN.UTF-8"
    NativeGameWindowSupport.resolve()?.apply(to: &environment, game: .genshin,
      fullscreen: preferences.windowMode == .fullScreen)
    if benchmark || preferences.metalHUDEnabled {
      environment["MTL_HUD_ENABLED"] = "1"
    }
    if benchmark {
      environment["MTL_HUD_LOG_ENABLED"] = "1"
      environment["MTL_HUD_OPACITY"] = "0.0"
    }
    return environment
  }

  private func finishRun(exitStatus: Int32? = nil) {
    let failedExit = exitStatus.map { $0 != 0 } == true && state != .stopping
    benchmarkTask?.cancel()
    benchmarkTask = nil
    monitorTask?.cancel()
    monitorTask = nil
    gameProcess = nil
    windowHelperProcess?.terminate()
    windowHelperProcess = nil
    try? logHandle?.close()
    logHandle = nil
    let benchmarkWasFinishing = benchmarkState == .finishing
    if !benchmarkWasFinishing, benchmarkState.isActive {
      benchmarkState = .failed("游戏在基准测试完成前退出")
    }
    if let reportPaths = activeRunPaths ?? paths {
      refreshReports(paths: reportPaths, benchmarkWasFinishing: benchmarkWasFinishing)
    }
    activeRunPaths = nil
    runStartedAt = nil
    if failedExit, let exitStatus {
      state = .failed("游戏兼容进程异常退出（退出码 \(exitStatus)），请查看启动日志。")
      NSApp.unhide(nil)
    } else {
      state = paths == nil ? .checking : .ready
    }
  }

  private func refreshReports(
    paths reportPaths: GameRuntimePaths,
    benchmarkWasFinishing: Bool = false
  ) {
    reportRefreshTask?.cancel()
    reportRefreshTask = Task { [weak self] in
      let reports = await Task.detached(priority: .utility) {
        (
          GamePerformanceReportLoader.latest(paths: reportPaths),
          GamePerformanceReportLoader.latestBenchmarks(paths: reportPaths)
        )
      }.value
      guard !Task.isCancelled, let self else { return }
      latestPerformanceReport = reports.0
      benchmarkReports = reports.1
      if benchmarkWasFinishing {
        benchmarkState =
          reports.0?.framePerformance == nil
          ? .failed("没有收到足够的逐帧数据") : .completed
      }
      reportRefreshTask = nil
    }
  }
}
