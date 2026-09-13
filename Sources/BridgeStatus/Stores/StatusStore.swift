import BridgeCore
import Foundation

@MainActor
final class StatusStore: ObservableObject {
  @Published private(set) var report: CapabilityReport?
  @Published private(set) var isRefreshing = false
  @Published private(set) var installLocation: InstallVolumeSelection?
  @Published private(set) var installLocationError: String?

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    let captured = await Task.detached(priority: .userInitiated) {
      SystemProbe().capture()
    }.value
    report = captured
    refreshInstallLocation()
    isRefreshing = false
  }

  func selectInstallLocation(_ url: URL) {
    do {
      installLocation = try InstallVolumeProbe.inspect(url, isDefaultPreview: false)
      installLocationError = nil
    } catch {
      installLocation = nil
      installLocationError = "无法访问安装位置，请检查磁盘是否已连接或文件夹权限。"
    }
  }

  private func refreshInstallLocation() {
    let savedContainer = GameInstallLocationPreference.load()?.deletingLastPathComponent()
    let currentURL =
      installLocation?.url ?? savedContainer ?? FileManager.default.homeDirectoryForCurrentUser
    let isDefaultPreview = installLocation?.isDefaultPreview ?? (savedContainer == nil)
    do {
      installLocation = try InstallVolumeProbe.inspect(
        currentURL,
        isDefaultPreview: isDefaultPreview
      )
      installLocationError = nil
    } catch {
      installLocation = nil
      installLocationError = "无法访问安装位置，请重新连接磁盘。已保存的游戏路径不会改变。"
    }
  }
}
