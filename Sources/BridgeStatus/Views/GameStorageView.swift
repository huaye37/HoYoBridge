import AppKit
import SwiftUI

struct GameStorageView: View {
  @ObservedObject var store: StatusStore
  @ObservedObject var installer: GameInstallationService
  @ObservedObject var launcher: GameLaunchService
  @State private var pendingLocation: InstallVolumeSelection?
  @State private var isMigration = false
  @State private var showConfirmation = false
  @State private var pickerError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("游戏存储", systemImage: "externaldrive")
        .font(.headline)
      Text(installer.targetURL.path(percentEncoded: false))
        .font(.callout).textSelection(.enabled)
      if let volume = store.installLocation {
        Text(
          "\(volume.volumeName) · \(volume.fileSystemName.uppercased()) · 可用 \(StatusFormatting.bytes(volume.freeDiskBytes))"
        )
        .font(.caption).foregroundStyle(.secondary)
        Text(volume.storageAdvice)
          .font(.callout)
          .foregroundStyle(volume.supportsCloning && !volume.isNetwork ? .secondary : .primary)
      }
      if let error = store.installLocationError {
        Text(error).font(.callout).foregroundStyle(.orange)
      }
      Text("游戏与新下载缓存放在所选磁盘；兼容运行环境仍保留在本机。网络盘请先通过 Finder 挂载。")
        .font(.caption).foregroundStyle(.secondary)

      HStack {
        if case .installed = installer.state {
          Button("迁移游戏…") { chooseLocation(migration: true) }
        } else {
          Button("选择安装位置…") { chooseLocation(migration: false) }
        }
        Button("定位已有游戏…") {
          if let url = InstallFolderPicker.choose(
            startingAt: installer.targetURL, title: "定位已有原神",
            message: "选择包含 YuanShen.exe 和 YuanShen_Data 的游戏文件夹，不要选择其上层目录。"
          ) {
            installer.locateExistingGame(url)
          }
        }
      }
      .disabled(!installer.canChangeStorage || gameIsActive)

      if let progress = installer.storageProgress {
        VStack(alignment: .leading, spacing: 8) {
          if progress.totalBytes > 0 {
            ProgressView(value: progress.fraction)
            Text(
              "\(StatusFormatting.bytes(progress.completedBytes)) / \(StatusFormatting.bytes(progress.totalBytes))"
            )
            .font(.caption.monospacedDigit())
          } else {
            ProgressView().controlSize(.small)
          }
          HStack {
            Text(progress.phase).font(.callout)
            Spacer()
            Button("取消迁移") { installer.cancelMigration() }
          }
        }
      }
      if let message = pickerError ?? installer.storageMessage {
        Text(message).font(.callout).textSelection(.enabled)
      }
      if let original = installer.retainedGameURL {
        Button("在 Finder 中检查原副本…") {
          NSWorkspace.shared.activateFileViewerSelecting([original])
        }
        .buttonStyle(.link)
      }
    }
    .padding(.vertical, 6)
    .alert(isMigration ? "迁移到这个位置？" : "使用这个安装位置？", isPresented: $showConfirmation) {
      Button("取消", role: .cancel) { pendingLocation = nil }
      Button(isMigration ? "复制并校验" : "使用此位置") {
        guard let location = pendingLocation, !gameIsActive else { return }
        if isMigration {
          installer.migrateGame(to: location.url)
        } else {
          installer.chooseNewLocation(location.url)
        }
        pendingLocation = nil
      }
    } message: {
      if let location = pendingLocation {
        Text(confirmationMessage(location))
      }
    }
  }

  private var gameIsActive: Bool { launcher.state.isBusy || launcher.state == .running }

  private func confirmationMessage(_ location: InstallVolumeSelection) -> String {
    let name = isMigration ? installer.targetURL.lastPathComponent : "Genshin Impact"
    let target = location.url.appending(path: name).path(percentEncoded: false)
    let operation =
      isMigration
      ? "将复制完整游戏，校验后切换启动位置。原副本不自动删除；游戏、官方启动器和其他更新程序需要保持关闭。"
      : "只保存安装位置，点击安装后才会下载游戏。"
    return "目标：\(target)\n\n\(operation)\n\n\(location.storageAdvice)"
  }

  private func chooseLocation(migration: Bool) {
    pickerError = nil
    guard
      let url = InstallFolderPicker.choose(
        startingAt: store.installLocation?.url,
        title: migration ? "选择迁移目标文件夹" : "选择安装位置",
        message: "在所选文件夹内创建游戏目录；可以选择已挂载的外置硬盘或网络盘。"
      )
    else { return }
    do {
      let location = try InstallVolumeProbe.inspect(url, isDefaultPreview: false)
      guard location.isWritable else { throw GameStorageError.readOnly }
      pendingLocation = location
      isMigration = migration
      showConfirmation = true
    } catch {
      pickerError = "无法使用所选位置，请检查磁盘连接及写入权限。"
    }
  }
}
