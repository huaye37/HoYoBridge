enum GamePrimaryAction: Equatable {
  case disabled
  case install
  case resumeInstall
  case resumeRecovery
  case update(version: String)
  case reviewStorage
  case reconnectStorage
  case showInstallation
  case showRecovery
  case pauseInstall
  case cancelMigration
  case prepareAndLaunch
  case launch
  case running

  var title: String {
    switch self {
    case .disabled: "正在处理…"
    case .install: "安装游戏"
    case .resumeInstall: "继续安装"
    case .resumeRecovery: "继续更新或修复"
    case .update(let version): "更新至 \(version)"
    case .reviewStorage: "选择安装位置"
    case .reconnectStorage: "重新检查磁盘"
    case .showInstallation: "查看安装状态"
    case .showRecovery: "查看备份进度"
    case .pauseInstall: "暂停下载"
    case .cancelMigration: "取消迁移"
    case .prepareAndLaunch: "准备并启动"
    case .launch: "开始游戏"
    case .running: "游戏运行中"
    }
  }

  var symbol: String {
    switch self {
    case .launch, .prepareAndLaunch: "play.fill"
    case .pauseInstall: "pause.fill"
    case .cancelMigration: "xmark"
    case .reviewStorage, .reconnectStorage: "externaldrive"
    case .running: "checkmark"
    case .showRecovery: "clock.arrow.circlepath"
    case .disabled, .showInstallation: "ellipsis"
    case .install, .resumeInstall, .resumeRecovery, .update: "arrow.down"
    }
  }

  var isEnabled: Bool { self != .disabled && self != .running }
}

enum GamePrimaryActionResolver {
  static func resolve(
    installation: GameInstallationState,
    runtime: RuntimePreparationState,
    launcher: GameLaunchState,
    storage: DownloadSpaceReadiness,
    update: GameUpdateState = .idle,
    storageIsAccessible: Bool = true,
    isMigrating: Bool = false,
    backup: GameBackupState = .none
  ) -> GamePrimaryAction {
    if launcher.isBusy { return .disabled }
    if launcher == .running { return .running }
    if isMigrating { return .cancelMigration }
    switch backup {
    case .creating, .restoring: return .showRecovery
    default: break
    }
    // Active tasks must remain controllable even if a drive disconnects or runtime detection fails.
    if case .installing = installation { return .pauseInstall }
    if case .cancelling = installation { return .disabled }
    if !storageIsAccessible { return .reconnectStorage }
    if case .unavailable = runtime { return .showInstallation }
    switch installation {
    case .checking: return .disabled
    case .notInstalled:
      switch storage {
      case .ready: return .install
      case .insufficient: return .reviewStorage
      case .unknown: return .disabled
      }
    case .resumable: return .resumeInstall
    case .recoveryRequired: return .resumeRecovery
    case .failed:
      if case .insufficient = storage { return .reviewStorage }
      return .resumeInstall
    case .installing: return .pauseInstall
    case .cancelling: return .disabled
    case .unavailable: return .showInstallation
    case .installed:
      if case .available(_, let version) = update { return .update(version: version) }
      switch runtime {
      case .ready: return .launch
      case .available, .failed: return .prepareAndLaunch
      case .checking, .preparing: return .disabled
      case .unavailable: return .showInstallation
      }
    }
  }
}

enum GameManagementSection: String, CaseIterable, Identifiable {
  case installation = "安装与更新"
  case storage = "安装位置与迁移"
  case recovery = "备份与回滚"

  var id: Self { self }
}
