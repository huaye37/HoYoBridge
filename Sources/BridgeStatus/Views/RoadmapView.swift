import SwiftUI

struct RoadmapView: View {
  private let phases = [
    RoadmapPhase(
      number: "01",
      title: "已完成：安全基础与清单验证",
      detail: "本机探测、签名目录、安全下载/缓存/回滚基础，以及国服主资源清单的受控结构验证。",
      color: .green
    ),
    RoadmapPhase(
      number: "02",
      title: "已完成：国服完整客户端下载",
      detail: "国服 7.0.0 的 2,673 个清单文件已下载并逐文件校验，版本、入口程序和数据目录均已复核。",
      color: .green
    ),
    RoadmapPhase(
      number: "03",
      title: "已完成：原版客户端成功启动",
      detail: "CrossOver 11 + DXMT + Steam 兼容入口已成功打开国服客户端，WDF 路线不再是当前主路径。",
      color: .green
    ),
    RoadmapPhase(
      number: "04",
      title: "当前：一键启动器与用户体验",
      detail: "自动应用中文、窗口、运行时和 Steam 参数，加入其他游戏入口，并完成登录与性能验收。",
      color: .blue
    ),
    RoadmapPhase(
      number: "05",
      title: "之后：全新机器自动安装与游戏更新",
      detail: "自动下载、校验和回滚运行时与游戏更新，并加入 GPTK 4 / DXMT 后端 A/B 测试。",
      color: .secondary
    ),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 6) {
          Text("从“能启动”到“一键可用”")
            .font(.largeTitle.bold())
          Text("启动路径已经验证，当前重点是把所有隐含步骤变成普通用户能理解的一键流程。")
            .foregroundStyle(.secondary)
        }

        ForEach(phases) { phase in
          RoadmapPhaseCard(phase: phase)
        }

        Label(
          "产品不会要求用户打开终端。游戏语言、窗口大小、Wine 前缀和兼容参数都由 MacGameBridge 在启动前自动处理。",
          systemImage: "wand.and.stars"
        )
        .font(.callout.weight(.medium))
        .padding(16)
        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
      }
      .padding(28)
      .frame(maxWidth: 880, alignment: .leading)
    }
    .navigationTitle("路线图")
  }
}

private struct RoadmapPhase: Identifiable {
  let number: String
  let title: String
  let detail: String
  let color: Color

  var id: String { number }
}

private struct RoadmapPhaseCard: View {
  let phase: RoadmapPhase

  var body: some View {
    HStack(alignment: .top, spacing: 18) {
      Text(phase.number)
        .font(.title2.monospacedDigit().bold())
        .foregroundStyle(phase.color)
        .frame(width: 42, alignment: .leading)

      VStack(alignment: .leading, spacing: 7) {
        Text(phase.title)
          .font(.title3.bold())
        Text(phase.detail)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}
