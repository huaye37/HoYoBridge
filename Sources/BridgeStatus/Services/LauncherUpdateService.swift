import AppKit
import Sparkle

enum LauncherUpdateConfiguration {
  static func isValid(feed: String?, publicKey: String?) -> Bool {
    guard let feed, let url = URLComponents(string: feed),
      url.scheme == "https", let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.fragment == nil,
      let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return false }
    return true
  }
}

@MainActor
final class LauncherUpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
  static let shared = LauncherUpdateService()
  @Published private(set) var message = "正式更新源尚未开放；当前版本可继续使用。"
  var isBusy: () -> Bool = { false }
  var prepareForInstallation: @MainActor () async throws -> Bool = { true }
  private var controller: SPUStandardUpdaterController?
  private var pendingInstall: (() -> Void)?
  private var waitTask: Task<Void, Never>?

  var configured: Bool { controller != nil }
  var automaticChecks: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? false }
    set {
      controller?.updater.automaticallyChecksForUpdates = newValue
      objectWillChange.send()
    }
  }

  func start() {
    guard controller == nil, LauncherUpdateConfiguration.isValid(
      feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    ) else { return }
    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    do {
      try updater.updater.start()
      controller = updater
      message = "更新仅替换启动器，不修改已安装游戏或账号环境。"
    } catch {
      message = "更新组件未能初始化：\(error.localizedDescription)"
    }
  }

  func check() {
    if pendingInstall != nil && waitTask == nil { beginWaitingForInstallation(); return }
    guard let controller else { show(message); return }
    guard controller.updater.canCheckForUpdates else { show("更新检查或安装流程正在进行，请完成当前更新窗口中的操作。"); return }
    controller.checkForUpdates(nil)
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    // Checking and downloading an application update do not replace the running app.
    // Quiesce game/download work only after the user confirms installation.
  }

  func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
    postponeInstallationIfNeeded(installHandler)
  }

  func postponeInstallationIfNeeded(_ installHandler: @escaping () -> Void) -> Bool {
    guard isBusy() else { return false }
    pendingInstall = installHandler
    message = "新版已准备好。请退出游戏并暂停下载；已暂停任务会保留文件，随后安装新版。"
    beginWaitingForInstallation()
    return true
  }

  private func beginWaitingForInstallation() {
    waitTask?.cancel()
    waitTask = Task { [weak self] in
      while !Task.isCancelled {
        guard !Task.isCancelled, let self else { return }
        do {
          if try await self.prepareForInstallation(), !self.isBusy() {
            guard !Task.isCancelled else { return }
            let action = self.pendingInstall
            self.pendingInstall = nil
            self.waitTask = nil
            action?()
            return
          }
        } catch {
          self.message = "新版已下载，暂未安装：\(error.localizedDescription) 文件保留；处理后可再次点击检查更新重试。"
          self.waitTask = nil
          return
        }
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    waitTask?.cancel()
    waitTask = nil
    pendingInstall = nil
  }

  private func show(_ text: String) {
    let alert = NSAlert()
    alert.messageText = "启动器更新"
    alert.informativeText = text
    alert.addButton(withTitle: "好")
    alert.runModal()
  }
}
