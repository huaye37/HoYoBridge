import AppKit
import SwiftUI
import Testing
@testable import BridgeStatus

@MainActor
struct GameClientLayoutTests {
  @Test func rendersRegionalSelectorOffscreenWhenRequested() async throws {
    guard let path = ProcessInfo.processInfo.environment["MGB_TEST_LAYOUT_OUTPUT"] else { return }
    let output = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, width, height) in [("regular", 960, 640), ("compact", 720, 560)] {
      let view = NSHostingView(rootView: ContentView(miHoYoLauncher: MiHoYoGameLaunchService(), initialGame: .honkaiImpact3Global)
        .frame(width: CGFloat(width), height: CGFloat(height)))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = view
      // Never order the test window onscreen or change the user's active application.
      try await Task.sleep(for: .milliseconds(250))
      view.layoutSubtreeIfNeeded()
      let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      try data.write(to: output.appending(path: "\(name).png"))
      window.close()
    }
  }
}
