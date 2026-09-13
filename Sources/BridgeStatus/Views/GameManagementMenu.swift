import SwiftUI

struct GameManagementMenu: View {
  @ObservedObject var installer: GameInstallationService
  @ObservedObject var launcher: GameLaunchService
  let showManagement: (GameManagementSection) -> Void
  @State private var showRepairConfirmation = false

  var body: some View {
    Menu {
      Button("安装与更新…") { showManagement(.installation) }
      Button("安装位置与迁移…") { showManagement(.storage) }
      Divider()
      Button("检查更新") { installer.checkForUpdates() }
        .disabled(!isInstalled || !installer.canChangeStorage)
      Button("校验并修复…") { showRepairConfirmation = true }
        .disabled(!canModifyGame)
      Button("备份与回滚…") { showManagement(.recovery) }
      Button("打开游戏目录") { installer.revealGameFolder() }
      if installer.latestLogURL != nil || launcher.latestLogURL != nil {
        Divider()
        if installer.latestLogURL != nil {
          Button("查看安装日志") { installer.openLatestLog() }
        }
        if launcher.latestLogURL != nil {
          Button("查看启动日志") { launcher.openLatestLog() }
        }
      }
      if launcher.state == .running {
        Divider()
        Button("退出游戏", role: .destructive) { launcher.stopGame() }
      }
    } label: {
      Label("游戏管理", systemImage: "ellipsis")
        .labelStyle(.iconOnly)
        .font(.system(size: 18, weight: .semibold))
    }
    .menuIndicator(.hidden)
    .menuStyle(.borderlessButton)
    .frame(width: 44, height: 48)
    .background(LauncherTheme.ink.opacity(0.07), in: .rect(cornerRadius: 12))
    .accessibilityLabel("游戏管理")
    .help("游戏管理：安装、迁移、修复、备份与日志")
    .alert("校验并修复游戏？", isPresented: $showRepairConfirmation) {
      Button("取消", role: .cancel) {}
      Button("开始校验") {
        guard canModifyGame else { return }
        installer.startOrResume(selectedLocation: nil)
        showManagement(.installation)
      }
    } message: {
      Text("先创建安全备份，再按官方当前版本校验游戏文件；缺失或损坏的文件会重新下载。如果已有新版本，也会更新游戏。")
    }
  }

  private var isInstalled: Bool {
    if case .installed = installer.state { return true }
    return false
  }

  private var canModifyGame: Bool {
    isInstalled && installer.canChangeStorage && !launcher.state.isBusy
      && launcher.state != .running
  }
}
