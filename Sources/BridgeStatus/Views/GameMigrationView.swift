import AppKit
import SwiftUI

struct GameMigrationView: View {
  let game: MiHoYoGame
  @ObservedObject var installer: OfficialGameInstaller
  @ObservedObject var launcher: MiHoYoGameLaunchService
  @Environment(\.dismiss) private var dismiss
  @State private var destination: InstallVolumeSelection?
  @State private var selectionError: String?

  private var progress: GameMigrationProgress? { installer.migrationProgress[game] }
  private var source: URL? { game.configuredDirectory }
  private var canChange: Bool {
    !installer.isOccupied && !launcher.state.isBusy && launcher.state != .running
      && !installer.blocksLaunch(for: game)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("迁移\(game.clientTitle)").font(.title2.bold())
      Text("复制游戏文件 → 校验完整性 → 自动切换启动和更新路径")
        .foregroundStyle(.secondary)
      if let source { Text("当前位置：\(source.path)").font(.callout).textSelection(.enabled) }
      if let destination, let source {
        Text("新位置：\(destination.url.appending(path: source.lastPathComponent).path)")
          .font(.callout).textSelection(.enabled)
        Text("可用空间：\(StatusFormatting.bytes(destination.freeDiskBytes))\n\(destination.storageAdvice)")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("选择新位置…") { selectDestination() }.disabled(!canChange || installer.migrationCopy(game) != nil)
        if let destination, let source {
          Button("开始迁移") { installer.migrateGame(game, from: source, to: destination.url) }
            .buttonStyle(.borderedProminent).disabled(!canChange || installer.migrationCopy(game) != nil)
        }
        if installer.migrationCopy(game) != nil {
          Button("完成迁移关联") { installer.retryMigrationAssociation(game) }
            .disabled(!canChange)
        }
      }
      if let progress {
        if progress.totalBytes > 0 {
          ProgressView(value: min(progress.fraction, 1))
          Text("\(StatusFormatting.bytes(progress.completedBytes)) / \(StatusFormatting.bytes(progress.totalBytes))")
            .font(.caption.monospacedDigit())
        } else { ProgressView().controlSize(.small) }
        HStack {
          Text(progress.phase)
          Spacer()
          Button("取消迁移") { installer.cancelMigration(game) }
            .disabled(progress.phase == "正在切换启动和更新路径")
        }
      }
      if let text = selectionError ?? installer.messages[game] {
        Text(text).font(.callout).textSelection(.enabled)
      }
      if let original = installer.retainedMigrationSources[game] {
        Button("查看保留的原副本") { NSWorkspace.shared.activateFileViewerSelecting([original]) }
      }
      if let copy = installer.migrationCopy(game) {
        Text("已完成的副本：\(copy.path)").font(.caption).textSelection(.enabled)
      }
      Text("原副本不自动删除；失败或取消时原文件保留。国服与国际服分别迁移，账号和兼容环境仍保留本机。迁移期间请保持磁盘连接，不要在其他启动器中更新或运行此游戏。")
        .font(.caption).foregroundStyle(.secondary)
      HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
    }
    .padding(24).frame(width: 600)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func selectDestination() {
    selectionError = nil
    guard canChange, let source,
      let url = InstallFolderPicker.choose(startingAt: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Games"),
        title: "选择迁移目标位置", message: "将在所选文件夹内创建 \(source.lastPathComponent)，不会覆盖已有目录。") else { return }
    do {
      let volume = try InstallVolumeProbe.inspect(url, isDefaultPreview: false)
      guard volume.isWritable else { throw GameStorageError.readOnly }
      let target = url.appending(path: source.lastPathComponent)
      if let issue = GameClientDirectoryPolicy.issue(for: target, client: game) {
        selectionError = issue; return
      }
      destination = volume
    } catch { selectionError = error.localizedDescription }
  }
}
