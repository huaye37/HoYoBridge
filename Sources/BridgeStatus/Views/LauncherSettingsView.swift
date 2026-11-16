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
  init(initialPage: String = "游戏") {
    self._page = State(initialValue: Page(rawValue: initialPage) ?? .game)
  }
  @State private var resolutionOptions: [GameResolutionOption] = []
  @State private var displays: [GameDisplay] = []
  @AppStorage(GameDisplayCatalog.preferenceKey) private var targetDisplay = ""
  @State private var customWidth = ""
  @State private var customHeight = ""
  @State private var resolutionError: String?
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
            Text("可以随时检查更新。确认安装后，已暂停的下载会保留文件；游戏运行或下载写入时等待，退出游戏并暂停下载后继续安装。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }.formStyle(.grouped)
      case .game:
        Form {
          Section("画面") {
            Picker("游戏显示器", selection: $targetDisplay) {
              Text("自动选择横屏").tag("")
              ForEach(displays) { display in
                Text(display.title).tag(display.id).disabled(display.isPortrait)
              }
              if !targetDisplay.isEmpty && !displays.contains(where: { $0.id == targetDisplay }) {
                Text("所选显示器已断开（暂用其他横屏）").tag(targetDisplay)
              }
            }
            Text("已识别 \(displays.count) 块屏幕，\(displays.filter { !$0.isPortrait }.count) 块横屏可用于游戏。竖屏不自动分配游戏窗口。")
              .font(.caption).foregroundStyle(.secondary)
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
            HStack {
              Text("自定义分辨率")
              Spacer()
              TextField("宽", text: $customWidth).frame(width: 80)
              Text("×")
              TextField("高", text: $customHeight).frame(width: 80)
              Button("应用") {
                guard let value = GameResolution(rawValue: "\(customWidth)x\(customHeight)") else {
                  resolutionError = "请输入有效的宽高（宽320–16384，高200–16384）。"
                  return
                }
                resolutionRaw = value.rawValue
                reloadResolutions()
              }
            }.textFieldStyle(.roundedBorder)
            if let resolutionError { Text(resolutionError).font(.caption).foregroundStyle(.red) }
            Text("显示方式和启动分辨率应用于所有游戏；画质、语言及游戏内其他设置由各游戏独立管理。")
              .font(.caption).foregroundStyle(.secondary)
            Text("窗口可拖动边缘缩放，左上角绿钮切换 macOS 全屏。分辨率列表按所选横屏整理，并保留常用尺寸和自定义输入；HiDPI 渲染像素不等于面板物理分辨率。")
              .font(.caption).foregroundStyle(.secondary)
            Text("这里设置下次启动时的屏幕、窗口和尺寸，不实时修改正在运行的游戏。游戏内分辨率菜单由游戏决定，可能受当前显示器及原生全屏限制。")
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
      reloadResolutions()
      if GameFPSUnlockMode(rawValue: fpsUnlockModeRaw) == nil {
        fpsUnlockModeRaw = GameFPSUnlockMode.disabled.rawValue
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      reloadResolutions()
    }
    .onChange(of: resolutionRaw) { _, _ in reloadResolutions() }
    .onChange(of: targetDisplay) { _, _ in reloadResolutions() }
  }

  private func reloadResolutions() {
    displays = GameDisplayCatalog.connected
    let selected = GameDisplayCatalog.selected(in: displays, preferredID: targetDisplay)
    resolutionOptions = GameResolutionCatalog.available(on: selected?.displayID)
    guard let current = GameResolution(rawValue: resolutionRaw) else { return }
    customWidth = String(current.width)
    customHeight = String(current.height)
    resolutionError = nil
    if !resolutionOptions.contains(where: { $0.resolution == current }) {
      resolutionOptions.insert(.init(resolution: current, isCurrentDesktop: false, isNativePixels: false, isCommon: false), at: 0)
    }
  }
}
