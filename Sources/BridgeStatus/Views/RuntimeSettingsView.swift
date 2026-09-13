import SwiftUI

struct RuntimeSettingsView: View {
  var body: some View {
    Form {
      Section("运行环境") {
        LabeledContent("启动组合", value: "CrossOver 11 + DXMT 0.80")
        LabeledContent("Wine", value: "CrossOver 11.0-1（随应用提供）")
        LabeledContent("DXMT", value: "0.80（随应用提供）")
        LabeledContent("Steam 兼容组件", value: "YAAGL ca78abc · 必需")
        Text("Steam 兼容入口自动保留，无需安装或登录 Steam 客户端。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        Text("此组合有国服 7.0.0 的本机启动记录，不代表所有系统和后续游戏版本均已验证。Wine / DXMT 随经过校验的应用包更新。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}
