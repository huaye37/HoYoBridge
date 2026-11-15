import SwiftUI

struct GameClientSwitcher: View {
  @Binding var selection: MiHoYoGame
  @State private var hovering = false

  var body: some View {
    Menu {
      Picker("客户端版本", selection: $selection) {
        ForEach(GameClientRegion.allCases) { region in
          let client = selection.client(in: region)
          Text(client.regionDescription + (OfficialGameInstaller.pendingOperation(for: client) != nil
            ? " · 下载未完成" : client.executableURL != nil ? " · 已安装" : ""))
            .tag(client)
        }
      }
    } label: {
      Text(selection.regionDescription + "  ⌄")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(.white.opacity(0.9))
    .fixedSize()
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.black.opacity(hovering ? 0.32 : 0.20), in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.28 : 0.14), lineWidth: 0.5))
    .onHover { hovering = $0 }
    .accessibilityLabel("客户端版本：\(selection.regionDescription)")
    .help("切换国服或国际服，分别管理安装和下载")
  }
}
