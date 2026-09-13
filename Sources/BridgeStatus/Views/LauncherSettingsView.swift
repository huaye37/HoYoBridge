import SwiftUI

struct LauncherSettingsView: View {
  @ObservedObject private var updater = LauncherUpdateService.shared
  private enum Page: String, CaseIterable, Identifiable {
    case game = "游戏"
    case runtime = "运行环境"
    case experiments = "实验功能"
    case application = "应用更新"
    var id: String { rawValue }
  }

  @State private var page = Page.game
  @State private var resolutionOptions: [GameResolutionOption] = []
  @AppStorage(LauncherPreferenceKeys.windowMode)
  private var windowModeRaw = GameWindowMode.windowed.rawValue
  @AppStorage(LauncherPreferenceKeys.resolution)
  private var resolutionRaw = GameResolution.balanced.rawValue
  @AppStorage(LauncherPreferenceKeys.graphicsProfile)
  private var graphicsProfileRaw = GameGraphicsProfile.balanced.rawValue
  @AppStorage(LauncherPreferenceKeys.textLanguage)
  private var textLanguageRaw = GameTextLanguage.simplifiedChinese.rawValue
  @AppStorage(LauncherPreferenceKeys.voiceLanguage)
  private var voiceLanguageRaw = GameVoiceLanguage.simplifiedChinese.rawValue
  @AppStorage(LauncherPreferenceKeys.hideAfterLaunch)
  private var hideAfterLaunch = true
  @AppStorage(LauncherPreferenceKeys.fpsUnlockMode)
  private var fpsUnlockModeRaw = GameFPSUnlockMode.disabled.rawValue
  @AppStorage(LauncherPreferenceKeys.metalHUDEnabled)
  private var metalHUDEnabled = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 18) {
        Text("启动设置").font(.system(size: 25, weight: .semibold))
        Picker("设置分类", selection: $page) {
          ForEach(Page.allCases) { page in
            Text(page.rawValue).tag(page)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      .padding(24)
      Divider()
      switch page {
      case .application:
        Form {
          Section("星桥 HoYoBridge") {
            Text("当前版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")")
            Text(updater.message).foregroundStyle(.secondary)
            Toggle("自动检查启动器更新", isOn: Binding(
              get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }
            )).disabled(!updater.configured)
            Button("检查更新…") { updater.check() }
            Text("发现新版后由你确认安装。游戏及下载任务运行期间暂缓更新；游戏内容仍由各游戏的更新入口维护。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }.formStyle(.grouped)
      case .game:
        Form {
          Section("画面") {
            Picker("显示方式", selection: $windowModeRaw) {
              ForEach(GameWindowMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
              }
            }
            Picker("原神分辨率", selection: $resolutionRaw) {
              ForEach(resolutionOptions) { option in
                Text(option.title).tag(option.resolution.rawValue)
              }
            }
            Picker("原神图形档位", selection: $graphicsProfileRaw) {
              ForEach(GameGraphicsProfile.allCases) { profile in
                Text(profile.title).tag(profile.rawValue)
              }
            }
          }
          Section("原神语言（其他游戏请在游戏内设置）") {
            Picker("界面语言", selection: $textLanguageRaw) {
              ForEach(GameTextLanguage.allCases) { language in
                Text(language.title).tag(language.rawValue)
              }
            }
            Picker("语音语言", selection: $voiceLanguageRaw) {
              ForEach(GameVoiceLanguage.allCases) { language in
                Text(language.title).tag(language.rawValue)
              }
            }
          }
          Section {
            Toggle("启动后隐藏启动器", isOn: $hideAfterLaunch)
            Text("设置自动保存，下次启动游戏时生效。").font(.caption).foregroundStyle(.secondary)
          }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
      case .runtime:
        RuntimeSettingsView()
      case .experiments:
        Form {
          Section {
            Toggle(
              "原神解锁至 120 FPS",
              isOn: Binding(
                get: { fpsUnlockModeRaw == GameFPSUnlockMode.fps120.rawValue },
                set: { fpsUnlockModeRaw = ($0 ? GameFPSUnlockMode.fps120 : .disabled).rawValue }
              ))
            Text("默认关闭。120 是目标上限，不保证达到；会增加负载，并可能导致兼容问题或账号风险。游戏更新后不匹配时保持默认帧率。")
              .font(.caption).foregroundStyle(.secondary)
          }
          Section {
            Toggle("显示 Metal HUD 面板", isOn: $metalHUDEnabled)
            Text("默认关闭。手动开启后，在游戏画面上显示 Metal 性能指标；下次启动生效。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
      }
    }
    .background(LauncherTheme.surface)
    .tint(LauncherTheme.accent)
    .navigationTitle("启动设置")
    .task {
      resolutionOptions = GameResolutionCatalog.available
      if GameFPSUnlockMode(rawValue: fpsUnlockModeRaw) == nil {
        fpsUnlockModeRaw = GameFPSUnlockMode.disabled.rawValue
      }
    }
  }
}
