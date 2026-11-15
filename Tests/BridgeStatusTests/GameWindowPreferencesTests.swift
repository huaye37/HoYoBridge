import Foundation
import Testing
@testable import BridgeStatus

struct GameWindowPreferencesTests {
  @Test func starRailLaunchOverridesOnlyItsDisplayRecord() throws {
    let commands = try GameWindowPreferences.commands(game: .starRail, resolution: .init(width: 5120, height: 2880))
    let special = try #require(commands.first { $0.contains("GraphicsSettings_PCResolution_h431323223") })
    let index = try #require(special.firstIndex(of: "/d"))
    let hex = Array(special[index+1])
    let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(String(hex[$0..<$0+2]), radix: 16) }
    let json = try #require(JSONSerialization.jsonObject(with: Data(bytes.dropLast())) as? [String: Any])
    #expect(json["width"] as? Int == 5120)
    #expect(json["height"] as? Int == 2880)
    #expect(json["isFullScreen"] as? Bool == false)
    #expect(!commands.joined().contains("GraphicsSettings_Model_h2986158309"))
    #expect(!commands.joined().contains("GENERAL_DATA_h2389025596"))
  }

  @Test func eachClientHasItsOwnDisplayRegistryKeyAndUsesWindowedUnityMode() throws {
    #expect(Set(MiHoYoGame.allCases.map { GameWindowPreferences.registryPath(for: $0) }).count == 8)
    for game in MiHoYoGame.allCases {
      let commands = try GameWindowPreferences.commands(game: game, resolution: .init(width: 3024, height: 1964))
      let fullscreen = try #require(commands.first { $0.contains("Screenmanager Fullscreen mode_h3630240806") })
      #expect(fullscreen.contains("3"))
      #expect(commands.allSatisfy { $0[2] == GameWindowPreferences.registryPath(for: game) })
    }
  }

  @Test func catalogIncludesNotebookAndUltrawideSizes() {
    let values = Set(GameResolutionCatalog.available.map(\.resolution.rawValue))
    for size in ["2560x1600", "3024x1964", "3024x1890", "2704x1756", "3456x2234", "3440x1440", "5120x2880"] {
      #expect(values.contains(size))
    }
    #expect(GameResolution(rawValue: "4500x2500") != nil)
  }
}
