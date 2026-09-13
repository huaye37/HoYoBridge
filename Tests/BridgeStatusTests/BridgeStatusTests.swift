import CryptoKit
import Foundation
import Testing

@testable import BridgeStatus

@Suite("Bridge status demo")
struct BridgeStatusTests {
  @Test("observed snapshot keeps the reviewed aggregate values")
  func observedSnapshot() {
    let snapshot = ObservedManifestSnapshot.genshinOfficialCN

    #expect(snapshot.fileCount == 2_673)
    #expect(snapshot.chunkReferenceCount == 107_480)
    #expect(snapshot.uniqueChunkObjectCount == 107_325)
    #expect(snapshot.uniqueChunkObjectBytes == 121_185_381_917)
    #expect(snapshot.targetInstalledBytes == 124_827_264_431)
    #expect(snapshot.compressedManifestBytes == 8_521_303)
    #expect(snapshot.decompressedManifestBytes == 15_913_977)
  }

  @Test("download plan uses checked conservative peak space")
  func downloadPlanSpace() {
    let plan = DownloadSpacePlan.genshinOfficialCNInitialInstall

    #expect(plan.requiredPeakBytes == 266_012_646_348)
    #expect(
      plan.readiness(freeDiskBytes: 300_000_000_000)
        == .ready(remainingBytes: 33_987_353_652))
    #expect(
      plan.readiness(freeDiskBytes: 200_000_000_000)
        == .insufficient(missingBytes: 66_012_646_348))
    #expect(plan.readiness(freeDiskBytes: nil) == .unknown)
  }

  @Test("download plan fails closed on aggregate overflow")
  func downloadPlanOverflow() {
    let plan = DownloadSpacePlan(
      resourceCacheBytes: .max,
      installedGameBytes: 1,
      safetyReserveBytes: 0
    )

    #expect(plan.requiredPeakBytes == nil)
    #expect(plan.readiness(freeDiskBytes: .max) == .unknown)
  }

  @Test("install volume selection remains a read-only preview")
  func installVolumeSelection() throws {
    let selection = try InstallVolumeProbe.inspect(
      FileManager.default.homeDirectoryForCurrentUser,
      isDefaultPreview: true
    )

    #expect(selection.isDefaultPreview)
    #expect(selection.freeDiskBytes > 0)
    #expect(!selection.directoryName.isEmpty)
    #expect(
      DownloadSpacePlan.genshinOfficialCNInitialInstall.readiness(
        freeDiskBytes: selection.freeDiskBytes
      ) != .unknown)
  }

  @Test("APFS safety backup remains independent and rollback swaps both versions")
  func apfsBackupAndRollback() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "MacGameBridge-BackupTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let game = root.appending(path: "Genshin Impact", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try Data("launcher".utf8).write(to: game.appending(path: "YuanShen.exe"))
    let payload = game.appending(path: "GenshinImpact_Data.bin")
    try Data("old-version".utf8).write(to: payload)
    try Data("game_version=1.0.0\n".utf8).write(to: game.appending(path: "config.ini"))

    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let backup = try GameAPFSBackupManager.createBackup(for: game, now: createdAt)
    #expect(backup.version == "1.0.0")
    #expect(backup.createdAt == createdAt)
    #expect(
      try Data(contentsOf: backup.gameURL.appending(path: payload.lastPathComponent))
        == Data("old-version".utf8))

    try Data("new-version".utf8).write(to: payload)
    try Data("game_version=2.0.0\n".utf8).write(to: game.appending(path: "config.ini"))
    #expect(
      try Data(contentsOf: backup.gameURL.appending(path: payload.lastPathComponent))
        == Data("old-version".utf8))

    let newerBackup = try GameAPFSBackupManager.rollback(gameURL: game)
    #expect(try Data(contentsOf: payload) == Data("old-version".utf8))
    #expect(
      try String(contentsOf: game.appending(path: "config.ini"), encoding: .utf8).contains("1.0.0"))
    #expect(newerBackup.version == "2.0.0")
    #expect(
      try Data(contentsOf: newerBackup.gameURL.appending(path: payload.lastPathComponent))
        == Data("new-version".utf8))

    _ = try GameAPFSBackupManager.rollback(gameURL: game)
    #expect(try Data(contentsOf: payload) == Data("new-version".utf8))

    let replacedBackup = try GameAPFSBackupManager.createBackup(for: game)
    #expect(replacedBackup.version == "2.0.0")
    #expect(
      try Data(contentsOf: replacedBackup.gameURL.appending(path: payload.lastPathComponent))
        == Data("new-version".utf8))
  }

  @Test("install volume probe rejects non-file locations")
  func rejectsRemoteInstallLocation() {
    #expect(throws: InstallVolumeProbeError.invalidLocation) {
      try InstallVolumeProbe.inspect(
        #require(URL(string: "https://example.com/install")),
        isDefaultPreview: false
      )
    }
  }

  @Test("demo states record the verified launch and remaining acceptance")
  func honestDeliveryStates() {
    let states = Dictionary(
      uniqueKeysWithValues: StatusDemoData.milestones.map { ($0.id, $0.state) })

    #expect(states["manifest"] == .verified)
    #expect(states["runtime"] == .verified)
    #expect(states["download"] == .verified)
    #expect(states["launch"] == .verified)
    #expect(states["acceptance"] == .notStarted)
  }

  @Test("runtime snapshot records the safe launch boundary")
  func runtimeExperimentSnapshot() {
    let runtime = RuntimeExperimentSnapshot.genshinOfficialCN

    #expect(runtime.wineVersion == "11.0-1 CrossOver")
    #expect(runtime.dxmtVersion == "0.80")
    #expect(runtime.windowsVersion == "10.0.19045")
    #expect(runtime.launchAttemptCount == 1)
    #expect(runtime.blockerCode == "游戏窗口已成功打开")
    #expect(!runtime.gameFilesModified)
    #expect(!runtime.systemSettingsModified)
  }

  @Test("downloaded game snapshot records the independently checked result")
  func downloadedGameSnapshot() {
    let download = DownloadedGameSnapshot.genshinOfficialCN

    #expect(download.version == "7.0.0")
    #expect(download.manifestFileCount == 2_673)
    #expect(download.installedBytes == 124_827_264_431)
    #expect(download.executableVerified)
    #expect(download.dataDirectoryVerified)
  }

  @Test("verified chunk probe snapshot records only safe aggregate evidence")
  func verifiedChunkProbeSnapshot() {
    let probe = VerifiedChunkProbeSnapshot.genshinOfficialCN

    #expect(probe.compressedBytes == 21)
    #expect(
      probe.sha256
        == "8a1c5ac944823490b4879b551f5862fe3718e96738f7f4e29490c280391b5391")
    #expect(probe.requestCount == 4)
    #expect(probe.compressedMD5Verified)
    #expect(probe.uncompressedMD5Verified)
    #expect(!probe.cacheRelativePath.contains("chunk_id"))
  }

  @Test("recommended launch preferences are windowed and Chinese")
  func recommendedLaunchPreferences() {
    let preferences = GameLaunchPreferences.recommended

    #expect(preferences.graphicsBackend == .dxmt)
    #expect(preferences.windowMode == .windowed)
    #expect(preferences.resolution == .balanced)
    #expect(preferences.resolution.width == 1600)
    #expect(preferences.resolution.height == 900)
    #expect(preferences.graphicsProfile == .balanced)
    #expect(preferences.textLanguage == .simplifiedChinese)
    #expect(preferences.textLanguage.gameValue == 2)
    #expect(preferences.voiceLanguage == .simplifiedChinese)
    #expect(preferences.voiceLanguage.gameValue == 0)
    #expect(preferences.fpsUnlockMode == .disabled)
    #expect(GameFPSUnlockMode.fps120.targetFPS == 120)
    #expect(GameFPSUnlockMode.allCases.compactMap(\.targetFPS).max() == 120)
    #expect(!preferences.detailedWineLoggingEnabled)
    #expect(!preferences.metalHUDEnabled)
    #expect(preferences.automaticDXMTFallbackEnabled)
  }

  @Test("resolution accepts display-specific sizes and orders current modes first")
  func displayResolutionCatalog() throws {
    let displaySpecific = try #require(GameResolution(rawValue: "3024x1964"))
    #expect(displaySpecific.width == 3024)
    #expect(displaySpecific.height == 1964)
    #expect(displaySpecific.title == "3024 × 1964")
    #expect(GameResolution(rawValue: "bad-value") == nil)

    let current = GameResolution(width: 2560, height: 1440)
    let native = GameResolution(width: 5120, height: 2880)
    let options = GameResolutionCatalog.options(
      resolutions: [.compact, current, native],
      currentDesktop: [current],
      nativePixels: [native]
    )
    #expect(options.map(\.resolution) == [current, native, .compact])
    #expect(options[0].title.contains("当前桌面"))
    #expect(options[1].title.contains("原生像素"))
    #expect(options[2].title.contains("常用"))
    #expect(options[2].title.contains("16:9"))
  }

  @Test("general data editor preserves fields while changing text and voice")
  func generalDataEditor() throws {
    let source: [String: Any] = [
      "deviceLanguageType": 1,
      "deviceVoiceLanguageType": 1,
      "preserved": "value",
    ]
    var data = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
    data.append(0)
    let registryBytes = data.map { String(format: "%02x", $0) }.joined(separator: ",")
    let registry = "\"GENERAL_DATA_h2389025596\"=hex:\(registryBytes)\n\"next\"=dword:00000001"

    let updatedHex = try #require(
      try GenshinGeneralDataEditor.updatedBinaryHex(
        userRegistryText: registry,
        textLanguage: .simplifiedChinese,
        voiceLanguage: .simplifiedChinese,
        graphicsProfile: .preserve
      ))
    var updatedData = Data(
      stride(from: 0, to: updatedHex.count, by: 2).compactMap { offset -> UInt8? in
        let start = updatedHex.index(updatedHex.startIndex, offsetBy: offset)
        let end = updatedHex.index(start, offsetBy: 2)
        return UInt8(updatedHex[start..<end], radix: 16)
      })
    #expect(updatedData.removeLast() == 0)
    let updated = try #require(
      JSONSerialization.jsonObject(with: updatedData) as? [String: Any])

    #expect(updated["deviceLanguageType"] as? Int == 2)
    #expect(updated["deviceVoiceLanguageType"] as? Int == 0)
    #expect(updated["preserved"] as? String == "value")
  }

  @Test("balanced graphics replaces the expensive custom render profile")
  func balancedGraphicsProfile() throws {
    let existingGraphics: [String: Any] = [
      "currentVolatielGrade": -1,
      "customVolatileGrades": [["key": 2, "value": 8]],
      "volatileVersion": "CNRELWin7.0.0",
    ]
    let source: [String: Any] = [
      "deviceLanguageType": 1,
      "deviceVoiceLanguageType": 1,
      "motionBlur": true,
      "graphicsData": String(
        decoding: try JSONSerialization.data(
          withJSONObject: existingGraphics, options: [.sortedKeys]),
        as: UTF8.self
      ),
      "globalPerfData": "stale",
    ]
    var data = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
    data.append(0)
    let registryBytes = data.map { String(format: "%02x", $0) }.joined(separator: ",")
    let registry =
      "\"GENERAL_DATA_h2389025596\"=hex:\(registryBytes)\n\"next\"=dword:00000001"

    let updatedHex = try #require(
      try GenshinGeneralDataEditor.updatedBinaryHex(
        userRegistryText: registry,
        textLanguage: .simplifiedChinese,
        voiceLanguage: .simplifiedChinese,
        graphicsProfile: .balanced
      ))
    var updatedData = Data(
      stride(from: 0, to: updatedHex.count, by: 2).compactMap { offset -> UInt8? in
        let start = updatedHex.index(updatedHex.startIndex, offsetBy: offset)
        let end = updatedHex.index(start, offsetBy: 2)
        return UInt8(updatedHex[start..<end], radix: 16)
      })
    #expect(updatedData.removeLast() == 0)
    let updated = try #require(
      JSONSerialization.jsonObject(with: updatedData) as? [String: Any])
    let graphicsText = try #require(updated["graphicsData"] as? String)
    let graphics = try #require(
      JSONSerialization.jsonObject(with: Data(graphicsText.utf8)) as? [String: Any])
    let grades = try #require(graphics["customVolatileGrades"] as? [[String: Int]])
    let values = Dictionary(uniqueKeysWithValues: grades.map { ($0["key"] ?? 0, $0["value"] ?? 0) })

    #expect(values[1] == 2)
    #expect(values[2] == 3)
    #expect(values[3] == 2)
    #expect(values[6] == 3)
    #expect(values[7] == 1)
    #expect(values[9] == 1)
    #expect(values[10] == 1)
    #expect(updated["motionBlur"] as? Bool == false)
    #expect((updated["globalPerfData"] as? String)?.contains("stale") == false)
  }

  @Test("launch preferences update user registry without invoking Wine")
  func launchPreferencesUpdateUserRegistry() throws {
    let general: [String: Any] = [
      "deviceLanguageType": 1,
      "deviceVoiceLanguageType": 1,
      "preserved": "value",
    ]
    var generalData = try JSONSerialization.data(withJSONObject: general, options: [.sortedKeys])
    generalData.append(0)
    let generalHex = generalData.map { String(format: "%02x", $0) }.joined(separator: ",")
    let registry =
      """
      WINE REGISTRY Version 2

      [Control Panel\\\\International] 1
      "LocaleName"="en-US"
      "iCountry"="1"

      [Software\\\\miHoYo\\\\\\x539f\\x795e] 2
      "GENERAL_DATA_h2389025596"=hex:\(generalHex)
      "Screenmanager Is Fullscreen mode_h3981298716"=dword:00000001
      "Screenmanager Resolution Height_h2627697771"=dword:00000438
      "Screenmanager Resolution Width_h182942802"=dword:00000780
      "UnityGraphicsQuality_h1669003810"=dword:00000005
      """

    let updated = try WineUserRegistryEditor.updatedText(
      registry,
      preferences: .recommended
    )

    #expect(updated.contains("\"LocaleName\"=\"zh-CN\""))
    #expect(updated.contains("\"iCountry\"=\"86\""))
    #expect(updated.contains("\"Screenmanager Is Fullscreen mode_h3981298716\"=dword:00000000"))
    #expect(updated.contains("\"Screenmanager Resolution Width_h182942802\"=dword:00000640"))
    #expect(updated.contains("\"Screenmanager Resolution Height_h2627697771\"=dword:00000384"))
    #expect(updated.contains("\"UnityGraphicsQuality_h1669003810\"=dword:00000002"))
    #expect(updated.contains("\"MIHOYOSDK_CURRENT_LANGUAGE_h2559149783\"=hex:7a,68,2d,63,6e,00"))
    let updatedLines = updated.components(separatedBy: "\n")
    let gameSectionName = "[Software\\\\miHoYo\\\\\\x539f\\x795e] 2"
    let gameSection = try #require(updatedLines.firstIndex(of: gameSectionName))
    let countryLine = try #require(updatedLines.firstIndex(of: "\"sCountry\"=\"China\""))
    let sdkLanguage =
      "\"MIHOYOSDK_CURRENT_LANGUAGE_h2559149783\"=hex:7a,68,2d,63,6e,00"
    let sdkLanguageLine = try #require(
      updatedLines.firstIndex(of: sdkLanguage)
    )
    #expect(countryLine < gameSection)
    #expect(sdkLanguageLine > gameSection)
  }

  @Test("performance sampler aggregates only the active runtime processes")
  func performanceSampler() {
    let output = """
       100     1 1048576 75.5 /runtime/wine/bin/wine YuanShen.exe
       101   100  524288 24.5 /runtime/wine/bin/wineserver
       102     1   99999 50.0 /Applications/Unrelated.app/Contents/MacOS/Unrelated
       103   100  262144 10.0 C:\\windows\\ZFGameBrowser.exe
      """

    let sample = GamePerformanceSampler.parse(
      output,
      matching: ["/runtime/wine", "YuanShen.exe", "ZFGameBrowser.exe"]
    )

    #expect(sample.memoryBytes == 1_835_008 * 1_024)
    #expect(sample.cpuPercent == 110)
    #expect(sample.processCount == 3)
  }

  @Test("game library starts with the four configured CN games")
  @MainActor
  func gameLibraryStartsWithGenshin() throws {
    let suite = "BridgeStatusTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let library = GameLibraryStore(defaults: defaults)

    #expect(library.games == GameLibraryItem.miHoYoCN)
    #expect(library.games.map(\.isConfigured) == [true, true, true, true])
  }

  @Test("installer parses bounded progress without exposing file names")
  func installerProgressParser() throws {
    let progress = try #require(
      GameInstallerOutputParser.progress(
        from:
          "PROGRESS percent=25.500 downloaded=255 total=1000 bytes_per_second=50 eta_seconds=15"
      ))

    #expect(progress.fraction == 0.255)
    #expect(progress.downloadedBytes == 255)
    #expect(progress.totalBytes == 1_000)
    #expect(progress.bytesPerSecond == 50)
    #expect(progress.etaSeconds == 15)
    #expect(
      GameInstallerOutputParser.progress(
        from:
          "PROGRESS percent=50 downloaded=1001 total=1000 bytes_per_second=50 eta_seconds=1"
      ) == nil)
  }

  @Test("installer recognizes only explicit completion records")
  func installerCompletionParser() {
    #expect(
      GameInstallerOutputParser.completedVersion(
        from: "COMPLETE target=/redacted version=7.0.0") == "7.0.0")
    #expect(GameInstallerOutputParser.completedVersion(from: "FAILED version=7.0.0") == nil)
    #expect(GameInstallerOutputParser.availableVersion(from: "AVAILABLE version=7.1.0") == "7.1.0")
    #expect(GameInstallerOutputParser.availableVersion(from: "COMPLETE version=7.1.0") == nil)
  }

  @Test("performance report summarizes a completed balanced session")
  func performanceReport() throws {
    let launcherLog = """
      MGB_CONFIG graphics=balanced resolution=1600x900 window=windowed
      MGB_PERF rss_bytes=1073741824 peak_rss_bytes=1073741824 cpu_percent=30.0 processes=2
      warn: Emulate stream output
      MGB_PERF elapsed_seconds=4 rss_bytes=3221225472 peak_rss_bytes=3221225472 cpu_percent=70.0 processes=3
      """
    let gameLog = """
      submit shader load 2
      ignored
      submit shader load 4
      """

    let report = try #require(
      GamePerformanceReportParser.parse(launcherLog: launcherLog, gameLog: gameLog)
    )
    #expect(report.graphicsProfile == "balanced")
    #expect(report.benchmarkKind == "none")
    #expect(report.graphicsBackend == "unknown")
    #expect(report.resolution == "1600x900")
    #expect(report.durationSeconds == 4)
    #expect(report.sampleCount == 2)
    #expect(report.peakMemoryBytes == 3_221_225_472)
    #expect(report.averageMemoryBytes == 2_147_483_648)
    #expect(report.averageCPUPercent == 50)
    #expect(report.maximumCPUPercent == 70)
    #expect(report.maximumProcessCount == 3)
    #expect(report.shaderLoadCount == 2)
    #expect(report.streamOutputWarningCount == 1)
    #expect(report.framePerformance == nil)
  }

  @Test("performance report parses a bounded Metal HUD capture window")
  func framePerformanceReport() throws {
    let steadyFrames = Array(repeating: "16.67,4.00", count: 58)
    let slowFrames = Array(repeating: "25.00,8.00", count: 2)
    let frameValues = (steadyFrames + slowFrames).joined(separator: ",")
    let launcherLog = """
      MGB_CONFIG backend=gptk4 graphics=balanced resolution=1600x900 window=windowed
      MGB_BENCHMARK kind=gameplay
      2026-08-22 07:00:00.000 wine[1:1] metal-HUD: 1,100.0,200.0,500.00,20.00
      MGB_PERF elapsed_seconds=70 rss_bytes=4294967296 peak_rss_bytes=4294967296 cpu_percent=300.0 processes=4
      MGB_FRAME_CAPTURE_START
      2026-08-22 07:01:00.000 wine[1:1] metal-HUD: 2,100.0,200.0,0.05,1.00,\(frameValues)
      MGB_PERF elapsed_seconds=90 rss_bytes=2147483648 peak_rss_bytes=4294967296 cpu_percent=200.0 processes=3
      MGB_FRAME_CAPTURE_END
      MGB_PERF elapsed_seconds=105 rss_bytes=6442450944 peak_rss_bytes=6442450944 cpu_percent=400.0 processes=5
      """

    let report = try #require(
      GamePerformanceReportParser.parse(launcherLog: launcherLog, gameLog: nil)
    )
    let frames = try #require(report.framePerformance)
    #expect(report.graphicsBackend == "gptk4")
    #expect(report.benchmarkKind == "gameplay")
    #expect(report.durationSeconds == 1)
    #expect(report.sampleCount == 1)
    #expect(report.peakMemoryBytes == 2_147_483_648)
    #expect(report.averageCPUPercent == 200)
    #expect(frames.frameCount == 60)
    #expect(abs(frames.averageFPS - 59.01) < 0.02)
    #expect(abs(frames.onePercentLowFPS - 40) < 0.01)
    #expect(abs(frames.percentile95FrameTimeMilliseconds - 16.67) < 0.01)
    #expect(abs(frames.percentile99FrameTimeMilliseconds - 25) < 0.01)
    #expect(frames.slowFrameCount == 0)
    #expect(abs(frames.averageGPUTimeMilliseconds - 4.13) < 0.02)
  }

  @Test("installer prefers a self-contained downloader outside the source checkout")
  @MainActor
  func bundledInstallerToolchain() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(
      path: "mgb-bundled-downloader-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? manager.removeItem(at: root) }
    let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
    let downloader = resources.appending(path: "GameDownloader", directoryHint: .isDirectory)
    let python = downloader.appending(path: "python/bin/python3.11")
    let packages = downloader.appending(path: "python-packages", directoryHint: .isDirectory)
    let upstream = downloader.appending(path: "upstream", directoryHint: .isDirectory)
    let script = downloader.appending(path: "download_genshin_cn_full.py")
    try manager.createDirectory(
      at: python.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try manager.createDirectory(at: packages, withIntermediateDirectories: true)
    try manager.createDirectory(at: upstream, withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: python, atomically: true, encoding: .utf8)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
    try "pass\n".write(to: script, atomically: true, encoding: .utf8)
    try "revision=ca78abc29c2fc236261d088c6907d28cab6e9476\n".write(
      to: upstream.appending(path: ".mgb-pinned-upstream"),
      atomically: true,
      encoding: .utf8
    )

    let toolchain = try GameInstallationService.resolveToolchain(
      bundleResourceURL: resources,
      environment: [:],
      currentDirectoryURL: root.appending(path: "unrelated", directoryHint: .isDirectory)
    )

    #expect(toolchain.isBundled)
    #expect(toolchain.python == python)
    #expect(toolchain.pythonPackages == packages)
    #expect(toolchain.script == script)
    #expect(toolchain.upstream == upstream)
  }

  @Test("primary game action connects install, runtime preparation and launch")
  func primaryGameActionFlow() {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .notInstalled,
        runtime: .available,
        launcher: .unavailable("missing"),
        storage: .ready(remainingBytes: 1)
      ) == .install)
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .installed(version: "7.0.0"),
        runtime: .available,
        launcher: .unavailable("runtime"),
        storage: .insufficient(missingBytes: 1)
      ) == .prepareAndLaunch)
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .installed(version: "7.0.0"),
        runtime: .ready,
        launcher: .ready,
        storage: .unknown
      ) == .launch)
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .resumable,
        runtime: .preparing,
        launcher: .unavailable("game"),
        storage: .insufficient(missingBytes: 1)
      ) == .resumeInstall)
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .installed(version: "7.0.0"),
        runtime: .ready,
        launcher: .preparing,
        storage: .ready(remainingBytes: 1)
      ) == .disabled)
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .notInstalled,
        runtime: .available,
        launcher: .unavailable("game"),
        storage: .insufficient(missingBytes: 1)
      ) == .reviewStorage)
  }

  @Test("one-click setup progress keeps storage game runtime and launch in one flow")
  func oneClickSetupProgress() {
    let readyToInstall = GameSetupProgressResolver.resolve(
      installation: .notInstalled,
      runtime: .available,
      launcher: .unavailable("game"),
      storage: .ready(remainingBytes: 10)
    )
    #expect(readyToInstall.stage == .readyToInstall)
    #expect(readyToInstall.storage == .complete)
    #expect(readyToInstall.game == .pending)
    #expect(readyToInstall.fraction == 0.15)

    let parallel = GameSetupProgressResolver.resolve(
      installation: .installing(
        GameInstallationProgress(
          fraction: 0.5,
          downloadedBytes: 50,
          totalBytes: 100,
          bytesPerSecond: 10,
          etaSeconds: 5
        )
      ),
      runtime: .preparing,
      launcher: .unavailable("game"),
      storage: .insufficient(missingBytes: 1)
    )
    #expect(parallel.stage == .installingGameAndRuntime)
    #expect(parallel.storage == .complete)
    #expect(abs(parallel.fraction - 0.425) < 0.000_001)

    let blocked = GameSetupProgressResolver.resolve(
      installation: .notInstalled,
      runtime: .available,
      launcher: .unavailable("game"),
      storage: .insufficient(missingBytes: 42)
    )
    #expect(blocked.stage == .storageInsufficient(missingBytes: 42))
    #expect(blocked.storage == .attention)

    let ready = GameSetupProgressResolver.resolve(
      installation: .installed(version: "7.0.0"),
      runtime: .ready,
      launcher: .ready,
      storage: .insufficient(missingBytes: 42)
    )
    #expect(ready.stage == .ready)
    #expect(ready.fraction == 1)
  }

  @Test("initial install preflight rereads the live volume including absent target parents")
  func initialInstallLiveStoragePreflight() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "MacGameBridge-StorageTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let live = try InstallVolumeProbe.inspect(root, isDefaultPreview: false)
    let tiny = DownloadSpacePlan(
      resourceCacheBytes: 1,
      installedGameBytes: 1,
      safetyReserveBytes: 0
    )
    #expect(
      try GameInstallationService.liveInitialInstallReadiness(
        at: root.appending(path: "not-created/child", directoryHint: .isDirectory),
        plan: tiny
      ) != .unknown)

    let oneGiBTooLarge = DownloadSpacePlan(
      resourceCacheBytes: live.freeDiskBytes + 1_000_000_000,
      installedGameBytes: 0,
      safetyReserveBytes: 0
    )
    let result = try GameInstallationService.liveInitialInstallReadiness(
      at: root,
      plan: oneGiBTooLarge
    )
    guard case .insufficient(let missingBytes) = result else {
      Issue.record("live preflight should reject a plan larger than current free space")
      return
    }
    #expect(missingBytes > 0)
  }

  @Test("runtime installer assembles Wine, DXMT, prefix and Steam stubs")
  func runtimeAssetInstaller() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appending(
      path: "mgb-runtime-installer-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? manager.removeItem(at: root) }
    try manager.createDirectory(at: root, withIntermediateDirectories: true)

    let wineSource = root.appending(path: "wine-source/wine", directoryHint: .isDirectory)
    let wineBin = wineSource.appending(path: "bin", directoryHint: .isDirectory)
    try manager.createDirectory(at: wineBin, withIntermediateDirectories: true)
    let wineboot = wineBin.appending(path: "wineboot")
    try
      "#!/bin/sh\nset -eu\nmkdir -p \"$WINEPREFIX/drive_c/windows/system32\"\nmkdir -p \"$WINEPREFIX/drive_c/windows/syswow64\"\n"
      .write(to: wineboot, atomically: true, encoding: .utf8)
    let wine = wineBin.appending(path: "wine")
    try "#!/bin/sh\nexit 0\n".write(to: wine, atomically: true, encoding: .utf8)
    let wineserver = wineBin.appending(path: "wineserver")
    try "#!/bin/sh\nexit 0\n".write(to: wineserver, atomically: true, encoding: .utf8)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineboot.path)
    try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineserver.path)

    let wineArchive = root.appending(path: "wine.tar.xz")
    try runTestProcess(
      "/usr/bin/tar",
      ["-cJf", wineArchive.path, "-C", wineSource.deletingLastPathComponent().path, "wine"]
    )

    let dxmtSource = root.appending(path: "dxmt-source/v0.80", directoryHint: .isDirectory)
    let dxmtFiles = [
      "x86_64-unix/winemetal.so",
      "x86_64-windows/d3d10core.dll",
      "x86_64-windows/d3d11.dll",
      "x86_64-windows/dxgi.dll",
      "x86_64-windows/winemetal.dll",
      "x86_64-windows/nvngx.dll",
      "i386-windows/d3d10core.dll",
      "i386-windows/d3d11.dll",
      "i386-windows/dxgi.dll",
      "i386-windows/winemetal.dll",
    ]
    for path in dxmtFiles {
      let url = dxmtSource.appending(path: path)
      try manager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("dxmt:\(path)".utf8).write(to: url)
    }
    let dxmtArchive = root.appending(path: "dxmt.tar.gz")
    try runTestProcess(
      "/usr/bin/tar",
      ["-czf", dxmtArchive.path, "-C", dxmtSource.deletingLastPathComponent().path, "v0.80"]
    )

    let steam64 = try makeTestAsset(named: "steam64.exe", contents: "steam64", in: root)
    let steam32 = try makeTestAsset(named: "steam32.exe", contents: "steam32", in: root)
    let client64 = try makeTestAsset(named: "lsteamclient64.dll", contents: "client64", in: root)
    let client32 = try makeTestAsset(named: "lsteamclient32.dll", contents: "client32", in: root)
    let assets = RuntimePreparationAssets(
      wineArchive: wineArchive,
      dxmtArchive: dxmtArchive,
      steam64: steam64,
      steam32: steam32,
      lsteamclient64: client64,
      lsteamclient32: client32,
      expectations: RuntimeAssetExpectations(
        wine: try expectation(for: wineArchive),
        dxmt: try expectation(for: dxmtArchive),
        steam64: try expectation(for: steam64),
        steam32: try expectation(for: steam32),
        lsteamclient64: try expectation(for: client64),
        lsteamclient32: try expectation(for: client32)
      )
    )
    let storage = root.appending(path: "installed", directoryHint: .isDirectory)

    try RuntimeAssetInstaller.install(assets: assets, storageRoot: storage)

    let runtime = storage.appending(path: "Runtimes/genshin-cn-crossover11-steam")
    let prefix = storage.appending(path: "Prefixes/genshin-cn-crossover11-steam")
    #expect(manager.isExecutableFile(atPath: runtime.appending(path: "wine/bin/wineboot").path))
    #expect(
      try Data(contentsOf: runtime.appending(path: "wine/lib/wine/x86_64-windows/d3d11.dll"))
        == Data("dxmt:x86_64-windows/d3d11.dll".utf8))
    #expect(
      try Data(contentsOf: prefix.appending(path: "drive_c/windows/system32/steam.exe"))
        == Data("steam64".utf8))
    #expect(
      try Data(contentsOf: prefix.appending(path: "drive_c/windows/syswow64/lsteamclient.dll"))
        == Data("client32".utf8))
    #expect(manager.fileExists(atPath: runtime.appending(path: ".mgb-managed-runtime").path))
    #expect(manager.fileExists(atPath: prefix.appending(path: ".mgb-managed-runtime").path))
  }

  @Test("runtime paths prefer the self-contained user installation")
  func userRuntimePaths() throws {
    let manager = FileManager.default
    let suite = "BridgeStatusTests.InstallLocation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let root = manager.temporaryDirectory.appending(
      path: "mgb-runtime-paths-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? manager.removeItem(at: root) }
    let storage = root.appending(path: "support", directoryHint: .isDirectory)
    let runtime = storage.appending(path: "Runtimes/genshin-cn-crossover11-steam")
    let prefix = storage.appending(path: "Prefixes/genshin-cn-crossover11-steam")
    let game = root.appending(path: "game", directoryHint: .isDirectory)
    try manager.createDirectory(
      at: runtime.appending(path: "wine/bin"), withIntermediateDirectories: true)
    try manager.createDirectory(at: prefix, withIntermediateDirectories: true)
    try manager.createDirectory(at: game, withIntermediateDirectories: true)
    for executable in ["wine", "wineserver"] {
      let url = runtime.appending(path: "wine/bin/\(executable)")
      try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
      try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    try Data().write(to: game.appending(path: "YuanShen.exe"))
    #expect(throws: GameRuntimePathError.runtimeNotFound) {
      try GameRuntimePaths.resolveRuntime(
        environment: ["MGB_GENSHIN_CN_HOME": game.path],
        bundleURL: root.appending(path: "NoProject.app"),
        currentDirectory: root.appending(path: "no-project"),
        userStorageRoot: storage
      )
    }
    try RuntimeAssetInstaller.markerContents.write(
      to: runtime.appending(path: RuntimeAssetInstaller.markerName),
      atomically: true,
      encoding: .utf8
    )
    try RuntimeAssetInstaller.markerContents.write(
      to: prefix.appending(path: RuntimeAssetInstaller.markerName),
      atomically: true,
      encoding: .utf8
    )
    GameInstallLocationPreference.save(game, defaults: defaults)
    let configuredGameRoot = try #require(
      GameInstallLocationPreference.load(defaults: defaults))

    let paths = try GameRuntimePaths.resolve(
      environment: [:],
      bundleURL: root.appending(path: "NoProject.app"),
      currentDirectory: root.appending(path: "no-project"),
      userStorageRoot: storage,
      configuredGameRoot: configuredGameRoot
    )

    #expect(paths.runtimeRoot.path == runtime.path)
    #expect(paths.prefix.path == prefix.path)
    #expect(paths.gameExecutable.path == game.appending(path: "YuanShen.exe").path)
  }

  @Test("custom games use a separate versioned prefix and direct Windows path")
  func customGameLaunchPlan() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "mgb-custom-plan-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let executable = root.appending(path: "Demo Game.exe")
    try Data("MZ".utf8).write(to: executable)
    let runtime = GameRuntimePaths(
      projectRoot: root,
      runtimeRoot: root.appending(path: "runtime"),
      prefix: root.appending(path: "genshin-prefix"),
      gameExecutable: root.appending(path: "unused.exe")
    )

    let plan = try CustomGameLaunchPlan.make(
      gameID: "demo-123",
      executablePath: executable.path,
      storageRoot: root,
      runtimePaths: runtime
    )

    #expect(plan.prefix.lastPathComponent == "custom-demo-123-generic-dxmt-r1")
    #expect(plan.prefix.path != runtime.prefix.path)
    #expect(plan.windowsExecutablePath.hasSuffix("Demo Game.exe"))
    #expect(plan.environment["WINEPREFIX"] == plan.prefix.path)
  }

  @Test("legacy custom games migrate to compatibility profile revision one")
  func legacyCustomGameMigration() throws {
    let json = Data(
      """
      {"id":"legacy","title":"Demo","subtitle":"Old","executablePath":"/tmp/demo.exe","profile":"unconfigured"}
      """.utf8)
    let item = try JSONDecoder().decode(GameLibraryItem.self, from: json)

    #expect(item.profile == .unconfigured)
    #expect(item.profileRevision == 1)
  }

  private func runTestProcess(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
  }

  private func makeTestAsset(named name: String, contents: String, in root: URL) throws -> URL {
    let url = root.appending(path: name)
    try Data(contents.utf8).write(to: url)
    return url
  }

  private func expectation(for url: URL) throws -> RuntimeAssetExpectation {
    let data = try Data(contentsOf: url)
    let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return RuntimeAssetExpectation(byteSize: UInt64(data.count), sha256: sha256)
  }
}
