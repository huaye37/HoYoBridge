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
    guard let controller else { show(message); return }
    guard !isBusy() else { show("请先结束游戏及下载、更新或修复任务，再更新启动器。"); return }
    guard controller.updater.canCheckForUpdates else { show("更新检查或安装流程正在进行，请完成当前更新窗口中的操作。"); return }
    controller.checkForUpdates(nil)
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    if isBusy() {
      throw NSError(domain: "HoYoBridge.Update", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "游戏或安装维护任务正在运行，启动器更新已暂缓。"])
    }
  }

  func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
    guard isBusy() else { return false }
    pendingInstall = installHandler
    message = "新版已准备好，等待游戏和安装维护任务结束后安装。"
    waitTask?.cancel()
    waitTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, let self else { return }
        if !self.isBusy() {
          let action = self.pendingInstall
          self.pendingInstall = nil
          action?()
          return
        }
      }
    }
    return true
  }

  private func show(_ text: String) {
    let alert = NSAlert()
    alert.messageText = "启动器更新"
    alert.informativeText = text
    alert.addButton(withTitle: "好")
    alert.runModal()
  }
}
