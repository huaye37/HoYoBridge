import SwiftUI

struct DownloadedGameCard: View {
  private let download = DownloadedGameSnapshot.genshinOfficialCN

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "checkmark.seal.fill")
          .font(.title2)
          .foregroundStyle(.green)

        VStack(alignment: .leading, spacing: 4) {
          Text("国服完整客户端已下载")
            .font(.headline)
          Text(
            "版本 \(download.version)，\(StatusFormatting.count(download.manifestFileCount)) 个清单文件已落盘并逐文件校验。"
          )
          .foregroundStyle(.secondary)
        }

        Spacer()

        Text("下载完成")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.green)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.green.opacity(0.12), in: Capsule())
      }

      HStack(spacing: 16) {
        DownloadCheck(title: "YuanShen.exe")
        DownloadCheck(title: "YuanShen_Data")
        DownloadCheck(title: "版本 7.0.0")
        DownloadCheck(title: StatusFormatting.bytes(download.installedBytes))
      }

      Text("完成时间  \(StatusFormatting.observationDate.string(from: download.completedAt))")
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(.green.opacity(0.2), lineWidth: 1)
    }
  }
}

private struct DownloadCheck: View {
  let title: String

  var body: some View {
    Label(title, systemImage: "checkmark.circle.fill")
      .font(.caption.weight(.medium))
      .foregroundStyle(.green)
  }
}
