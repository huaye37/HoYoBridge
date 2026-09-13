import AppKit
import SwiftUI

@main
struct MacGameBridgeApp: App {
  @NSApplicationDelegateAdaptor(LauncherAppDelegate.self) private var appDelegate
  @StateObject private var miHoYoLauncher = MiHoYoGameLaunchService()

  var body: some Scene {
    WindowGroup("星桥 HoYoBridge", id: "main") {
      ContentView(
        miHoYoLauncher: miHoYoLauncher
      )
      .frame(minWidth: 720, minHeight: 560)
      .task {
        LauncherUpdateService.shared.isBusy = {
          miHoYoLauncher.state.isBusy || miHoYoLauncher.state == .running
            || OfficialGameInstaller.shared.isOccupied
        }
        LauncherUpdateService.shared.start()
      }
    }
    .defaultSize(width: 960, height: 640)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("检查启动器更新…") { LauncherUpdateService.shared.check() }
        Button("刷新游戏状态") {
          miHoYoLauncher.objectWillChange.send()
        }
        .keyboardShortcut("r", modifiers: .command)
      }
    }

    Settings {
      LauncherSettingsView()
        .frame(width: 620, height: 560)
        .preferredColorScheme(.light)
    }
  }
}

final class LauncherAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if LauncherUpdateService.shared.isBusy() {
      let alert = NSAlert()
      alert.messageText = "仍有游戏或安装维护任务正在运行"
      alert.informativeText = "请先结束任务，再退出或更新启动器。"
      alert.runModal()
      return .terminateCancel
    }
    return .terminateNow
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}
