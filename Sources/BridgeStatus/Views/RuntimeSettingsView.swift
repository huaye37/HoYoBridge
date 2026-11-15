import SwiftUI

struct RuntimeSettingsView: View {
  var body: some View {
    Form {
      Section("运行环境") {
        LabeledContent("启动组合", value: "CrossOver 11 + DXMT 0.80")
        LabeledContent("Wine", value: "CrossOver 11.0-1（按需下载并校验）")
        LabeledContent("DXMT", value: "0.80（按需下载并校验）")
        LabeledContent("Steam 兼容组件", value: "YAAGL ca78abc · 必需")
        Text("Steam 兼容入口自动保留，无需安装或登录 Steam 客户端。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("已确认可游玩") {
        LabeledContent("原神 · 国服", value: "7.2.0")
        LabeledContent("崩坏：星穹铁道 · 国服", value: "4.7.0")
        Text("本机玩家于 2026年11月15日确认以上版本可正常游玩，使用 CrossOver 11.0-1 + DXMT 0.80。后续游戏版本和国际服分别验证，安装成功不会自动加入此列表。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("其他客户端") {
        Text("绝区零、崩坏 3 及四款国际服：尚无已确认可游玩的具体版本记录。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("启动辅助") {
        Text("星铁国服的专用启动辅助程序仅在首次安装或辅助程序升级时请求管理员授权，之后启动自动使用。它只处理短暂的启动兼容操作，不保存密码。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}
