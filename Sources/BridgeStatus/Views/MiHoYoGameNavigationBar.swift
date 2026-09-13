import AppKit
import SwiftUI

@MainActor
struct MiHoYoGameNavigationBar: NSViewRepresentable {
  @Binding var selection: MiHoYoGame

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  func makeNSView(context: Context) -> NSView {
    let container = NSView()
    container.wantsLayer = true

    let gameStack = NSStackView()
    gameStack.orientation = .horizontal
    gameStack.alignment = .centerY
    gameStack.spacing = 4
    gameStack.distribution = .fillEqually

    for game in MiHoYoGame.allCases {
      let button = FirstMouseNavigationButton(
        title: game.sidebarTitle,
        target: context.coordinator,
        action: #selector(Coordinator.selectGame(_:))
      )
      button.identifier = NSUserInterfaceItemIdentifier(game.rawValue)
      button.font = .systemFont(ofSize: 14, weight: .medium)
      button.isBordered = false
      button.focusRingType = .none
      button.wantsLayer = true
      button.layer?.cornerRadius = 6
      button.layer?.cornerCurve = .continuous
      button.translatesAutoresizingMaskIntoConstraints = false
      button.widthAnchor.constraint(equalToConstant: 100).isActive = true
      button.heightAnchor.constraint(equalToConstant: 36).isActive = true
      button.toolTip = game.title
      button.setAccessibilityLabel(game.title)
      gameStack.addArrangedSubview(button)
      context.coordinator.buttons[game] = button
    }

    let content = NSStackView(views: [gameStack])
    content.orientation = .horizontal
    content.alignment = .centerY
    content.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      content.topAnchor.constraint(equalTo: container.topAnchor),
      content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    context.coordinator.updateSelection(selection)
    return container
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.selection = $selection
    context.coordinator.updateSelection(selection)
  }

  @MainActor
  final class Coordinator: NSObject {
    var selection: Binding<MiHoYoGame>
    var buttons: [MiHoYoGame: NSButton] = [:]

    init(selection: Binding<MiHoYoGame>) {
      self.selection = selection
    }

    @objc func selectGame(_ sender: NSButton) {
      guard let rawValue = sender.identifier?.rawValue,
        let game = MiHoYoGame(rawValue: rawValue)
      else { return }
      selection.wrappedValue = game
      updateSelection(game)
    }

    func updateSelection(_ selectedGame: MiHoYoGame) {
      for (game, button) in buttons {
        let selected = game == selectedGame
        button.layer?.backgroundColor = selected
          ? NSColor.white.withAlphaComponent(0.13).cgColor
          : NSColor.clear.cgColor
        button.contentTintColor = selected ? .white : NSColor.white.withAlphaComponent(0.72)
      }
    }
  }
}

@MainActor
private final class FirstMouseNavigationButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
