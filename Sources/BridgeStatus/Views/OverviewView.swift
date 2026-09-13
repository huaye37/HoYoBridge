import SwiftUI

struct OverviewView: View {
  private let snapshot = ObservedManifestSnapshot.genshinOfficialCN
  private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        boundaryBanner
        DownloadedGameCard()
        RuntimeExperimentCard()
        VerifiedChunkProbeCard()
        metrics
        milestones
        evidenceNote
      }
      .padding(28)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .navigationTitle("项目概览")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "gamecontroller.fill")
          .font(.title2)
          .foregroundStyle(.blue)
        Text("MacGameBridge")
          .font(.largeTitle.bold())
        Text("可启动 · 产品化阶段")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.blue.opacity(0.12), in: Capsule())
          .foregroundStyle(.blue)
      }

      Text("让 PC 版《原神》在 Apple Silicon Mac 上可维护地运行。")
        .font(.title3)
        .foregroundStyle(.secondary)
    }
  }

  private var boundaryBanner: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "info.circle.fill")
        .font(.title2)
        .foregroundStyle(.green)

      VStack(alignment: .leading, spacing: 5) {
        Text("原版国服客户端已经成功打开")
          .font(.headline)
        Text("当前主路径为 CrossOver 11 + DXMT + Steam 兼容入口。接下来把终端步骤收进原生启动器，并继续做登录与性能验收。")
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.green.opacity(0.22), lineWidth: 1)
    }
  }

  private var metrics: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("已验证的国服资源快照")
        .font(.title2.bold())

      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        MetricCard(
          title: "清单文件",
          value: StatusFormatting.count(snapshot.fileCount),
          detail: "结构已校验",
          systemImage: "doc.on.doc"
        )
        MetricCard(
          title: "资源分块引用",
          value: StatusFormatting.count(snapshot.chunkReferenceCount),
          detail: "\(StatusFormatting.count(snapshot.uniqueChunkObjectCount)) 个唯一对象",
          systemImage: "shippingbox"
        )
        MetricCard(
          title: "目标安装体积",
          value: StatusFormatting.bytes(snapshot.targetInstalledBytes),
          detail: "完整客户端已落盘",
          systemImage: "internaldrive"
        )
        MetricCard(
          title: "受控观测时间",
          value: StatusFormatting.observationDate.string(from: snapshot.observedAt),
          detail: "离线快照，非实时刷新",
          systemImage: "clock.arrow.circlepath"
        )
      }
    }
  }

  private var milestones: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("能力进度")
        .font(.title2.bold())

      VStack(spacing: 0) {
        ForEach(Array(StatusDemoData.milestones.enumerated()), id: \.element.id) { index, item in
          MilestoneRow(milestone: item)
          if index < StatusDemoData.milestones.count - 1 {
            Divider().padding(.leading, 44)
          }
        }
      }
      .padding(.horizontal, 16)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private var evidenceNote: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock.shield")
      Text(
        "这些数据只证明本地解析链能读懂该快照，不等于官方签名、版本可玩或兼容性验收。"
      )
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
  }
}

private struct MetricCard: View {
  let title: String
  let value: String
  let detail: String
  let systemImage: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title2.bold())
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct MilestoneRow: View {
  let milestone: DeliveryMilestone

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: milestone.state.systemImage)
        .font(.title3)
        .foregroundStyle(color)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(milestone.title)
            .font(.headline)
          Spacer()
          Text(milestone.state.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
        }
        Text(milestone.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 14)
  }

  private var color: Color {
    switch milestone.state {
    case .verified: .green
    case .foundation: .blue
    case .blocked: .orange
    case .notStarted: .secondary
    }
  }
}
