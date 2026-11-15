import Foundation
import Testing
@testable import BridgeStatus

@MainActor
struct DownloadWhilePlayingTests {
  @Test(arguments: MiHoYoGame.allCases)
  func maintenanceBlocksOnlyItsOwnClient(game: MiHoYoGame) throws {
    let name = "ConcurrentDownload.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let service = OfficialGameInstaller(region: game.region, storageRoot: root, defaults: defaults)
    for operation in ["install", "update", "repair"] {
      defaults.set(root.appending(path: "Game").path, forKey: "games.\(game.rawValue).pendingInstall")
      defaults.set(operation, forKey: "games.\(game.rawValue).pendingOperation")
      #expect(service.isOccupied)
      for candidate in MiHoYoGame.allCases {
        #expect(service.blocksLaunch(for: candidate) == (candidate == game))
      }
    }
    defaults.set(true, forKey: "games.\(game.rawValue).taskDetached")
    #expect(!service.isOccupied)
    #expect(service.blocksLaunch(for: game))
    defaults.removeObject(forKey: "games.\(game.rawValue).pendingInstall")
    #expect(!service.blocksLaunch(for: game))
    defaults.set(root.appending(path: "Game").path, forKey: "games.\(game.rawValue).pendingUninstall")
    #expect(service.blocksLaunch(for: game))
    #expect(!service.blocksLaunch(for: game.client(in: game.region == .china ? .global : .china)))
  }
}
