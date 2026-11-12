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
            Picker("游戏启动分辨率", selection: $resolutionRaw) {
              ForEach(resolutionOptions) { option in
                Text(option.title).tag(option.resolution.rawValue)
              }
            }
            Text("显示方式和启动分辨率应用于所有游戏；画质、语言及游戏内其他设置由各游戏独立管理。")
              .font(.caption).foregroundStyle(.secondary)
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
              "120 FPS 目标（实验）",
              isOn: Binding(
                get: { fpsUnlockModeRaw == GameFPSUnlockMode.fps120.rawValue },
                set: { fpsUnlockModeRaw = ($0 ? GameFPSUnlockMode.fps120 : .disabled).rawValue }
              ))
            Text("默认关闭。对所有游戏设置 120 FPS 渲染上限；原神另尝试解锁。其他游戏仍受各自帧率限制，未必能达到 120 FPS。")
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
