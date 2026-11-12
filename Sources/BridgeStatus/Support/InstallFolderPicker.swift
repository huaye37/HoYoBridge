import AppKit
import Foundation

enum StoragePerformanceNotice {
  static func message(isLocal: Bool?, isInternal: Bool?) -> String? {
    if isLocal == false {
      return "网络磁盘：加载速度取决于网络和存储性能，连接波动可能导致加载变慢或卡顿；使用时请保持连接。"
    }
    if isLocal == true && isInternal == false {
      return "外接磁盘：速度和连接稳定时通常可以流畅运行；读取较慢时，启动或场景加载可能变慢。"
    }
    return nil
  }

  static func message(for url: URL) -> String? {
    guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey]) else {
      return nil
    }
    return message(isLocal: values.volumeIsLocal, isInternal: values.volumeIsInternal)
  }
}

@MainActor
private final class StorageNoticeDelegate: NSObject, NSOpenSavePanelDelegate {
  private let label: NSTextField
  private var lookup: Task<Void, Never>?

  init(label: NSTextField) { self.label = label }

  func refresh(_ panel: NSOpenPanel) {
    refresh(url: panel.urls.first ?? panel.directoryURL)
  }

  private func refresh(url: URL?) {
    lookup?.cancel()
    guard let url else {
      label.stringValue = ""
      return
    }
    label.stringValue = ""
    lookup = Task { [weak self] in
      let message = await Task.detached(priority: .utility) {
        StoragePerformanceNotice.message(for: url)
      }.value
      guard !Task.isCancelled else { return }
      self?.label.stringValue = message ?? ""
    }
  }

  func panelSelectionDidChange(_ sender: Any?) {
    if let panel = sender as? NSOpenPanel { refresh(panel) }
  }

  func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) {
    refresh(url: url)
  }
}

@MainActor
enum InstallFolderPicker {
  static func choose(
    startingAt currentURL: URL?, title: String = "选择安装文件存放位置",
    message: String = "游戏与下载缓存将放在所选文件夹中，也可选择已连接的外置硬盘。"
  ) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.message = message
    panel.prompt = "选择此位置"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = false
    panel.directoryURL = currentURL
    return runWithStorageNotice(panel)
  }

  static func runWithStorageNotice(_ panel: NSOpenPanel) -> URL? {
    let label = NSTextField(wrappingLabelWithString: "")
    label.frame = NSRect(x: 0, y: 0, width: 500, height: 42)
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    panel.accessoryView = label
    panel.isAccessoryViewDisclosed = true
    let advisor = StorageNoticeDelegate(label: label)
    panel.delegate = advisor
    advisor.refresh(panel)
    return withExtendedLifetime(advisor) {
      panel.runModal() == .OK ? panel.url : nil
    }
  }
}
