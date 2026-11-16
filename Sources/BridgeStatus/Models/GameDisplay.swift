import AppKit
import CoreGraphics

struct GameDisplay: Identifiable, Equatable, Sendable {
  let id: String
  let displayID: CGDirectDisplayID
  let name: String
  let isBuiltIn: Bool
  let isPortrait: Bool

  var title: String {
    "\(name) · \(isBuiltIn ? "内建屏幕" : "外接屏幕")\(isPortrait ? " · 竖屏（不用于游戏）" : "")"
  }
}

enum GameDisplayCatalog {
  static let preferenceKey = "launcher.targetDisplayUUID"

  @MainActor static var connected: [GameDisplay] {
    NSScreen.screens.compactMap { screen in
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
        let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
        let id = CFUUIDCreateString(nil, uuid) as String? else { return nil }
      return GameDisplay(id: id, displayID: number.uint32Value, name: screen.localizedName,
        isBuiltIn: CGDisplayIsBuiltin(number.uint32Value) != 0,
        isPortrait: screen.frame.height > screen.frame.width)
    }
  }

  static func selected(in displays: [GameDisplay], preferredID: String) -> GameDisplay? {
    displays.first { $0.id == preferredID && !$0.isPortrait }
      ?? displays.first { !$0.isPortrait }
  }
}
