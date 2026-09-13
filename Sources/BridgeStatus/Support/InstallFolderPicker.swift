import AppKit
import Foundation

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

    return panel.runModal() == .OK ? panel.url : nil
  }
}
