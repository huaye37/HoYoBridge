import SwiftUI

struct LauncherIssue: Equatable {
  let title: String
  let detail: String
  let recovery: String

  static func resolve(
    installation: GameInstallationState, runtime: RuntimePreparationState,
    launch: GameLaunchState, update: GameUpdateState
  ) -> Self? {
    switch installation {
    case .recoveryRequired:
      return Self(
        title: "更新或校验尚未完成", detail: "当前目录可能混有不同版本文件，暂时不能启动。",
        recovery: "点击“继续更新或修复”；也可在“游戏管理 → 备份与回滚”恢复旧版本。")
    case .failed(let message), .unavailable(let message):
      return Self(title: "游戏安装未完成", detail: message, recovery: "打开“游戏管理”检查安装位置与更新任务，或查看安装日志。")
    default: break
    }
    switch runtime {
    case .failed(let message), .unavailable(let message):
      return Self(title: "运行环境未就绪", detail: message, recovery: "重新准备运行环境；如果安装包缺少组件，请重新下载完整应用。")
    default: break
    }
    switch launch {
    case .failed(let message):
      return Self(title: "游戏启动失败", detail: message, recovery: "关闭实验功能，选择默认 DXMT 组合后重试；仍失败时查看启动日志。")
    case .unavailable(let message):
      if case .installed = installation, runtime == .ready {
        return Self(title: "游戏尚不能启动", detail: message, recovery: "在“游戏管理”中定位游戏目录或校验修复文件。")
      }
    default: break
    }
    if case .failed(let message) = update {
      return Self(title: "暂时无法检查更新", detail: message, recovery: "检查网络后，在“游戏管理”中重新检查。")
    }
    return nil
  }
}

struct LauncherIssueView: View {
  let installation: GameInstallationState
  let runtime: RuntimePreparationState
  let launch: GameLaunchState
  let update: GameUpdateState

  var body: some View {
    if let issue = LauncherIssue.resolve(
      installation: installation, runtime: runtime, launch: launch, update: update
    ) {
      VStack(alignment: .leading, spacing: 8) {
        Label(issue.title, systemImage: "exclamationmark.triangle.fill").font(.headline)
        Text(issue.detail).textSelection(.enabled)
        Text(issue.recovery).font(.callout)
      }
      .foregroundStyle(.orange)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.orange.opacity(0.08), in: .rect(cornerRadius: 14))
    }
  }
}
