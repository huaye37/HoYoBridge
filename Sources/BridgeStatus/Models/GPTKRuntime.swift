import Foundation

struct ImportedGPTKRuntime: Equatable, Sendable {
  let version: String
  let root: URL
  let d3d11SHA256: String
  let frameworkSHA256: String

  var libraryRoot: URL { root.appending(path: "lib", directoryHint: .isDirectory) }
  var windowsModules: URL {
    libraryRoot.appending(path: "wine/x86_64-windows", directoryHint: .isDirectory)
  }
  var unixModules: URL {
    libraryRoot.appending(path: "wine/x86_64-unix", directoryHint: .isDirectory)
  }
  var externalLibraries: URL {
    libraryRoot.appending(path: "external", directoryHint: .isDirectory)
  }
  var framework: URL {
    externalLibraries.appending(path: "D3DMetal.framework", directoryHint: .isDirectory)
  }
}

enum GPTKRuntimeImportState: Equatable {
  case checking
  case missing
  case importing
  case ready(version: String)
  case failed(String)

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }
}

struct GPTKRuntimeManifest: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let version: String
  let d3d11SHA256: String
  let frameworkSHA256: String
}
