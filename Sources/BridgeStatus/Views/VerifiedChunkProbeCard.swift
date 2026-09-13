import SwiftUI

struct VerifiedChunkProbeCard: View {
  private let probe = VerifiedChunkProbeSnapshot.genshinOfficialCN

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "checkmark.seal.fill")
          .font(.title2)
          .foregroundStyle(.green)

        VStack(alignment: .leading, spacing: 4) {
          Text("首个真实资源分块已验证")
            .font(.headline)
          Text(
            "已从国服 CDN 下载确定性最小 chunk（\(probe.compressedBytes) 字节）并存入私有内容寻址缓存。"
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        Text("真实下载")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.green)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.green.opacity(0.12), in: Capsule())
      }

      HStack(spacing: 16) {
        ProbeCheck(title: "压缩大小")
        ProbeCheck(title: "压缩 MD5")
        ProbeCheck(title: "zstd 解压")
        ProbeCheck(title: "解压后 MD5")
      }

      Text("SHA-256  \(shortSHA)")
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(16)
    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(.green.opacity(0.2), lineWidth: 1)
    }
  }

  private var shortSHA: String {
    "\(probe.sha256.prefix(12))…\(probe.sha256.suffix(12))"
  }
}

private struct ProbeCheck: View {
  let title: String

  var body: some View {
    Label(title, systemImage: "checkmark.circle.fill")
      .font(.caption.weight(.medium))
      .foregroundStyle(.green)
  }
}
