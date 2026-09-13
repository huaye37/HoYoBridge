import SwiftUI

struct DownloadPlanView: View {
  @ObservedObject var store: StatusStore
  @ObservedObject var launcher: GameLaunchService
  @ObservedObject var installer: GameInstallationService
  @ObservedObject var runtimePreparer: RuntimePreparationService
  let section: GameManagementSection
  @State private var showRollbackConfirmation = false

  private let plan = DownloadSpacePlan.genshinOfficialCNInitialInstall

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        switch section {
        case .installation:
          installationCard
          if runtimePreparer.state != .ready { runtimePreparationCard }
          if installer.state == .notInstalled { readinessCard }
        case .storage:
          GameStorageView(store: store, installer: installer, launcher: launcher)
        case .recovery:
          Text("备份与回滚").font(.title2.weight(.semibold))
          Text("更新前自动创建安全备份；需要恢复旧版本时，可以在这里切换。")
            .foregroundStyle(.secondary)
          if shouldShowBackupPanel {
            backupPanel
          } else {
            Text("安装游戏后可使用备份与回滚。").foregroundStyle(.secondary)
          }
        }
      }
      .padding(28)
      .frame(maxWidth: 900, alignment: .leading)
    }
    .navigationTitle("安装与更新")
    .task {
      installer.refresh(selectedLocation: store.installLocation)
    }
    .onChange(of: store.installLocation) { _, selection in
      installer.refresh(selectedLocation: selection)
    }
    .onChange(of: runtimePreparer.state) { _, state in
      if state == .ready {
        launcher.refreshReadiness()
      }
    }
    .onChange(of: installer.state) { _, state in
      if case .installed = state {
        launcher.refreshReadiness()
      }
    }
    .alert("回滚游戏版本？", isPresented: $showRollbackConfirmation) {
      Button("取消", role: .cancel) {}
      Button("原子回滚", role: .destructive) {
        guard !gameIsActive else { return }
        installer.rollbackToBackup()
      }
    } message: {
      Text("将当前目录与安全备份交换。替换下来的文件仍保留，但未完成的更新不能再次作为可启动版本恢复。旧版本能否登录取决于服务器要求。")
    }
  }

  private var runtimePreparationCard: some View {
    HStack(alignment: .center, spacing: 16) {
      Image(systemName: runtimePreparationIcon)
        .font(.system(size: 21))
        .foregroundStyle(runtimePreparationColor)
        .frame(width: 44)
      VStack(alignment: .leading, spacing: 4) {
        Text(runtimePreparationTitle)
          .font(.headline)
        Text(runtimePreparationDetail)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      switch runtimePreparer.state {
      case .checking, .preparing:
        ProgressView()
          .controlSize(.small)
      case .available, .failed:
        Button("自动准备运行环境") {
          runtimePreparer.prepare()
        }
        .buttonStyle(.borderedProminent)
      case .unavailable:
        Button("重新检测") {
          runtimePreparer.refresh()
        }
      case .ready:
        Label("已就绪", systemImage: "checkmark")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.green)
      }
    }
    .padding(.vertical, 6)
  }

  private var installationCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(installationTitle)
            .font(.system(size: 20, weight: .semibold))
          Text(installationDetail)
            .foregroundStyle(.secondary)
          if case .installed = installer.state {
            Label(updateDetail, systemImage: updateIcon)
              .font(.callout)
              .foregroundStyle(updateColor)
          }
        }
        Spacer()
        Image(systemName: installationIcon)
          .font(.system(size: 30))
          .foregroundStyle(installationColor)
      }

      if case .installing(let progress) = installer.state {
        ProgressView(value: progress.fraction)
          .tint(.blue)
        HStack {
          Text(
            "\(StatusFormatting.bytes(progress.downloadedBytes)) / \(StatusFormatting.bytes(progress.totalBytes))"
          )
          Spacer()
          Text(progressDetail(progress))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      }

      if let message = installer.storageMessage {
        Text(message).font(.callout).foregroundStyle(.secondary)
      }

      HStack {
        installationAction
          .disabled(gameIsActive || runtimeAssetsMissing || installer.isStorageBusy)
        if installer.latestLogURL != nil {
          Button("查看安装日志") {
            installer.openLatestLog()
          }
          .buttonStyle(.link)
        }
        Spacer()
        Text(installer.targetURL.path(percentEncoded: false))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.vertical, 6)
  }

  private var runtimePreparationTitle: String {
    switch runtimePreparer.state {
    case .checking: "正在检查兼容运行环境"
    case .ready: "CrossOver 11 + DXMT 0.80 已就绪"
    case .available: "可以自动准备兼容运行环境"
    case .preparing: "正在解包运行时并创建独立 Prefix"
    case .unavailable: "运行环境资产尚未包含在此构建中"
    case .failed: "运行环境准备暂未完成"
    }
  }

  private var runtimePreparationDetail: String {
    switch runtimePreparer.state {
    case .checking: "正在检测应用资源和用户目录。"
    case .ready: "运行时、DXMT 与 Steam 兼容入口均可由启动器使用。"
    case .available: "使用应用内固定并校验的成功配置，不需要 Docker 或终端。"
    case .preparing: "首次准备会解压约 2 GB 内容，请保持应用运行。"
    case .unavailable(let message), .failed(let message): message
    }
  }

  private var runtimePreparationIcon: String {
    switch runtimePreparer.state {
    case .ready: "checkmark.seal.fill"
    case .failed, .unavailable: "exclamationmark.triangle.fill"
    default: "shippingbox.and.arrow.backward"
    }
  }

  private var runtimePreparationColor: Color {
    switch runtimePreparer.state {
    case .ready: .green
    case .failed, .unavailable: .orange
    default: .purple
    }
  }

  private var readinessCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(readinessTitle)
            .font(.title2.bold())
            .foregroundStyle(readinessColor)
          Text(readinessDetail)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: readinessIcon)
          .font(.system(size: 32))
          .foregroundStyle(readinessColor)
      }

      if let freeDiskBytes = selectedFreeDiskBytes, let required = plan.requiredPeakBytes {
        ProgressView(value: min(Double(freeDiskBytes) / Double(required), 1))
          .tint(readinessColor)
        HStack {
          Text("保守峰值预算 \(StatusFormatting.bytes(required))")
          Spacer()
          Text("当前可用 \(StatusFormatting.bytes(freeDiskBytes))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(18)
    .background(readinessColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(readinessColor.opacity(0.2), lineWidth: 1)
    }
  }

  @ViewBuilder
  private var installationAction: some View {
    switch installer.state {
    case .checking:
      ProgressView()
        .controlSize(.small)
    case .installed:
      HStack {
        switch installer.updateState {
        case .available(_, let target):
          Button("更新到 \(target)") {
            startInstallation()
          }
          .buttonStyle(.borderedProminent)
          .disabled(backupIsBusy || gameIsActive)
        case .current:
          Button("校验并修复") {
            startInstallation()
          }
          .disabled(backupIsBusy || gameIsActive)
        case .checking:
          ProgressView("正在检查版本…")
            .controlSize(.small)
        case .idle, .failed:
          Button("检查更新") {
            installer.checkForUpdates()
          }
        }
        Button("在 Finder 中显示") {
          installer.revealGameFolder()
        }
        .buttonStyle(.link)
      }
    case .notInstalled:
      Button("开始自动安装") {
        startInstallation()
      }
      .buttonStyle(.borderedProminent)
      .disabled(readinessRemainingBytes == nil)
    case .resumable, .failed:
      Button("继续安装") {
        startInstallation()
      }
      .buttonStyle(.borderedProminent)
    case .recoveryRequired:
      Button("继续更新或修复") { startInstallation() }
        .buttonStyle(.borderedProminent)
        .disabled(gameIsActive || !installer.canChangeStorage)
    case .installing:
      Button("取消", role: .destructive) {
        installer.cancel()
      }
    case .cancelling:
      ProgressView("正在暂停…")
        .controlSize(.small)
    case .unavailable:
      Button("重新检测") {
        installer.refresh(selectedLocation: store.installLocation)
      }
    }
  }

  private var shouldShowBackupPanel: Bool {
    if case .installed = installer.state { return true }
    if case .recoveryRequired = installer.state { return true }
    if case .none = installer.backupState { return false }
    return true
  }

  private var gameIsActive: Bool {
    launcher.state.isBusy || launcher.state == .running
  }

  private var runtimeAssetsMissing: Bool {
    if case .unavailable = runtimePreparer.state { return true }
    return false
  }

  private var gameIsInstalled: Bool {
    if case .installed = installer.state { return true }
    return false
  }

  private var backupIsBusy: Bool {
    switch installer.backupState {
    case .creating, .restoring: true
    case .none, .available, .failed: false
    }
  }

  private var backupPanel: some View {
    HStack(spacing: 12) {
      Image(systemName: backupIcon)
        .foregroundStyle(backupColor)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(backupTitle)
          .font(.callout.weight(.semibold))
        Text(backupDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      switch installer.backupState {
      case .none, .failed:
        Button("创建安全备份") {
          installer.createSafetyBackup()
        }
        .disabled(gameIsActive || !installer.canChangeStorage || !gameIsInstalled)
      case .available(let snapshot):
        if snapshot.isRestorable {
          Button(snapshot.version.map { "回滚到 \($0)" } ?? "回滚") {
            showRollbackConfirmation = true
          }
          .disabled(gameIsActive || !installer.canChangeStorage)
        } else {
          Button("创建新备份") { installer.createSafetyBackup() }
            .disabled(gameIsActive || !installer.canChangeStorage || !gameIsInstalled)
        }
      case .creating, .restoring:
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(12)
    .background(backupColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
  }

  private var backupTitle: String {
    switch installer.backupState {
    case .none: "尚未创建回滚点"
    case .creating: "正在创建 APFS 安全备份"
    case .available(let snapshot):
      snapshot.isRestorable
        ? (snapshot.version.map { "可回滚到 \($0)" } ?? "安全备份可用") : "已保留中断文件，不可作为回滚点"
    case .restoring: "正在原子回滚游戏目录"
    case .failed: "安全备份暂不可用"
    }
  }

  private var backupDetail: String {
    switch installer.backupState {
    case .none:
      installer.state == .recoveryRequired
        ? "未找到更新前备份，请继续修复；不会为中断目录创建安全备份。"
        : "更新前会自动创建；也可以现在手动准备。"
    case .creating: "使用 APFS 写时复制，通常不需要再复制一份完整游戏。"
    case .available(let snapshot):
      if snapshot.isRestorable {
        "创建于 \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))；继续修复不会覆盖此备份。"
      } else {
        "这些文件来自未完成的更新。可为当前完整版本创建新备份，替换此中断副本。"
      }
    case .restoring: "游戏必须保持关闭；目录交换完成后会重新检测版本。"
    case .failed(let message): message
    }
  }

  private var backupIcon: String {
    switch installer.backupState {
    case .available: "clock.arrow.circlepath"
    case .failed: "exclamationmark.triangle.fill"
    case .creating, .restoring: "externaldrive.badge.timemachine"
    case .none: "externaldrive"
    }
  }

  private var backupColor: Color {
    switch installer.backupState {
    case .available(let snapshot): snapshot.isRestorable ? .green : .orange
    case .failed: .orange
    case .creating, .restoring: .blue
    case .none: .secondary
    }
  }

  private var installationTitle: String {
    switch installer.state {
    case .checking: "正在检查安装状态"
    case .installed(let version): version.map { "原神 \($0) 已安装" } ?? "原神已经安装"
    case .notInstalled: "可以开始自动安装"
    case .resumable: "发现未完成的安装"
    case .recoveryRequired: "更新或校验需要恢复"
    case .installing: "正在下载并校验游戏"
    case .cancelling: "正在暂停安装"
    case .unavailable: "安装任务暂不可用"
    case .failed: "安装暂未完成"
    }
  }

  private var updateDetail: String {
    switch installer.updateState {
    case .idle: "尚未检查远端版本"
    case .checking: "正在查询国服主分支版本，不下载游戏内容"
    case .current(let version): "当前 \(version) 已是最新；可按需校验并修复文件"
    case .available(let installed, let target): "发现更新：\(installed) → \(target)，已有正确文件会复用"
    case .failed(let message): message
    }
  }

  private var updateIcon: String {
    switch installer.updateState {
    case .current: "checkmark.circle.fill"
    case .available: "arrow.down.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .idle, .checking: "arrow.triangle.2.circlepath"
    }
  }

  private var updateColor: Color {
    switch installer.updateState {
    case .current: .green
    case .available: .blue
    case .failed: .orange
    case .idle, .checking: .secondary
    }
  }

  private var installationDetail: String {
    switch installer.state {
    case .checking: "正在识别游戏目录和可恢复任务。"
    case .installed: "文件已存在，启动器会继续负责语言、窗口和运行参数。"
    case .notInstalled: "点击后自动容量预检、下载、续传并逐文件校验。"
    case .resumable: "保留已经验证的内容，只补齐剩余文件。"
    case .recoveryRequired: "暂不能启动；继续时重新校验并补齐文件，不会用中断目录覆盖原备份。"
    case .installing:
      if case .creating = installer.backupState {
        "正在创建更新前安全备份，完成后才会开始下载。"
      } else {
        "可以离开本页，任务会继续运行。"
      }
    case .cancelling: "正在安全停止当前下载，已完成内容会保留。"
    case .unavailable(let message): message
    case .failed(let message): message
    }
  }

  private var installationIcon: String {
    switch installer.state {
    case .installed: "checkmark.circle.fill"
    case .installing: "arrow.down.circle.fill"
    case .failed, .unavailable, .recoveryRequired: "exclamationmark.triangle.fill"
    default: "shippingbox"
    }
  }

  private var installationColor: Color {
    switch installer.state {
    case .installed: .green
    case .failed, .unavailable, .recoveryRequired: .orange
    default: .blue
    }
  }

  private var readinessRemainingBytes: UInt64? {
    guard case .ready(let remainingBytes) = readiness else { return nil }
    return remainingBytes
  }

  private func startInstallation() {
    guard !gameIsActive, !backupIsBusy else { return }
    if case .unavailable = runtimePreparer.state { return }
    switch runtimePreparer.state {
    case .available, .failed:
      runtimePreparer.prepare()
    case .checking, .ready, .preparing, .unavailable:
      break
    }
    installer.startOrResume(selectedLocation: store.installLocation)
  }

  private func progressDetail(_ progress: GameInstallationProgress) -> String {
    let speed = "\(StatusFormatting.bytes(progress.bytesPerSecond))/s"
    guard let eta = progress.etaSeconds else { return speed }
    return "\(speed) · 约 \(eta / 60) 分钟"
  }

  private var readiness: DownloadSpaceReadiness {
    plan.readiness(freeDiskBytes: selectedFreeDiskBytes)
  }

  private var selectedFreeDiskBytes: UInt64? {
    store.installLocation?.freeDiskBytes ?? store.report?.freeDiskBytes
  }

  private var readinessTitle: String {
    switch readiness {
    case .ready: "当前空间满足保守预算"
    case .insufficient: "当前空间不足"
    case .unknown: "正在等待本机磁盘检测"
    }
  }

  private var readinessDetail: String {
    switch readiness {
    case .ready(let remainingBytes):
      "按当前可用空间计算，完成保守峰值规划后约剩 \(StatusFormatting.bytes(remainingBytes))。"
    case .insufficient(let missingBytes):
      "按当前可用空间计算，至少还缺 \(StatusFormatting.bytes(missingBytes))。"
    case .unknown:
      "本页不会为了完成检测而创建文件。"
    }
  }

  private var readinessIcon: String {
    switch readiness {
    case .ready: "checkmark.circle.fill"
    case .insufficient: "exclamationmark.triangle.fill"
    case .unknown: "clock"
    }
  }

  private var readinessColor: Color {
    switch readiness {
    case .ready: .green
    case .insufficient: .orange
    case .unknown: .secondary
    }
  }
}
