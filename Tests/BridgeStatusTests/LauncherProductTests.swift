import Foundation
import Testing

@testable import BridgeStatus

struct LauncherProductTests {
  @Test("saved GPTK selection is ignored by the DXMT-only launcher")
  func retiredBackend() throws {
    let name = "LauncherProductTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("gptk4", forKey: LauncherPreferenceKeys.graphicsBackend)
    #expect(GameLaunchPreferences.load(defaults: defaults).graphicsBackend == .dxmt)
  }

  @Test("incomplete application cannot start a large game download from home")
  func missingBundledRuntime() {
    #expect(
      GamePrimaryActionResolver.resolve(
        installation: .notInstalled, runtime: .unavailable("缺少组件"),
        launcher: .unavailable("未就绪"), storage: .ready(remainingBytes: 1)
      ) == .showInstallation)
  }

  @Test("fresh installs disable both experimental features")
  func defaultPreferences() throws {
    let name = "LauncherProductTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(GameLaunchPreferences.load(defaults: defaults) == .recommended)
  }

  @Test("old 144 FPS preference cannot enable more than 120 or hidden diagnostics")
  func legacyPreferences() throws {
    let name = "LauncherProductTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("fps144", forKey: LauncherPreferenceKeys.fpsUnlockMode)
    defaults.set(true, forKey: LauncherPreferenceKeys.detailedWineLoggingEnabled)
    defaults.set(false, forKey: LauncherPreferenceKeys.automaticDXMTFallbackEnabled)
    let loaded = GameLaunchPreferences.load(defaults: defaults)
    #expect(loaded.fpsUnlockMode == .disabled)
    #expect(!loaded.detailedWineLoggingEnabled)
    #expect(loaded.automaticDXMTFallbackEnabled)
    defaults.set("fps120", forKey: LauncherPreferenceKeys.fpsUnlockMode)
    defaults.set(true, forKey: LauncherPreferenceKeys.metalHUDEnabled)
    #expect(GameLaunchPreferences.load(defaults: defaults).fpsUnlockMode.targetFPS == 120)
    #expect(GameLaunchPreferences.load(defaults: defaults).metalHUDEnabled)
  }

  @Test("installation errors take priority and retain their explicit cause")
  func installationIssue() {
    let issue = LauncherIssue.resolve(
      installation: .failed("空间不足"), runtime: .available,
      launch: .unavailable("尚未准备"), update: .idle
    )
    #expect(issue?.title == "游戏安装未完成")
    #expect(issue?.detail == "空间不足")
    #expect(issue?.recovery.contains("游戏管理") == true)
  }

  @Test("ordinary first install is not shown as an error")
  func firstInstall() {
    #expect(
      LauncherIssue.resolve(
        installation: .notInstalled, runtime: .available,
        launch: .unavailable("尚未准备"), update: .idle
      ) == nil)
  }

  @Test("runtime failure reports stage and exit status")
  func runtimeFailure() {
    let detail = LauncherFailureDescription.describe(
      RuntimeAssetInstallerError.commandFailed("wineboot", 5))
    #expect(detail.contains("wineboot"))
    #expect(detail.contains("5"))
    #expect(
      LauncherFailureDescription.describe(GPTKPackageImportError.signatureRejected).contains("签名"))
  }

  @Test("unknown errors never display arbitrary credential-bearing descriptions")
  func redactedFailure() {
    let error = NSError(
      domain: "Test", code: 42,
      userInfo: [
        NSLocalizedDescriptionKey: "secret-token=/private/file"
      ])
    let detail = LauncherFailureDescription.describe(error)
    #expect(detail.contains("42"))
    #expect(!detail.contains("secret-token"))
  }
}
