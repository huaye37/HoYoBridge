import AppKit
import Darwin
import Foundation

enum GameInstallationState: Equatable {
  case checking
  case installed(version: String?)
  case notInstalled
  case resumable
  case recoveryRequired
  case installing(GameInstallationProgress)
  case cancelling
  case unavailable(String)
  case failed(String)
}

enum GameUpdateState: Equatable {
  case idle
  case checking
  case current(version: String)
  case available(installed: String, target: String)
  case failed(String)
}

enum GameBackupState: Equatable {
  case none
  case creating
  case available(GameBackupSnapshot)
  case restoring
  case failed(String)
}

struct GameInstallationProgress: Equatable, Sendable {
  let fraction: Double
  let downloadedBytes: UInt64
  let totalBytes: UInt64
  let bytesPerSecond: UInt64
  let etaSeconds: Int?
}

enum GameInstallerOutputParser {
  static func progress(from line: String) -> GameInstallationProgress? {
    guard line.hasPrefix("PROGRESS ") else { return nil }
    let fields = keyValues(in: line)
    guard let percent = fields["percent"].flatMap(Double.init),
      let downloadedBytes = fields["downloaded"].flatMap(UInt64.init),
      let totalBytes = fields["total"].flatMap(UInt64.init),
      totalBytes > 0,
      downloadedBytes <= totalBytes,
      let bytesPerSecond = fields["bytes_per_second"].flatMap(UInt64.init),
      let rawETA = fields["eta_seconds"].flatMap(Int.init)
    else {
      return nil
    }
    return GameInstallationProgress(
      fraction: min(max(percent / 100, 0), 1),
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      bytesPerSecond: bytesPerSecond,
      etaSeconds: rawETA >= 0 ? rawETA : nil
    )
  }

  static func completedVersion(from line: String) -> String? {
    guard line.hasPrefix("COMPLETE ") else { return nil }
    return keyValues(in: line)["version"]
  }

  static func availableVersion(from line: String) -> String? {
    guard line.hasPrefix("AVAILABLE ") else { return nil }
    return keyValues(in: line)["version"]
  }

  private static func keyValues(in line: String) -> [String: String] {
    var result: [String: String] = [:]
    for component in line.split(separator: " ").dropFirst() {
      guard let separator = component.firstIndex(of: "=") else { continue }
      let key = String(component[..<separator])
      let value = String(component[component.index(after: separator)...])
      guard !key.isEmpty, !value.isEmpty, result[key] == nil else { continue }
      result[key] = value
    }
    return result
  }
}

@MainActor
final class GameInstallationService: ObservableObject {
  @Published private(set) var state: GameInstallationState = .checking
  @Published private(set) var updateState: GameUpdateState = .idle
  @Published private(set) var backupState: GameBackupState = .none
  @Published private(set) var targetURL: URL
  @Published private(set) var latestLogURL: URL?
  @Published private(set) var storageProgress: GameMigrationProgress?
  @Published private(set) var storageMessage: String?
  @Published private(set) var retainedGameURL: URL?

  var isStorageBusy: Bool { storageProgress != nil }
  var canChangeStorage: Bool {
    installationTask == nil && backupOperationTask == nil && !isStorageBusy
  }

  private var installationTask: Task<Void, Never>?
  private var updateCheckTask: Task<Void, Never>?
  private var backupOperationTask: Task<Void, Never>?
  private var backupWorker: Task<GameBackupSnapshot, Error>?
  private var process: Process?
  private var processStopTask: Task<Void, Never>?
  private var checkedInstallationIdentity: String?
  private var migrationWorker: Task<URL, Error>?
  private var operationLock: GameDownloadLock?
  private var updateCheckID: UUID?
  private let defaults: UserDefaults
  private let automaticallyChecksForUpdates: Bool
  private let installerToolchain: GameInstallerToolchain?
  private let logDirectory: URL?

  init(
    defaults: UserDefaults = .standard, automaticallyChecksForUpdates: Bool = true,
    installerToolchain: GameInstallerToolchain? = nil, logDirectory: URL? = nil
  ) {
    self.defaults = defaults
    self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    self.installerToolchain = installerToolchain
    self.logDirectory = logDirectory
    targetURL = GameInstallLocationPreference.load(defaults: defaults) ?? Self.defaultTargetURL
    refresh()
  }

  func refresh(selectedLocation: InstallVolumeSelection? = nil) {
    guard canChangeStorage else { return }
    targetURL = Self.targetURL(
      for: selectedLocation, savedRoot: GameInstallLocationPreference.load(defaults: defaults))
    if GameDownloadLock.isBusy(game: targetURL) {
      cancelUpdateCheck()
      state = .unavailable(GameDownloadLockError.busy.localizedDescription)
      return
    }
    backupState =
      GameAPFSBackupManager.loadBackup(for: targetURL)
      .map(GameBackupState.available) ?? .none
    let recordedState = GameInstallationRecord.state(at: targetURL)
    if case .installed(let version) = recordedState {
      GameInstallLocationPreference.save(targetURL, defaults: defaults)
      state = recordedState
      if let version, automaticallyChecksForUpdates {
        checkForUpdates(installedVersion: version)
      }
      return
    }
    cancelUpdateCheck()
    if targetURL.path.hasPrefix("/Volumes/"),
      (try? InstallVolumeProbe.inspect(
        targetURL.deletingLastPathComponent(), isDefaultPreview: false)) == nil
    {
      state = .failed("安装磁盘未连接或目录不可访问。请重新连接磁盘；原安装路径已保留，不会改装到内置磁盘。")
      return
    }
    if recordedState == .resumable || recordedState == .recoveryRequired {
      state = recordedState
      return
    }
    do {
      _ = try installerToolchain ?? Self.resolveToolchain()
      state = .notInstalled
    } catch {
      state = .unavailable("此构建尚未包含可独立分发的下载组件")
    }
  }

  func startOrResume(selectedLocation: InstallVolumeSelection?) {
    guard canChangeStorage else { return }
    cancelUpdateCheck()
    storageMessage = nil
    targetURL = Self.targetURL(
      for: selectedLocation, savedRoot: GameInstallLocationPreference.load(defaults: defaults))
    let previousState = GameInstallationRecord.state(at: targetURL)
    let hadInstalledGame = GameInstallationRecord.isInstalled(at: targetURL)
    if targetURL.path.hasPrefix("/Volumes/"),
      (try? InstallVolumeProbe.inspect(
        targetURL.deletingLastPathComponent(), isDefaultPreview: false)) == nil
    {
      state = .failed("安装磁盘不可访问，请先重新连接；没有创建或修改游戏文件。")
      return
    }
    if hadInstalledGame {
      do {
        let volume = try InstallVolumeProbe.inspect(targetURL, isDefaultPreview: false)
        guard volume.isWritable, volume.supportsCloning, !volume.isNetwork else {
          storageMessage = volume.storageAdvice
          return
        }
      } catch {
        storageMessage = "游戏目录不可访问，请检查磁盘连接。"
        return
      }
    }
    if previousState == .notInstalled {
      do {
        let container = selectedLocation?.url ?? targetURL.deletingLastPathComponent()
        switch try Self.liveInitialInstallReadiness(at: container) {
        case .ready:
          break
        case .insufficient(let missingBytes):
          state = .failed(
            "安装空间不足，还需要 \(StatusFormatting.bytes(missingBytes))；请选择其他位置")
          return
        case .unknown:
          state = .failed("无法确认安装位置的剩余空间")
          return
        }
      } catch {
        state = .failed("无法重新检查安装位置的剩余空间")
        return
      }
    }
    guard acquireOperationLock() else { return }
    GameInstallLocationPreference.save(targetURL, defaults: defaults)
    state = .installing(
      GameInstallationProgress(
        fraction: 0,
        downloadedBytes: 0,
        totalBytes: DownloadSpacePlan.genshinOfficialCNInitialInstall.resourceCacheBytes,
        bytesPerSecond: 0,
        etaSeconds: nil
      ))

    installationTask = Task { [weak self] in
      guard let self else { return }
      defer {
        processStopTask = nil
        operationLock = nil
        installationTask = nil
      }
      do {
        try Task.checkCancellation()
        if hadInstalledGame {
          backupState = .creating
          let gameURL = targetURL
          let worker = Task.detached(priority: .utility) {
            try GameAPFSBackupManager.createBackup(for: gameURL)
          }
          backupWorker = worker
          do {
            backupState = .available(try await worker.value)
            backupWorker = nil
          } catch is CancellationError {
            backupWorker = nil
            backupState =
              GameAPFSBackupManager.loadBackup(for: gameURL)
              .map(GameBackupState.available) ?? .none
            throw CancellationError()
          } catch {
            backupWorker = nil
            backupState = .failed("无法创建更新前安全备份")
            throw GameInstallationServiceError.backupFailed
          }
          try GameStorageManager.prepareManagedMarker(at: targetURL)
        } else {
          // Resuming must never replace the last good rollback point with partial files.
          backupState =
            GameAPFSBackupManager.loadBackup(for: targetURL)
            .map(GameBackupState.available) ?? .none
        }

        try Task.checkCancellation()
        let toolchain = try installerToolchain ?? Self.resolveToolchain()
        let logURL = try Self.makeLogURL(directory: logDirectory)
        latestLogURL = logURL
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        let pipe = Pipe()
        let child = Process()
        child.executableURL = toolchain.python
        child.arguments = [
          toolchain.script.path,
          "--target", targetURL.path,
          "--workers", "4",
          "--operation-lock-stdin",
        ]
        child.environment = Self.toolchainEnvironment(toolchain)
        child.standardOutput = pipe
        child.standardError = pipe
        child.standardInput = operationLock?.handle
        try Task.checkCancellation()
        // Persist before launching any writer, including a process that later crashes.
        if previousState == .notInstalled,
          FileManager.default.fileExists(atPath: targetURL.path),
          try !FileManager.default.contentsOfDirectory(atPath: targetURL.path).isEmpty
        {
          throw GameInstallationServiceError.installerFailed
        }
        try GameInstallationRecord.begin(at: targetURL)
        try child.run()
        process = child

        var completedVersion: String?
        for try await line in pipe.fileHandleForReading.bytes.lines {
          try Task.checkCancellation()
          if let bytes = "\(line)\n".data(using: .utf8) {
            try logHandle.write(contentsOf: bytes)
          }
          if let progress = GameInstallerOutputParser.progress(from: line) {
            state = .installing(progress)
          }
          if let version = GameInstallerOutputParser.completedVersion(from: line) {
            completedVersion = version
          }
        }
        await Self.waitForExit(child)
        process = nil
        try Task.checkCancellation()

        guard child.terminationStatus == 0, let completedVersion,
          completedVersion == GameInstallationRecord.completedVersion(at: targetURL)
        else {
          throw GameInstallationServiceError.installerFailed
        }
        state = .installed(version: completedVersion)
        updateState = .current(version: completedVersion)
        checkedInstallationIdentity = Self.installationIdentity(
          targetURL: targetURL, version: completedVersion)
      } catch is CancellationError {
        await stopInstaller()
        state = GameInstallationRecord.state(at: targetURL)
        storageMessage = "任务已停止，没有删除已有文件或安全备份。继续时会重新核对文件。"
      } catch {
        await stopInstaller()
        state = GameInstallationRecord.state(at: targetURL)
        if case .installed = state {
          storageMessage = "更新任务未完成；磁盘记录仍为完整版本。请查看安装日志后重试。"
        } else {
          storageMessage = "更新或校验未完成，暂不能启动。可以继续修复，或在“备份与回滚”恢复旧版本；详情见安装日志。"
        }
      }
    }
  }

  func checkForUpdates(force: Bool = true) {
    guard case .installed(let version) = state, let version else { return }
    if force {
      checkedInstallationIdentity = nil
    }
    checkForUpdates(installedVersion: version)
  }

  func cancel() {
    guard installationTask != nil || backupOperationTask != nil || backupWorker != nil else {
      return
    }
    if installationTask != nil {
      state = .cancelling
    }
    requestProcessStop()
    backupWorker?.cancel()
    backupOperationTask?.cancel()
    installationTask?.cancel()
  }

  private func acquireOperationLock() -> Bool {
    do {
      operationLock = try GameDownloadLock(game: targetURL)
      return true
    } catch {
      storageMessage = error.localizedDescription
      return false
    }
  }

  private func stopInstaller() async {
    requestProcessStop()
    await processStopTask?.value
    process = nil
    processStopTask = nil
  }

  private func requestProcessStop() {
    guard let child = process, processStopTask == nil else { return }
    if child.isRunning { child.interrupt() }
    // Start independently of stdout reads: a silent/stalled writer must also stop.
    processStopTask = Task { await Self.waitForExit(child, stopping: true) }
  }

  nonisolated static func waitForExit(_ child: Process, stopping: Bool = false) async {
    // A cancelled UI task must still reap its own writer before enabling rollback.
    await Task.detached(priority: .utility) {
      let deadline = Date().addingTimeInterval(10)
      var forced = false
      while child.isRunning {
        if stopping, !forced, Date() >= deadline {
          kill(child.processIdentifier, SIGKILL)
          forced = true
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
      child.waitUntilExit()
    }.value
  }

  func createSafetyBackup() {
    guard canChangeStorage,
      case .installed = state
    else { return }
    guard acquireOperationLock() else { return }
    let gameURL = targetURL
    backupState = .creating
    backupOperationTask = Task { [weak self] in
      guard let self else { return }
      let worker = Task.detached(priority: .utility) {
        try GameAPFSBackupManager.createBackup(for: gameURL)
      }
      backupWorker = worker
      do {
        backupState = .available(try await worker.value)
      } catch is CancellationError {
        backupState =
          GameAPFSBackupManager.loadBackup(for: gameURL)
          .map(GameBackupState.available) ?? .none
      } catch {
        backupState = .failed("无法创建 APFS 安全备份")
      }
      backupWorker = nil
      backupOperationTask = nil
      operationLock = nil
    }
  }

  func rollbackToBackup() {
    guard canChangeStorage,
      case .available(let snapshot) = backupState, snapshot.isRestorable
    else { return }
    guard acquireOperationLock() else { return }
    cancelUpdateCheck()
    let gameURL = targetURL
    backupState = .restoring
    backupOperationTask = Task { [weak self] in
      guard let self else { return }
      let worker = Task.detached(priority: .userInitiated) {
        try GameAPFSBackupManager.rollback(gameURL: gameURL)
      }
      backupWorker = worker
      do {
        let snapshot = try await worker.value
        state = GameInstallationRecord.state(at: gameURL)
        updateState = .idle
        checkedInstallationIdentity = nil
        backupState = .available(snapshot)
        storageMessage = "已恢复备份。替换下来的目录仍保留；未完成的更新不能作为可启动回滚点。旧版本能否登录仍取决于服务器要求。"
      } catch is CancellationError {
        state = GameInstallationRecord.state(at: gameURL)
        backupState =
          GameAPFSBackupManager.loadBackup(for: gameURL)
          .map(GameBackupState.available) ?? .none
      } catch {
        backupState = .failed("回滚没有完成，当前游戏目录未切换")
      }
      backupWorker = nil
      backupOperationTask = nil
      operationLock = nil
    }
  }

  func revealGameFolder() {
    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
  }

  func openLatestLog() {
    guard let latestLogURL else { return }
    NSWorkspace.shared.open(latestLogURL)
  }

  private static let defaultTargetURL = MiHoYoGame.genshin.defaultDirectory

  static func targetURL(
    for selection: InstallVolumeSelection?, savedRoot: URL? = GameInstallLocationPreference.load()
  ) -> URL {
    guard let selection else {
      return savedRoot ?? defaultTargetURL
    }
    guard !selection.isDefaultPreview else { return savedRoot ?? defaultTargetURL }
    if let saved = savedRoot,
      saved.deletingLastPathComponent().standardizedFileURL == selection.url.standardizedFileURL
    {
      return saved
    }
    return selection.url.appending(path: "Genshin Impact", directoryHint: .isDirectory)
  }

  func chooseNewLocation(_ container: URL) {
    guard canChangeStorage else { return }
    do {
      let volume = try InstallVolumeProbe.inspect(container, isDefaultPreview: false)
      guard volume.isWritable else { throw GameStorageError.readOnly }
      let target = container.appending(path: "Genshin Impact", directoryHint: .isDirectory)
      GameInstallLocationPreference.save(target, defaults: defaults)
      storageMessage = nil
      refresh()
    } catch {
      storageMessage = error.localizedDescription
    }
  }

  func locateExistingGame(_ url: URL) {
    guard canChangeStorage else { return }
    do {
      let game = try GameStorageManager.recognize(url)
      GameInstallLocationPreference.save(game, defaults: defaults)
      storageMessage = "已关联游戏目录，不会重新下载。目录识别不代表文件完整；可在支持备份的磁盘上执行校验修复。"
      refresh()
    } catch {
      storageMessage = "无法识别此目录。请选择包含 YuanShen.exe 和 YuanShen_Data 的国服游戏文件夹。"
    }
  }

  func migrateGame(to container: URL) {
    guard canChangeStorage, case .installed = state else { return }
    guard acquireOperationLock() else { return }
    let source = targetURL
    storageMessage = nil
    storageProgress = .init(completedBytes: 0, totalBytes: 0, phase: "准备迁移")
    cancelUpdateCheck()
    let worker = Task.detached(priority: .utility) { [self] in
      try await GameStorageManager.migrate(source: source, to: container) { progress in
        await self.setStorageProgress(progress)
      }
    }
    migrationWorker = worker
    Task {
      do {
        let destination = try await worker.value
        GameInstallLocationPreference.save(destination, defaults: defaults)
        retainedGameURL = source
        storageMessage =
          "复制与逐文件 SHA-256 校验完成，启动路径已切换。原游戏、旧下载缓存和旧备份仍保留；确认新位置可玩后，可在 Finder 中清理原副本以释放空间。"
      } catch is CancellationError {
        storageMessage = "迁移已取消，启动路径和原游戏未改变。"
      } catch {
        storageMessage = "迁移未完成，启动路径和原游戏未改变。\(error.localizedDescription)"
      }
      migrationWorker = nil
      storageProgress = nil
      operationLock = nil
      refresh()
    }
  }

  func cancelMigration() {
    migrationWorker?.cancel()
  }

  private func setStorageProgress(_ progress: GameMigrationProgress) {
    storageProgress = progress
  }

  private func cancelUpdateCheck() {
    updateCheckID = nil
    updateCheckTask?.cancel()
    updateCheckTask = nil
    checkedInstallationIdentity = nil
    updateState = .idle
  }

  private func checkForUpdates(installedVersion: String) {
    let identity = Self.installationIdentity(targetURL: targetURL, version: installedVersion)
    guard updateCheckTask == nil, checkedInstallationIdentity != identity else { return }
    checkedInstallationIdentity = identity
    let requestID = UUID()
    updateCheckID = requestID
    updateState = .checking
    let checkedTarget = targetURL
    updateCheckTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if updateCheckID == requestID { updateCheckTask = nil }
      }
      do {
        let toolchain = try Self.resolveToolchain()
        let availableVersion = try await Task.detached(priority: .utility) {
          try Self.fetchAvailableVersion(toolchain: toolchain, targetURL: checkedTarget)
        }.value
        try Task.checkCancellation()
        guard targetURL == checkedTarget, updateCheckID == requestID,
          case .installed = state
        else { return }
        if availableVersion == installedVersion {
          updateState = .current(version: installedVersion)
        } else {
          updateState = .available(installed: installedVersion, target: availableVersion)
        }
      } catch is CancellationError {
        if targetURL == checkedTarget, updateCheckID == requestID {
          updateState = .idle
        }
      } catch {
        if targetURL == checkedTarget, updateCheckID == requestID {
          updateState = .failed("暂时无法检查新版本，现有游戏不受影响")
        }
      }
    }
  }

  private nonisolated static func fetchAvailableVersion(
    toolchain: GameInstallerToolchain,
    targetURL: URL
  ) throws -> String {
    try Task.checkCancellation()
    let output = Pipe()
    let child = Process()
    child.executableURL = toolchain.python
    child.arguments = [
      toolchain.script.path,
      "--target", targetURL.path,
      "--check-version-only",
    ]
    child.environment = toolchainEnvironment(toolchain)
    child.standardOutput = output
    child.standardError = FileHandle.nullDevice
    try child.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    child.waitUntilExit()
    try Task.checkCancellation()
    guard child.terminationStatus == 0,
      let text = String(data: data, encoding: .utf8),
      let version = text.split(separator: "\n")
        .compactMap({ GameInstallerOutputParser.availableVersion(from: String($0)) })
        .last
    else {
      throw GameInstallationServiceError.updateCheckFailed
    }
    return version
  }

  private nonisolated static func toolchainEnvironment(
    _ toolchain: GameInstallerToolchain
  ) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["MGB_YAAGL_ROOT"] = toolchain.upstream.path
    environment["PYTHONUNBUFFERED"] = "1"
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    if let pythonPackages = toolchain.pythonPackages {
      environment["PYTHONPATH"] = pythonPackages.path
      environment["PYTHONNOUSERSITE"] = "1"
    }
    return environment
  }

  private static func installationIdentity(targetURL: URL, version: String) -> String {
    "\(targetURL.standardizedFileURL.path)|\(version)"
  }

  nonisolated static func liveInitialInstallReadiness(
    at containerURL: URL,
    plan: DownloadSpacePlan = .genshinOfficialCNInitialInstall
  ) throws -> DownloadSpaceReadiness {
    var existingDirectory = containerURL.standardizedFileURL
    while !FileManager.default.fileExists(atPath: existingDirectory.path) {
      let parent = existingDirectory.deletingLastPathComponent()
      guard parent.path != existingDirectory.path, parent.path != "/Volumes" else {
        throw InstallVolumeProbeError.unavailable
      }
      existingDirectory = parent
    }
    let selection = try InstallVolumeProbe.inspect(
      existingDirectory,
      isDefaultPreview: false
    )
    return plan.readiness(freeDiskBytes: selection.freeDiskBytes)
  }

  static func resolveToolchain(
    bundleResourceURL: URL? = Bundle.main.resourceURL,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    currentDirectoryURL: URL = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    )
  ) throws -> GameInstallerToolchain {
    if let bundleResourceURL {
      let root = bundleResourceURL.appending(
        path: "GameDownloader",
        directoryHint: .isDirectory
      )
      let python = root.appending(path: "python/bin/python3.11")
      let script = root.appending(path: "download_genshin_cn_full.py")
      let upstream = root.appending(path: "upstream", directoryHint: .isDirectory)
      let pythonPackages = root.appending(path: "python-packages", directoryHint: .isDirectory)
      let marker = upstream.appending(path: ".mgb-pinned-upstream")
      if FileManager.default.isExecutableFile(atPath: python.path),
        FileManager.default.fileExists(atPath: script.path),
        FileManager.default.fileExists(atPath: pythonPackages.path),
        (try? String(contentsOf: marker, encoding: .utf8))
          == "revision=ca78abc29c2fc236261d088c6907d28cab6e9476\n"
      {
        return GameInstallerToolchain(
          python: python,
          pythonPackages: pythonPackages,
          script: script,
          upstream: upstream,
          isBundled: true
        )
      }
    }

    var candidates: [URL] = []
    if let override = environment["MGB_PROJECT_ROOT"], !override.isEmpty {
      candidates.append(URL(fileURLWithPath: override, isDirectory: true))
    }
    candidates.append(currentDirectoryURL)

    for candidate in candidates {
      var cursor = candidate.hasDirectoryPath ? candidate : candidate.deletingLastPathComponent()
      for _ in 0..<8 {
        let script = cursor.appending(path: "script/download_genshin_cn_full.py")
        let upstream = cursor.appending(
          path: "LocalRuntimes/Tools/YAAGL-ca78abc",
          directoryHint: .isDirectory
        )
        let python = upstream.appending(path: ".venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: python.path),
          FileManager.default.fileExists(atPath: script.path),
          FileManager.default.fileExists(atPath: upstream.appending(path: ".git").path)
        {
          return GameInstallerToolchain(
            python: python,
            pythonPackages: nil,
            script: script,
            upstream: upstream,
            isBundled: false
          )
        }
        let parent = cursor.deletingLastPathComponent()
        guard parent.path != cursor.path else { break }
        cursor = parent
      }
    }
    throw GameInstallationServiceError.toolchainUnavailable
  }

  private static func makeLogURL(directory: URL? = nil) throws -> URL {
    let directory =
      directory
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Logs/MacGameBridge",
        directoryHint: .isDirectory
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let url = directory.appending(
      path: "installer-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).log"
    )
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
      throw GameInstallationServiceError.logUnavailable
    }
    return url
  }
}

struct GameInstallerToolchain: Sendable {
  let python: URL
  let pythonPackages: URL?
  let script: URL
  let upstream: URL
  let isBundled: Bool
}

enum GameInstallationServiceError: Error {
  case toolchainUnavailable
  case logUnavailable
  case installerFailed
  case updateCheckFailed
  case backupFailed
}
