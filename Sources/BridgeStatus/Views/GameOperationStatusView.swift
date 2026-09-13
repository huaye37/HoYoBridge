import SwiftUI

struct GameOperationStatusView: View {
  let installation: GameInstallationState
  let runtime: RuntimePreparationState
  let backup: GameBackupState
  let migration: GameMigrationProgress?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let migration {
        Text(migration.phase).font(.headline)
        if migration.totalBytes > 0 {
          ProgressView(value: migration.fraction)
          byteCount(migration.completedBytes, total: migration.totalBytes)
        } else {
          ProgressView().controlSize(.small)
        }
      } else if backup == .creating || backup == .restoring {
        ProgressView(backup == .creating ? "正在创建安全备份…" : "正在回滚游戏版本…")
          .controlSize(.small)
      } else if case .installing(let progress) = installation {
        Text("正在下载并校验游戏").font(.headline)
        ProgressView(value: progress.fraction)
        HStack {
          byteCount(progress.downloadedBytes, total: progress.totalBytes)
          Spacer()
          Text("\(StatusFormatting.bytes(progress.bytesPerSecond))/s")
            .font(.caption.monospacedDigit())
        }
      } else if case .cancelling = installation {
        ProgressView("正在暂停，已完成内容会保留…").controlSize(.small)
      } else if case .notInstalled = installation {
        Text("首次安装会自动准备游戏和运行环境；账号登录在游戏内完成。")
          .font(.callout).foregroundStyle(.secondary)
      }
      if case .preparing = runtime {
        ProgressView("正在准备运行环境…").controlSize(.small)
      }
    }
  }

  private func byteCount(_ completed: UInt64, total: UInt64) -> some View {
    Text("\(StatusFormatting.bytes(completed)) / \(StatusFormatting.bytes(total))")
      .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
  }
}
