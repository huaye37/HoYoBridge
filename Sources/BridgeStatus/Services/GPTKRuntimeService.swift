import Foundation

@MainActor
final class GPTKRuntimeService: ObservableObject {
  @Published private(set) var state: GPTKRuntimeImportState = .checking

  private var task: Task<Void, Never>?

  init() {
    refresh()
  }

  func refresh() {
    guard task == nil else { return }
    do {
      let runtime = try GPTKRuntimeStore.current()
      state = .ready(version: runtime.version)
    } catch {
      state = .missing
    }
  }

  func importPackage(from dmg: URL) {
    guard task == nil else { return }
    state = .importing
    task = Task { [weak self] in
      guard let self else { return }
      defer { task = nil }
      do {
        let runtime = try await Task.detached(priority: .userInitiated) {
          try GPTKPackageImporter.importDMG(dmg)
        }.value
        state = .ready(version: runtime.version)
      } catch is CancellationError {
        if let runtime = try? GPTKRuntimeStore.current() {
          state = .ready(version: runtime.version)
        } else {
          state = .missing
        }
      } catch {
        state = .failed(LauncherFailureDescription.describe(error))
      }
    }
  }
}
