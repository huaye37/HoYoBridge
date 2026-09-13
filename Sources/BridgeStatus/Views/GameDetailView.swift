import SwiftUI

struct GameDetailView: View {
  @ObservedObject var store: StatusStore
  @ObservedObject var launcher: GameLaunchService
  @ObservedObject var installer: GameInstallationService
  @ObservedObject var runtimePreparer: RuntimePreparationService
  let showManagement: (GameManagementSection) -> Void
  @State private var launchAfterRuntimePreparation = false

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 20)
      VStack(alignment: .leading, spacing: 12) {
        Text("原神")
          .font(.system(size: 68, weight: .semibold, design: .serif))
          .tracking(8)
          .foregroundStyle(.white)
        Text("在 Mac 上，继续你的旅途。")
          .font(.system(size: 15))
          .foregroundStyle(.white.opacity(0.95))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 44)
      .allowsWindowActivationEvents(true)
      .gesture(WindowDragGesture())
      Spacer(minLength: 24)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let installLocationError = store.installLocationError {
            Label(
              installLocationError + " 可在“游戏管理 → 安装位置与迁移”中重新定位。",
              systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
          } else {
            LauncherIssueView(
              installation: installer.state, runtime: runtimePreparer.state,
              launch: launcher.state, update: installer.updateState
            )
          }
          if let notice = launcher.latestLaunchNotice {
            Label(notice, systemImage: "info.circle")
              .font(.callout).foregroundStyle(.white.opacity(0.9))
          }
          GameOperationStatusView(
            installation: installer.state, runtime: runtimePreparer.state,
            backup: installer.backupState, migration: installer.storageProgress
          )
          if installer.state == .notInstalled, case .insufficient(let missing) = storageReadiness {
            Text("安装位置空间不足，还需要 \(StatusFormatting.bytes(missing))。请选择其他磁盘。")
              .font(.callout).foregroundStyle(.orange)
          }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, hasStatusDetails ? 20 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: hasStatusDetails ? 100 : 0)
      launchBar
    }
    .background {
      LauncherArtworkView()
        .overlay {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0),
              .init(color: .clear, location: 0.4),
              .init(color: .black.opacity(0.2), location: 0.75),
              .init(color: .black.opacity(0.65), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
          )
        }
        .ignoresSafeArea()
    }
    .preferredColorScheme(.dark)
    .navigationTitle("原神启动器")
    .toolbar(removing: .title)
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    .onChange(of: runtimePreparer.state) { _, state in
      guard launchAfterRuntimePreparation else { return }
      switch state {
      case .ready:
        launchAfterRuntimePreparation = false
        guard primaryAction == .launch else { return }
        launcher.refreshReadiness()
        launcher.launchGenshin(preferences: .load())
      case .failed, .unavailable:
        launchAfterRuntimePreparation = false
      default: break
      }
    }
    .onChange(of: installer.state) { _, state in
      if case .installed = state { launcher.refreshReadiness() }
    }
    .onChange(of: installer.targetURL) { _, _ in launcher.refreshReadiness() }
  }

  private var hasStatusDetails: Bool {
    store.installLocationError != nil || launcher.latestLaunchNotice != nil
      || !isInstalled || runtimePreparer.state != .ready
      || installer.isStorageBusy || backupIsBusy
      || LauncherIssue.resolve(
        installation: installer.state, runtime: runtimePreparer.state,
        launch: launcher.state, update: installer.updateState
      ) != nil
  }

  private var launchBar: some View {
    VStack(spacing: 18) {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 9) {
          Text(launcher.state == .running ? "游戏运行中" : gameVersion)
            .font(.system(size: 17, weight: .semibold))
          Text(statusSubtitle)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.9))
        }
        Spacer(minLength: 0)
        Button(action: performPrimaryAction) {
          HStack(spacing: 16) {
            Text(primaryAction.title)
            Image(systemName: primaryAction.symbol)
          }
          .font(.system(size: 17, weight: .semibold))
          .frame(minWidth: 178, minHeight: 40)
          .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(LauncherTheme.accent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!primaryAction.isEnabled)
        GameManagementMenu(
          installer: installer, launcher: launcher,
          showManagement: showManagement
        )
      }
      .controlSize(.large)
      HStack(spacing: 18) {
        if !isInstalled, installer.canChangeStorage {
          Button("已有游戏？定位文件夹") { showManagement(.storage) }
        }
        Spacer()
        Text("原神国服 · 非官方启动器").foregroundStyle(.white.opacity(0.85))
      }
      .buttonStyle(.plain)
      .font(.system(size: 12))
      .foregroundStyle(.white.opacity(0.9))
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 26)
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.7), radius: 8, y: 2)
  }

  private var isInstalled: Bool {
    if case .installed = installer.state { return true }
    return false
  }

  private var gameVersion: String {
    switch installer.state {
    case .installed(let version): return version.map { "国服 · \($0)" } ?? "国服 · 已安装"
    case .installing: return "国服 · 安装任务进行中"
    case .resumable, .failed: return "国服 · 安装尚未完成"
    case .recoveryRequired: return "国服 · 更新或校验中断"
    case .cancelling: return "国服 · 正在暂停"
    case .checking: return "国服 · 正在检查"
    case .notInstalled, .unavailable: return "国服 · 尚未安装"
    }
  }

  private var backupIsBusy: Bool {
    switch installer.backupState {
    case .creating, .restoring: true
    default: false
    }
  }

  private var storageReadiness: DownloadSpaceReadiness {
    DownloadSpacePlan.genshinOfficialCNInitialInstall.readiness(
      freeDiskBytes: store.installLocation?.freeDiskBytes)
  }

  private var primaryAction: GamePrimaryAction {
    GamePrimaryActionResolver.resolve(
      installation: installer.state, runtime: runtimePreparer.state,
      launcher: launcher.state, storage: storageReadiness,
      update: installer.updateState, storageIsAccessible: store.installLocationError == nil,
      isMigrating: installer.isStorageBusy, backup: installer.backupState
    )
  }

  private var statusSubtitle: String {
    if installer.isStorageBusy { return "正在迁移，原副本会保留" }
    if backupIsBusy { return "正在处理安全备份" }
    if store.installLocationError != nil { return "安装磁盘不可访问，已保留原路径" }
    if launcher.state == .running { return "可在游戏管理中退出游戏" }
    if launcher.state == .preparing { return "正在启动游戏，请稍候" }
    if launcher.state == .stopping { return "正在退出游戏，请稍候" }
    if case .installing = installer.state { return "可离开管理页，任务会继续" }
    if case .cancelling = installer.state { return "正在停止任务，已下载内容会保留" }
    if case .resumable = installer.state { return "继续时会复用已下载的内容" }
    if case .recoveryRequired = installer.state { return "请继续修复，或在游戏管理中恢复备份" }
    if case .preparing = runtimePreparer.state { return "正在自动准备运行环境" }
    if case .available(_, let version) = installer.updateState { return "新版本 \(version) 已发布" }
    if case .checking = installer.updateState { return "正在检查新版本…" }
    if !isInstalled { return "官方游戏文件 · 自动准备运行环境" }
    return "已安装 · 随时出发"
  }

  private func performPrimaryAction() {
    switch primaryAction {
    case .launch:
      launcher.refreshReadiness()
      launcher.launchGenshin(preferences: .load())
    case .prepareAndLaunch:
      launchAfterRuntimePreparation = true
      runtimePreparer.prepare()
    case .install, .resumeInstall, .resumeRecovery, .update:
      switch runtimePreparer.state {
      case .available, .failed: runtimePreparer.prepare()
      default: break
      }
      installer.startOrResume(selectedLocation: store.installLocation)
      showManagement(.installation)
    case .pauseInstall: installer.cancel()
    case .cancelMigration: installer.cancelMigration()
    case .reviewStorage: showManagement(.storage)
    case .showRecovery: showManagement(.recovery)
    case .showInstallation: showManagement(.installation)
    case .reconnectStorage:
      Task {
        await store.refresh()
        installer.refresh(selectedLocation: store.installLocation)
        launcher.refreshReadiness()
        if store.installLocationError != nil { showManagement(.storage) }
      }
    case .disabled, .running: break
    }
  }
}
