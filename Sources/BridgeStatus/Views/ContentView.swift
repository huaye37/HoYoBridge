import SwiftUI

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject var miHoYoLauncher: MiHoYoGameLaunchService
  @ObservedObject private var chineseInstaller = OfficialGameInstaller.shared
  @ObservedObject private var globalInstaller = OfficialGameInstaller.international
  @State private var selectedGame: MiHoYoGame = MiHoYoGame.starRail.rememberedClient()
  @State private var prerequisiteIssue: String?

  init(miHoYoLauncher: MiHoYoGameLaunchService, initialGame: MiHoYoGame? = nil) {
    self.miHoYoLauncher = miHoYoLauncher
    self._selectedGame = State(initialValue: initialGame ?? MiHoYoGame.starRail.rememberedClient())
  }

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        MiHoYoGameDetailView(game: selectedGame, launcher: miHoYoLauncher, selection: $selectedGame)
      }
      .id(selectedGame)
      .transition(.opacity)

      HStack {
        MiHoYoGameNavigationBar(selection: $selectedGame)
          .frame(width: 428, height: 52)
        Spacer()
        SettingsLink {
          Label("设置", systemImage: "gearshape")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(height: 42)
        }
        .buttonStyle(.plain)
        .allowsWindowActivationEvents(true)
        .help("启动设置")
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 8)
      .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }
    .animation(.easeOut(duration: 0.16), value: selectedGame)
    .onChange(of: selectedGame) { _, value in
      value.rememberRegion()
      Task { await LauncherArtworkStore.shared.refreshIfNeeded(regions: [value.region]) }
    }
    .task {
      prerequisiteIssue = await Task.detached(priority: .utility) {
        LauncherPrerequisites.issue()
      }.value
    }
    .alert("需要准备运行环境", isPresented: Binding(
      get: { prerequisiteIssue != nil },
      set: { if !$0 { prerequisiteIssue = nil } }
    )) {
      Button("Apple 安装指引") {
        NSWorkspace.shared.open(URL(string: "https://support.apple.com/zh-cn/102527")!)
      }
      Button("关闭", role: .cancel) {}
    } message: {
      Text(prerequisiteIssue ?? "")
    }
    .task { await LauncherArtworkStore.shared.refreshIfNeeded() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await LauncherArtworkStore.shared.refreshIfNeeded() }
      }
    }

  }
}

private struct MiHoYoGameDetailView: View {
  @ObservedObject private var officialInstaller: OfficialGameInstaller
  let game: MiHoYoGame
  @ObservedObject var launcher: MiHoYoGameLaunchService
  @Binding var selection: MiHoYoGame
  init(game: MiHoYoGame, launcher: MiHoYoGameLaunchService, selection: Binding<MiHoYoGame>) {
    self.game = game
    self.launcher = launcher
    self._selection = selection
    self.officialInstaller = OfficialGameInstaller.service(for: game)
  }
  @State private var refreshID = UUID()
  @State private var locationError: String?
  @State private var storagePerformanceNotice: String?
  @State private var showRepairConfirmation = false
  @State private var showAssociationConfirmation = false
  @State private var uninstallDirectory: URL?
  @State private var showUninstallConfirmation = false
  @State private var showDiscardConfirmation = false
  @State private var discardDirectory: URL?
  @State private var diskUsage: GameDiskUsage?
  @State private var measuringDiskUsage = false
  @State private var diskUsageRevision = UUID()

  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 18) {
          Text(game.title)
            .font(.system(size: 38, weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .gesture(WindowDragGesture())
          GameClientSwitcher(selection: $selection)
        }
        Text(game.tagline)
          .font(.system(size: 15))
          .foregroundStyle(.white.opacity(0.95))
        if game.region == .global {
          Text("国际服下载管理已接入，游戏启动兼容性尚待实测")
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 44)
      .allowsWindowActivationEvents(true)
      .padding(.bottom, 36)
      VStack(spacing: 18) {
        if let message = officialInstaller.blockingMessage(for: game) {
          Text(message).font(.callout).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let message = officialInstaller.messages[game] {
          Text(message).font(.callout).foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let message = issueMessage {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack(spacing: 16) {
          VStack(alignment: .leading, spacing: 7) {
            Text(statusTitle).font(.system(size: 17, weight: .semibold))
            Text(statusSubtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
              .lineLimit(1).truncationMode(.middle)
            if measuringDiskUsage || diskUsage != nil {
              Text(diskUsageText)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            }
            if isInstalled, let storagePerformanceNotice {
              Text(storagePerformanceNotice)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          Spacer()
          if officialInstaller.cleaningDownloads.contains(game) {
            ProgressView("正在清理下载…")
          } else if launcher.state == .running, launcher.activeGame == game {
            Button("退出游戏") { launcher.stop() }.buttonStyle(.bordered)
          } else if officialInstaller.checking.contains(game) {
            ProgressView("检查更新中…")
          } else if officialInstaller.busy.contains(game) {
            if officialInstaller.uninstalling.contains(game) {
              ProgressView("正在卸载…")
            } else if officialInstaller.controllableDownloads.contains(game) {
            Button((officialInstaller.paused.contains(game) ? "继续" : "暂停") + (officialInstaller.activeOperations[game]?.label ?? "下载")) {
              officialInstaller.togglePause()
            }.buttonStyle(.borderedProminent).tint(LauncherTheme.accent)
              .disabled(officialInstaller.changingDownloadState)
            } else {
              ProgressView("正在准备任务…")
            }
          } else if officialInstaller.hasPendingUninstall(game) {
            Button("检查卸载结果") { officialInstaller.reconcileUninstall(game) }
              .disabled(!officialInstaller.busy.isEmpty || !officialInstaller.checking.isEmpty || launcher.state.isBusy || launcher.state == .running)
          } else if let pending = OfficialGameInstaller.pendingOperation(for: game) {
            Button("重新连接\(pending == .repair ? "修复" : pending == .update ? "更新" : "安装")任务") {
              officialInstaller.resume(game)
            }
            .buttonStyle(.borderedProminent)
            .tint(LauncherTheme.accent)
            .disabled(!officialInstaller.canResume(game) || launcher.state.isBusy || launcher.state == .running)
          } else if game.installationDiskOffline {
            Button("重新检查磁盘") { refreshID = UUID() }
              .disabled(officialInstaller.isOccupied || launcher.state.isBusy || launcher.state == .running)
          } else if isInstalled {
            Button { launcher.launch(game) } label: {
              Label("开始游戏", systemImage: "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(minWidth: 160, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(LauncherTheme.accent)
            .disabled(launcher.state.isBusy || launcher.state == .running || officialInstaller.blocksLaunch(for: game))
          } else {
            Button("一键安装") { officialInstaller.install(game) }
              .buttonStyle(.borderedProminent)
              .tint(LauncherTheme.accent)
              .disabled(officialInstaller.isOccupied || launcher.state.isBusy || launcher.state == .running)
          }
          Menu {
            Button("检查更新") { officialInstaller.checkForUpdates(game) }
              .disabled(!canManage)
            Button("更新游戏") { officialInstaller.install(game, operation: .update) }
              .disabled(!canManage || !officialInstaller.updates.contains(game))
            Button("校验并修复…") { showRepairConfirmation = true }
              .disabled(!canManage)
            Button("关联当前目录到更新服务…") { showAssociationConfirmation = true }
              .disabled(!canManage)
            Divider()
            if officialInstaller.canEndTask(game) {
              Button("结束任务，保留文件") { officialInstaller.endTaskKeepingFiles(game) }
            }
            if OfficialGameInstaller.pendingOperation(for: game) == .install {
              Button("取消下载并清理文件…", role: .destructive) {
                discardDirectory = officialInstaller.incompleteDownloadDirectory(game)
                showDiscardConfirmation = discardDirectory != nil
              }
              .disabled(!officialInstaller.canDiscardDownload(game) || launcher.state.isBusy
                || (launcher.state == .running && launcher.activeGame == game))
            }
            Button("重新统计占用大小") { diskUsageRevision = UUID() }
              .disabled(installationDirectory == nil)
            Button("查看后台诊断") { officialInstaller.openDiagnostics() }
            Button("卸载游戏…", role: .destructive) {
              uninstallDirectory = game.executableURL?.deletingLastPathComponent()
              showUninstallConfirmation = uninstallDirectory != nil
            }.disabled(!canManage || !isInstalled)
            Button("重新定位游戏目录") { locateGame() }
              .disabled(officialInstaller.isOccupied || launcher.state == .running || launcher.state.isBusy)
            if launcher.latestLogURL != nil {
              Button("查看启动日志") { launcher.openLatestLog() }
            }
          } label: {
            Image(systemName: "ellipsis").frame(width: 32, height: 32)
          }
          .menuStyle(.borderlessButton)
          .fixedSize(horizontal: true, vertical: false)
        }
        .controlSize(.large)
        HStack {
          Text(game.regionDescription + "官服")
          Spacer()
          Text("CrossOver 11 + DXMT 0.80")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.85))
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 26)
      .foregroundStyle(.white)
      .shadow(color: .black.opacity(0.7), radius: 8, y: 2)
    }
    .id(refreshID)
    .task(id: game.configuredDirectory?.path ?? game.defaultDirectory.path) {
      let directory = game.configuredDirectory ?? game.defaultDirectory
      let notice = await Task.detached(priority: .utility) {
        StoragePerformanceNotice.message(for: directory)
      }.value
      guard !Task.isCancelled else { return }
      storagePerformanceNotice = notice
    }
    .task(id: diskUsageTaskID) {
      diskUsage = nil
      guard let root = installationDirectory else { measuringDiskUsage = false; return }
      measuringDiskUsage = true
      let scan = Task.detached(priority: .utility) { try GameDiskUsage.measure(root) }
      let result = await withTaskCancellationHandler {
        try? await scan.value
      } onCancel: { scan.cancel() }
      guard !Task.isCancelled else { return }
      diskUsage = result
      measuringDiskUsage = false
    }
    .background {
      LauncherArtworkView(game: game)
        .overlay {
          LinearGradient(
            colors: [.black.opacity(0.25), .clear, .black.opacity(0.65)],
            startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
    .preferredColorScheme(.dark)
    .alert("取消下载并清理\(game.clientTitle)？", isPresented: $showDiscardConfirmation) {
      Button("保留下载", role: .cancel) {}
      Button("取消并清理", role: .destructive) {
        guard let target = discardDirectory else { return }
        Task {
          _ = await officialInstaller.discardIncompleteDownload(game, expectedDirectory: target)
          refreshID = UUID()
          diskUsageRevision = UUID()
        }
      }
    } message: {
      Text("将停止此客户端下载，并由官方服务永久删除未完成的下载文件，无法恢复。其他客户端和兼容环境保留。剩余文件会尽可能移到废纸篓。\n\(discardDirectory?.path ?? "")")
    }
    .alert("卸载\(game.clientTitle)？", isPresented: $showUninstallConfirmation) {
      Button("取消", role: .cancel) {}
      Button("卸载", role: .destructive) {
        guard canManage, let target = uninstallDirectory else { return }
        Task {
          _ = await officialInstaller.uninstall(game, expectedDirectory: target)
          refreshID = UUID()
        }
      }
    } message: {
      Text("将永久删除以下位置的游戏安装内容，无法从废纸篓恢复；游戏目录内的本地文件请先备份。保留兼容环境与其他游戏。\n\(uninstallDirectory?.path ?? "")")
    }
    .alert("校验并修复\(game.clientTitle)？", isPresented: $showRepairConfirmation) {
      Button("取消", role: .cancel) {}
      Button("开始校验") {
        guard canManage else { return }
        officialInstaller.install(game, operation: .repair)
      }
    } message: {
      Text("官方服务会检查当前目录并下载缺失或损坏的文件，可能需要额外磁盘空间。任务完成前不能启动游戏。")
    }
    .alert("关联已有游戏？", isPresented: $showAssociationConfirmation) {
      Button("取消", role: .cancel) {}
      Button("关联当前目录") {
        guard canManage else { return }
        officialInstaller.associateDirectory(game)
      }
    } message: {
      Text("将当前所选目录登记到后台官方服务，不重新下载游戏整包。官方服务可能写入配置或准备配套组件。")
    }
  }

  private var canManage: Bool {
    isInstalled && !game.installationDiskOffline && !officialInstaller.isOccupied
      && !launcher.state.isBusy && launcher.state != .running
  }

  private var installationDirectory: URL? {
    if let path = UserDefaults.standard.string(forKey: "games.\(game.rawValue).pendingInstall") {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return game.configuredDirectory ?? (isInstalled ? game.defaultDirectory : nil)
  }

  private var diskUsageTaskID: String {
    "\(game.rawValue):\(installationDirectory?.path ?? ""):\(officialInstaller.busy.contains(game)):\(officialInstaller.paused.contains(game)):\(diskUsageRevision)"
  }

  private var diskUsageText: String {
    let title = OfficialGameInstaller.pendingOperation(for: game) == .install ? "已下载文件占用" : "游戏占用"
    guard let diskUsage else { return "\(title)：统计中…" }
    return "\(title)：\(diskUsage.approximate ? "约 " : "")\(StatusFormatting.bytes(diskUsage.bytes))"
  }

  private var isInstalled: Bool { game.executableURL != nil }

  private var issueMessage: String? {
    if let locationError { return locationError }
    guard launcher.stateGame == game else { return nil }
    if case .failed(let message) = launcher.state { return message }
    if case .unavailable(let message) = launcher.state { return message }
    return nil
  }

  private var statusTitle: String {
    if launcher.activeGame == game && launcher.state == .running { return "游戏运行中" }
    if launcher.stateGame == game && launcher.state == .preparing { return "正在准备启动" }
    if OfficialGameInstaller.pendingOperation(for: game) != nil { return "任务尚未完成 · 文件已保留" }
    if game.installationDiskOffline { return "安装磁盘未连接" }
    return isInstalled ? "已安装" : "尚未安装"
  }

  private var statusSubtitle: String {
    if game.installationDiskOffline {
      return "请重新连接磁盘后检查，安装记录已保留：\(game.configuredDirectory?.path ?? "")"
    }
    if launcher.stateGame == game && launcher.state == .preparing {
      return "正在应用独立兼容配置，请稍候"
    }
    if launcher.activeGame == game && launcher.state == .running {
      return "启动器正在跟踪运行状态"
    }
    if let root = installationDirectory { return root.path }
    return isInstalled
      ? game.executableURL?.deletingLastPathComponent().path ?? ""
      : "可选择本机、外置硬盘或已挂载的网络磁盘"
  }

  private var gameTint: Color {
    switch game {
    case .starRail, .starRailGlobal: Color(red: 0.22, green: 0.17, blue: 0.52)
    case .zenlessZoneZero, .zenlessZoneZeroGlobal: Color(red: 0.03, green: 0.35, blue: 0.32)
    case .honkaiImpact3, .honkaiImpact3Global: Color(red: 0.48, green: 0.18, blue: 0.38)
    case .genshin, .genshinGlobal: LauncherTheme.accent
    }
  }

  private func locateGame() {
    let panel = NSOpenPanel()
    panel.title = "定位\(game.clientTitle)"
    panel.message = "选择包含 \(game.executableNames.joined(separator: " / ")) 的游戏目录。"
    panel.prompt = "使用此目录"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = game.configuredDirectory ?? game.defaultDirectory.deletingLastPathComponent()
    guard let selected = InstallFolderPicker.runWithStorageNotice(panel) else { return }
    if let issue = GameClientDirectoryPolicy.issue(for: selected, client: game) {
      locationError = issue
      return
    }
    guard game.executableNames.contains(where: {
      FileManager.default.isReadableFile(atPath: selected.appending(path: $0).path)
    }) else {
      locationError = "该目录中没有找到\(game.executableNames.joined(separator: " / "))。"
      return
    }
    game.saveDirectory(selected)
    locationError = nil
    refreshID = UUID()
  }
}

private struct GameManagementView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var store: StatusStore
  @ObservedObject var launcher: GameLaunchService
  @ObservedObject var installer: GameInstallationService
  @ObservedObject var runtimePreparer: RuntimePreparationService
  @State private var section: GameManagementSection

  init(
    store: StatusStore, launcher: GameLaunchService, installer: GameInstallationService,
    runtimePreparer: RuntimePreparationService, initialSection: GameManagementSection
  ) {
    self.store = store
    self.launcher = launcher
    self.installer = installer
    self.runtimePreparer = runtimePreparer
    _section = State(initialValue: initialSection)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("游戏管理").font(.system(size: 22, weight: .semibold))
        Spacer()
        Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      .padding(24)
      Picker("管理分类", selection: $section) {
        ForEach(GameManagementSection.allCases) { item in
          Text(item.rawValue).tag(item)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 24).padding(.bottom, 20)
      Divider()
      DownloadPlanView(
        store: store, launcher: launcher, installer: installer,
        runtimePreparer: runtimePreparer, section: section
      )
    }
    .frame(width: 760, height: 500)
    .background(LauncherTheme.surface)
    .preferredColorScheme(.light)
    .tint(LauncherTheme.accent)
  }
}
