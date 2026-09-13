import BridgeCore
import SwiftUI

struct EnvironmentView: View {
  @ObservedObject var store: StatusStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        if let report = store.report {
          environmentCard(report)
          findingsCard(report)
        } else {
          ProgressView("正在只读检测本机…")
            .frame(maxWidth: .infinity, minHeight: 260)
        }
      }
      .padding(28)
      .frame(maxWidth: 880, alignment: .leading)
    }
    .navigationTitle("本机环境")
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text("本机兼容性检测")
          .font(.largeTitle.bold())
        Text("只读检查 macOS、Apple Silicon、Metal、Rosetta、GPTK 和剩余空间。")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        Task { await store.refresh() }
      } label: {
        Label("重新检测", systemImage: "arrow.clockwise")
      }
      .disabled(store.isRefreshing)
      .keyboardShortcut("r", modifiers: .command)
    }
  }

  private func environmentCard(_ report: CapabilityReport) -> some View {
    VStack(spacing: 0) {
      EnvironmentRow(label: "macOS", value: report.macOSVersion, systemImage: "apple.logo")
      Divider()
      EnvironmentRow(
        label: "架构与机型",
        value: [report.architecture, report.hardwareModel].compactMap { $0 }.joined(
          separator: " · "),
        systemImage: "cpu"
      )
      Divider()
      EnvironmentRow(
        label: "物理内存",
        value: StatusFormatting.bytes(report.physicalMemoryBytes),
        systemImage: "memorychip"
      )
      Divider()
      EnvironmentRow(
        label: "可用磁盘",
        value: report.freeDiskBytes.map(StatusFormatting.bytes) ?? "未知",
        systemImage: "internaldrive"
      )
      Divider()
      EnvironmentRow(
        label: "Metal",
        value: report.metal.deviceName ?? "不可用",
        systemImage: "sparkles"
      )
      Divider()
      EnvironmentRow(
        label: "Rosetta 2",
        value: componentText(report.rosetta),
        systemImage: "arrow.triangle.2.circlepath"
      )
      Divider()
      EnvironmentRow(
        label: "GPTK / D3DMetal",
        value: componentText(report.gptk),
        systemImage: "wrench.and.screwdriver"
      )
    }
    .padding(.horizontal, 16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func findingsCard(_ report: CapabilityReport) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("检测结论")
        .font(.title2.bold())

      if report.findings.isEmpty {
        Label("未发现当前基础目标的明确阻断项。", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      } else {
        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: findingIcon(finding.severity))
              .foregroundStyle(findingColor(finding.severity))
            VStack(alignment: .leading, spacing: 3) {
              Text(findingTitle(finding.code))
                .font(.headline)
              Text(findingMessage(finding.code))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  private func componentText(_ component: ComponentStatus) -> String {
    switch component.availability {
    case .installed:
      component.version.map { "已安装 · \($0)" } ?? "已安装"
    case .missing: "未检测到"
    case .unknown: "无法确认"
    }
  }

  private func findingIcon(_ severity: FindingSeverity) -> String {
    switch severity {
    case .info: "info.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .blocker: "xmark.octagon.fill"
    }
  }

  private func findingColor(_ severity: FindingSeverity) -> Color {
    switch severity {
    case .info: .blue
    case .warning: .orange
    case .blocker: .red
    }
  }

  private func findingTitle(_ code: String) -> String {
    switch code {
    case "unsupported-macos-version": "macOS 版本不在首期范围"
    case "unsupported-architecture": "不是 Apple Silicon"
    case "metal-unavailable": "Metal 不可用"
    case "rosetta-missing": "未检测到 Rosetta 2"
    case "gptk-not-installed": "未检测到 GPTK / D3DMetal"
    case "initial-install-disk-low": "剩余空间可能不足"
    case "gatekeeper-disabled": "Gatekeeper 当前关闭"
    default: "兼容性提示"
    }
  }

  private func findingMessage(_ code: String) -> String {
    switch code {
    case "unsupported-macos-version": "首期目标只是 macOS 26 和 27。"
    case "unsupported-architecture": "首期只支持 Apple Silicon Mac。"
    case "metal-unavailable": "本机没有可用的 Metal 设备。"
    case "rosetta-missing": "后续的 Wine 运行时可能需要 Rosetta 2。"
    case "gptk-not-installed": "当前仍可继续研究 DXMT 等后端，但还未形成可玩配置。"
    case "initial-install-disk-low": "首次安装规划预留约 200 GB，当前剩余空间低于该阈值。"
    case "gatekeeper-disabled": "这里只报告状态，程序不会修改 Gatekeeper。"
    default: "请根据详细诊断继续确认。"
    }
  }
}

private struct EnvironmentRow: View {
  let label: String
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 22)
      Text(label)
        .font(.headline)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
    .padding(.vertical, 13)
  }
}
