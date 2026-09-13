import AppKit
import Foundation

@MainActor
final class CustomGameLaunchService: ObservableObject {
  @Published private(set) var state: GameLaunchState = .ready
  @Published private(set) var activeGameID: String?
  @Published private(set) var latestLogURL: URL?

  private var process: Process?
  private var activePlan: CustomGameLaunchPlan?
  private var logHandle: FileHandle?
  private var task: Task<Void, Never>?

  func launch(_ game: GameLibraryItem) {
    guard task == nil, process?.isRunning != true else { return }
    guard let executablePath = game.executablePath else {
      state = .failed("没有可用的 Windows 可执行文件")
      return
    }
    state = .preparing
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let plan = try CustomGameLaunchPlan.make(gameID: game.id, executablePath: executablePath)
        try await Task.detached(priority: .userInitiated) {
          try CustomGamePrefixPreparer.prepare(plan)
        }.value
        try Task.checkCancellation()
        try start(plan: plan, gameID: game.id)
      } catch is CancellationError {
        state = .ready
      } catch {
        state = .failed("通用兼容环境启动失败，可以查看诊断日志")
      }
      task = nil
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    guard let activePlan else {
      state = .ready
      return
    }
    state = .stopping
    Task { [weak self] in
      do {
        try await Task.detached(priority: .userInitiated) {
          try CustomGamePrefixPreparer.stop(activePlan)
        }.value
        self?.finish()
      } catch {
        self?.state = .failed("停止通用游戏环境失败")
      }
    }
  }

  func openLatestLog() {
    guard let latestLogURL else { return }
    NSWorkspace.shared.open(latestLogURL)
  }

  private func start(plan: CustomGameLaunchPlan, gameID: String) throws {
    try FileManager.default.createDirectory(
      at: plan.diagnosticsDirectory,
      withIntermediateDirectories: true
    )
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let logURL = plan.diagnosticsDirectory.appending(
      path: "custom-\(formatter.string(from: Date())).log"
    )
    guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
      throw CustomGameLaunchError.commandFailed
    }
    let handle = try FileHandle(forWritingTo: logURL)
    try handle.write(
      contentsOf: Data("MGB_CUSTOM_PROFILE generic-crossover11-dxmt-r1\n".utf8)
    )

    let launched = Process()
    launched.executableURL = plan.wine
    launched.arguments = [plan.windowsExecutablePath]
    launched.environment = plan.environment
    launched.standardOutput = handle
    launched.standardError = handle
    try launched.run()

    process = launched
    activePlan = plan
    logHandle = handle
    latestLogURL = logURL
    activeGameID = gameID
    state = .running

    Task { [weak self, weak launched] in
      guard let launched else { return }
      while launched.isRunning {
        try? await Task.sleep(for: .seconds(1))
      }
      self?.finish()
    }
  }

  private func finish() {
    process = nil
    activePlan = nil
    try? logHandle?.close()
    logHandle = nil
    activeGameID = nil
    state = .ready
  }
}

struct CustomGameLaunchPlan: Equatable, Sendable {
  let wine: URL
  let wineboot: URL
  let prefix: URL
  let executable: URL
  let diagnosticsDirectory: URL

  var windowsExecutablePath: String {
    "Z:" + executable.path.replacingOccurrences(of: "/", with: "\\")
  }

  var environment: [String: String] {
    var result = ProcessInfo.processInfo.environment
    result["WINEPREFIX"] = prefix.path
    result["WINEESYNC"] = "1"
    result["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;"
    result["WINEDEBUG"] = "fixme-all,err-unwind,+timestamp"
    result["LANG"] = "zh_CN.UTF-8"
    result["LC_ALL"] = "zh_CN.UTF-8"
    return result
  }

  static func make(
    gameID: String,
    executablePath: String,
    storageRoot: URL = GameRuntimePaths.userStorageRoot,
    runtimePaths: GameRuntimePaths? = nil
  ) throws -> Self {
    let executable = URL(fileURLWithPath: executablePath).standardizedFileURL
    let values = try executable.resourceValues(forKeys: [.isRegularFileKey])
    guard executable.pathExtension.lowercased() == "exe", values.isRegularFile == true else {
      throw CustomGameLaunchError.invalidExecutable
    }
    let runtime = try runtimePaths ?? GameRuntimePaths.resolveRuntime(userStorageRoot: storageRoot)
    let safeID = gameID.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(64)
    guard !safeID.isEmpty else { throw CustomGameLaunchError.invalidGameID }
    return Self(
      wine: runtime.wine,
      wineboot: runtime.runtimeRoot.appending(path: "wine/bin/wineboot"),
      prefix: storageRoot.appending(
        path: "Prefixes/custom-\(safeID)-generic-dxmt-r1",
        directoryHint: .isDirectory
      ),
      executable: executable,
      diagnosticsDirectory: storageRoot.appending(
        path: "Diagnostics/CustomGames/\(safeID)", directoryHint: .isDirectory)
    )
  }
}

enum CustomGameLaunchError: Error {
  case invalidExecutable
  case invalidGameID
  case commandFailed
}

enum CustomGamePrefixPreparer {
  static func prepare(_ plan: CustomGameLaunchPlan) throws {
    try Task.checkCancellation()
    if FileManager.default.fileExists(atPath: plan.prefix.path) { return }
    try FileManager.default.createDirectory(
      at: plan.prefix.deletingLastPathComponent(), withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = plan.wineboot
    process.arguments = ["-u"]
    process.environment = plan.environment.merging(["WINEDEBUG": "-all"]) { _, new in new }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CustomGameLaunchError.commandFailed }
    try Task.checkCancellation()
  }

  static func stop(_ plan: CustomGameLaunchPlan) throws {
    let wineserver = plan.wine.deletingLastPathComponent().appending(path: "wineserver")
    let process = Process()
    process.executableURL = wineserver
    process.arguments = ["-k"]
    process.environment = plan.environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CustomGameLaunchError.commandFailed }
  }
}
