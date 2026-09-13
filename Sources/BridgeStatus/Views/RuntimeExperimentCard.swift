import SwiftUI

struct RuntimeExperimentCard: View {
  private let runtime = RuntimeExperimentSnapshot.genshinOfficialCN

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .font(.title2)
          .foregroundStyle(.green)

        VStack(alignment: .leading, spacing: 4) {
          Text("兼容启动链已经跑通")
            .font(.headline)
          Text(
            "Wine \(runtime.wineVersion) + DXMT \(runtime.dxmtVersion) + Steam 兼容入口已经成功打开原版国服客户端。"
          )
          .foregroundStyle(.secondary)
        }

        Spacer()

        Text("已验证启动")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.green)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.green.opacity(0.12), in: Capsule())
      }

      HStack(spacing: 16) {
        RuntimeCheck(title: "Windows \(runtime.windowsVersion)", passed: true)
        RuntimeCheck(title: "M5 Pro / Metal", passed: true)
        RuntimeCheck(title: runtime.blockerCode, passed: true)
      }

      Text("原版游戏文件 · 独立 prefix · 可安全停止和重启")
        .font(.caption)
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

private struct RuntimeCheck: View {
  let title: String
  let passed: Bool

  var body: some View {
    Label(
      title,
      systemImage: passed ? "checkmark.circle.fill" : "xmark.circle.fill"
    )
    .font(.caption.weight(.medium))
    .foregroundStyle(passed ? .green : .orange)
  }
}
