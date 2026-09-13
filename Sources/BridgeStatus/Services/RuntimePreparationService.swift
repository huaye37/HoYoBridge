import CryptoKit
import Foundation

enum RuntimePreparationState: Equatable {
  case checking
  case ready
  case available
  case preparing
  case unavailable(String)
  case failed(String)
}

struct RuntimePreparationAssets: Equatable, Sendable {
  let wineArchive: URL
  let dxmtArchive: URL
  let steam64: URL
  let steam32: URL
  let lsteamclient64: URL
  let lsteamclient32: URL
  var expectations = RuntimeAssetExpectations.pinned

  static let wineByteSize: UInt64 = 456_021_524
  static let wineSHA256 = "89fa7e90fb626523a90d5867a03c6be785d017176739c6320a3b86c7838c3a35"
  static let dxmtByteSize: UInt64 = 18_681_669
  static let dxmtSHA256 = "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"

  static func resolve(
    resourceURL: URL? = Bundle.main.resourceURL,
    bundleURL: URL = Bundle.main.bundleURL,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  ) -> Self? {
    if let resourceURL {
      let root = resourceURL.appending(path: "RuntimeAssets", directoryHint: .isDirectory)
      let bundled = Self(
        wineArchive: root.appending(path: "wine-crossover-11.0-1-osx64-signed.tar.xz"),
        dxmtArchive: root.appending(path: "dxmt-v0.80-builtin.tar.gz"),
        steam64: root.appending(path: "steam64.exe"),
        steam32: root.appending(path: "steam32.exe"),
        lsteamclient64: root.appending(path: "lsteamclient64.dll"),
        lsteamclient32: root.appending(path: "lsteamclient32.dll")
      )
      if bundled.allFilesExist { return bundled }
    }

    for candidate in [bundleURL, currentDirectory] {
      var cursor = candidate.hasDirectoryPath ? candidate : candidate.deletingLastPathComponent()
      for _ in 0..<8 {
        let upstream = cursor.appending(
          path: "LocalRuntimes/Tools/YAAGL-ca78abc/sidecar/protonextras",
          directoryHint: .isDirectory
        )
        let local = Self(
          wineArchive: cursor.appending(
            path: "LocalRuntimes/Downloads/wine-crossover-11.0-1-osx64-signed.tar.xz"),
          dxmtArchive: cursor.appending(
            path: "LocalRuntimes/RuntimeAssets/dxmt-v0.80-builtin.tar.gz"),
          steam64: upstream.appending(path: "steam64.exe"),
          steam32: upstream.appending(path: "steam32.exe"),
          lsteamclient64: upstream.appending(path: "lsteamclient64.dll"),
          lsteamclient32: upstream.appending(path: "lsteamclient32.dll")
        )
        if local.allFilesExist { return local }
        let parent = cursor.deletingLastPathComponent()
        guard parent.path != cursor.path else { break }
        cursor = parent
      }
    }
    return nil
  }

  private var allFilesExist: Bool {
    [wineArchive, dxmtArchive, steam64, steam32, lsteamclient64, lsteamclient32]
      .allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
  }
}

struct RuntimeAssetExpectation: Equatable, Sendable {
  let byteSize: UInt64
  let sha256: String
}

struct RuntimeAssetExpectations: Equatable, Sendable {
  let wine: RuntimeAssetExpectation
  let dxmt: RuntimeAssetExpectation
  let steam64: RuntimeAssetExpectation
  let steam32: RuntimeAssetExpectation
  let lsteamclient64: RuntimeAssetExpectation
  let lsteamclient32: RuntimeAssetExpectation

  static let pinned = Self(
    wine: RuntimeAssetExpectation(
      byteSize: RuntimePreparationAssets.wineByteSize,
      sha256: RuntimePreparationAssets.wineSHA256
    ),
    dxmt: RuntimeAssetExpectation(
      byteSize: RuntimePreparationAssets.dxmtByteSize,
      sha256: RuntimePreparationAssets.dxmtSHA256
    ),
    steam64: RuntimeAssetExpectation(
      byteSize: 111_304,
      sha256: "0424339444c54bf1f9fdbadf12e4e2c90ceef41d987fe573b93f5f2ebfd8a657"
    ),
    steam32: RuntimeAssetExpectation(
      byteSize: 97_904,
      sha256: "d3b17fda25217165f5f5198ac179bb0645d4fcc61381bfeb0ba3c73ea029a433"
    ),
    lsteamclient64: RuntimeAssetExpectation(
      byteSize: 5_560_872,
      sha256: "af50ed0d952ef98d99d4d3ff67b4836b545c9403894430fca31969f9f630637b"
    ),
    lsteamclient32: RuntimeAssetExpectation(
      byteSize: 4_412_824,
      sha256: "608eece6672369db539211fd04eb95b9fb5ddd077e76aa87c28c04c25c1e2fe2"
    )
  )
}

@MainActor
final class RuntimePreparationService: ObservableObject {
  @Published private(set) var state: RuntimePreparationState = .checking

  private var task: Task<Void, Never>?

  init() {
    refresh()
  }

  func refresh() {
    guard task == nil else { return }
    if (try? GameRuntimePaths.resolveRuntime()) != nil {
      state = .ready
    } else if RuntimePreparationAssets.resolve() != nil {
      state = .available
    } else {
      state = .unavailable("此构建没有包含 CrossOver、DXMT 与 Steam 兼容资产")
    }
  }

  func prepare() {
    guard task == nil, let assets = RuntimePreparationAssets.resolve() else {
      refresh()
      return
    }
    state = .preparing
    task = Task { [weak self] in
      guard let self else { return }
      do {
        try await Task.detached(priority: .userInitiated) {
          try RuntimeAssetInstaller.install(assets: assets)
        }.value
        state = .ready
      } catch is CancellationError {
        state = .available
      } catch {
        state = .failed(LauncherFailureDescription.describe(error))
      }
      task = nil
    }
  }
}

enum RuntimeAssetInstaller {
  static let markerName = ".mgb-managed-runtime"
  static let markerContents =
    "schema=1\nprofile=genshin-cn-crossover11-steam-v1\nwineSHA256=\(RuntimePreparationAssets.wineSHA256)\ndxmtSHA256=\(RuntimePreparationAssets.dxmtSHA256)\n"

  static func install(
    assets: RuntimePreparationAssets,
    storageRoot: URL = GameRuntimePaths.userStorageRoot
  ) throws {
    try verifyAssets(assets)
    try Task.checkCancellation()

    let manager = FileManager.default
    try manager.createDirectory(at: storageRoot, withIntermediateDirectories: true)
    let stagingRoot = storageRoot.appending(
      path: ".runtime-preparing-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let stagedRuntime = stagingRoot.appending(path: "runtime", directoryHint: .isDirectory)
    let stagedPrefix = stagingRoot.appending(path: "prefix", directoryHint: .isDirectory)
    defer { try? manager.removeItem(at: stagingRoot) }
    try manager.createDirectory(at: stagedRuntime, withIntermediateDirectories: true)

    try run("/usr/bin/tar", ["-xf", assets.wineArchive.path, "-C", stagedRuntime.path])
    let wineRoot = stagedRuntime.appending(path: "wine", directoryHint: .isDirectory)
    let wine = wineRoot.appending(path: "bin/wine")
    let wineboot = wineRoot.appending(path: "bin/wineboot")
    let wineserver = wineRoot.appending(path: "bin/wineserver")
    guard manager.isExecutableFile(atPath: wine.path),
      manager.isExecutableFile(atPath: wineboot.path),
      manager.isExecutableFile(atPath: wineserver.path)
    else {
      throw RuntimeAssetInstallerError.invalidArchive
    }

    let dxmtRoot = stagingRoot.appending(path: "dxmt", directoryHint: .isDirectory)
    try manager.createDirectory(at: dxmtRoot, withIntermediateDirectories: true)
    try run("/usr/bin/tar", ["-xf", assets.dxmtArchive.path, "-C", dxmtRoot.path])
    try installDXMT(from: dxmtRoot.appending(path: "v0.80"), into: wineRoot)
    try Task.checkCancellation()

    var environment = ProcessInfo.processInfo.environment
    environment["WINEPREFIX"] = stagedPrefix.path
    environment["WINEDEBUG"] = "-all"
    environment["LANG"] = "zh_CN.UTF-8"
    environment["LC_ALL"] = "zh_CN.UTF-8"
    try run(wineboot.path, ["-u"], environment: environment)
    try run(wineserver.path, ["-w"], environment: environment)
    try installSteamStubs(assets: assets, prefix: stagedPrefix)
    try writeMarker(at: stagedRuntime.appending(path: markerName))
    try writeMarker(at: stagedPrefix.appending(path: markerName))
    try Task.checkCancellation()

    let runtimeTarget = storageRoot.appending(
      path: "Runtimes/genshin-cn-crossover11-steam",
      directoryHint: .isDirectory
    )
    let prefixTarget = storageRoot.appending(
      path: "Prefixes/genshin-cn-crossover11-steam",
      directoryHint: .isDirectory
    )
    try requireManagedOrAbsent(runtimeTarget)
    try requireManagedOrAbsent(prefixTarget)
    try replaceManagedDirectory(at: runtimeTarget, with: stagedRuntime)
    try replaceManagedDirectory(at: prefixTarget, with: stagedPrefix)
  }

  private static func verifyAssets(_ assets: RuntimePreparationAssets) throws {
    try verify(assets.wineArchive, expectation: assets.expectations.wine)
    try verify(assets.dxmtArchive, expectation: assets.expectations.dxmt)
    try verify(assets.steam64, expectation: assets.expectations.steam64)
    try verify(assets.steam32, expectation: assets.expectations.steam32)
    try verify(assets.lsteamclient64, expectation: assets.expectations.lsteamclient64)
    try verify(assets.lsteamclient32, expectation: assets.expectations.lsteamclient32)
  }

  private static func verify(_ url: URL, expectation: RuntimeAssetExpectation) throws {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
      values.fileSize.map(UInt64.init) == expectation.byteSize
    else {
      throw RuntimeAssetInstallerError.assetMismatch
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      try Task.checkCancellation()
      digest.update(data: data)
    }
    guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == expectation.sha256
    else {
      throw RuntimeAssetInstallerError.assetMismatch
    }
  }

  private static func installDXMT(from sourceRoot: URL, into wineRoot: URL) throws {
    let mappings = [
      ("x86_64-unix/winemetal.so", "lib/wine/x86_64-unix/winemetal.so"),
      ("x86_64-windows/d3d10core.dll", "lib/wine/x86_64-windows/d3d10core.dll"),
      ("x86_64-windows/d3d11.dll", "lib/wine/x86_64-windows/d3d11.dll"),
      ("x86_64-windows/dxgi.dll", "lib/wine/x86_64-windows/dxgi.dll"),
      ("x86_64-windows/winemetal.dll", "lib/wine/x86_64-windows/winemetal.dll"),
      ("x86_64-windows/nvngx.dll", "lib/wine/x86_64-windows/nvngx.dll"),
      ("i386-windows/d3d10core.dll", "lib/wine/i386-windows/d3d10core.dll"),
      ("i386-windows/d3d11.dll", "lib/wine/i386-windows/d3d11.dll"),
      ("i386-windows/dxgi.dll", "lib/wine/i386-windows/dxgi.dll"),
      ("i386-windows/winemetal.dll", "lib/wine/i386-windows/winemetal.dll"),
    ]
    for (source, destination) in mappings {
      try replaceFile(
        from: sourceRoot.appending(path: source),
        to: wineRoot.appending(path: destination)
      )
    }
  }

  static func installSteamStubs(
    assets: RuntimePreparationAssets,
    prefix: URL
  ) throws {
    try replaceFile(
      from: assets.steam64,
      to: prefix.appending(path: "drive_c/windows/system32/steam.exe")
    )
    try replaceFile(
      from: assets.lsteamclient64,
      to: prefix.appending(path: "drive_c/windows/system32/lsteamclient.dll")
    )
    try replaceFile(
      from: assets.steam32,
      to: prefix.appending(path: "drive_c/windows/syswow64/steam.exe")
    )
    try replaceFile(
      from: assets.lsteamclient32,
      to: prefix.appending(path: "drive_c/windows/syswow64/lsteamclient.dll")
    )
  }

  private static func replaceFile(from source: URL, to destination: URL) throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath: source.path) else {
      throw RuntimeAssetInstallerError.invalidArchive
    }
    try manager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if manager.fileExists(atPath: destination.path) {
      try manager.removeItem(at: destination)
    }
    try manager.copyItem(at: source, to: destination)
  }

  private static func replaceManagedDirectory(at destination: URL, with source: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if manager.fileExists(atPath: destination.path) {
      try manager.removeItem(at: destination)
    }
    try manager.moveItem(at: source, to: destination)
  }

  private static func requireManagedOrAbsent(_ destination: URL) throws {
    guard FileManager.default.fileExists(atPath: destination.path) else { return }
    let marker = destination.appending(path: markerName)
    guard
      (try? String(contentsOf: marker, encoding: .utf8)) == markerContents
    else {
      throw RuntimeAssetInstallerError.unmanagedDestination
    }
  }

  private static func writeMarker(at url: URL) throws {
    try markerContents.write(to: url, atomically: true, encoding: .utf8)
  }

  private static func run(
    _ executable: String,
    _ arguments: [String],
    environment: [String: String]? = nil
  ) throws {
    try Task.checkCancellation()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw RuntimeAssetInstallerError.commandFailed(
        URL(fileURLWithPath: executable).lastPathComponent, process.terminationStatus)
    }
    try Task.checkCancellation()
  }
}

enum RuntimeAssetInstallerError: Error, LocalizedError {
  case assetMismatch
  case invalidArchive
  case unmanagedDestination
  case commandFailed(String, Int32)

  var errorDescription: String? {
    switch self {
    case .assetMismatch: "运行组件的大小或 SHA-256 校验失败，请重新下载完整启动器。"
    case .invalidArchive: "Wine 安装包缺少必需的可执行文件，请重新下载完整启动器。"
    case .unmanagedDestination: "目标目录不是启动器管理的运行环境，未覆盖原文件。"
    case .commandFailed(let command, let status):
      "运行环境准备在 \(command) 步骤失败（退出码 \(status)）；请检查磁盘空间和 Rosetta 是否可用。"
    }
  }
}
