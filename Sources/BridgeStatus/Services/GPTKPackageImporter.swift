import CryptoKit
import Foundation

enum GPTKPackageImportError: Error, Equatable {
  case invalidPackage
  case mountFailed
  case nestedImageMissing
  case unsupportedVersion
  case signatureRejected
  case unsafeDestination
  case commandFailed
}

enum GPTKRuntimeStore {
  static let manifestName = "manifest.json"

  static func root(
    storageRoot: URL = GameRuntimePaths.userStorageRoot
  ) -> URL {
    storageRoot.appending(path: "Runtimes/GPTK", directoryHint: .isDirectory)
  }

  static func activeRoot(
    storageRoot: URL = GameRuntimePaths.userStorageRoot
  ) -> URL {
    root(storageRoot: storageRoot).appending(path: "active", directoryHint: .isDirectory)
  }

  static func current(
    storageRoot: URL = GameRuntimePaths.userStorageRoot
  ) throws -> ImportedGPTKRuntime {
    let runtimeRoot = activeRoot(storageRoot: storageRoot)
    let manifestURL = runtimeRoot.appending(path: manifestName)
    let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
    let manifest = try JSONDecoder().decode(GPTKRuntimeManifest.self, from: data)
    guard manifest.schemaVersion == 1,
      GPTKPackageImporter.isSafeVersion(manifest.version)
    else {
      throw GPTKPackageImportError.invalidPackage
    }
    let runtime = ImportedGPTKRuntime(
      version: manifest.version,
      root: runtimeRoot,
      d3d11SHA256: manifest.d3d11SHA256,
      frameworkSHA256: manifest.frameworkSHA256
    )
    try GPTKPackageImporter.validateInstalledRuntime(runtime)
    return runtime
  }
}

enum GPTKPackageImporter {
  private struct MountedImage {
    let mountPoint: URL
    let device: String?
  }

  private struct ProcessResult {
    let status: Int32
    let standardOutput: Data
  }

  static func importDMG(
    _ dmg: URL,
    storageRoot: URL = GameRuntimePaths.userStorageRoot
  ) throws -> ImportedGPTKRuntime {
    let values = try dmg.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard dmg.isFileURL,
      dmg.pathExtension.lowercased() == "dmg",
      values.isRegularFile == true,
      let byteSize = values.fileSize,
      byteSize > 0,
      byteSize <= 2_147_483_648
    else {
      throw GPTKPackageImportError.invalidPackage
    }

    try requireSuccess("/usr/bin/hdiutil", ["verify", dmg.path])
    var mounts: [MountedImage] = []
    defer {
      for mount in mounts.reversed() {
        let target = mount.device ?? mount.mountPoint.path
        _ = try? run("/usr/bin/hdiutil", ["detach", "-force", target])
      }
    }

    let outer = try attach(dmg)
    mounts.append(outer)
    var contentRoot = outer.mountPoint
    if !FileManager.default.fileExists(
      atPath: contentRoot.appending(path: "redist/lib").path
    ) {
      let nested = try nestedEvaluationImage(in: outer.mountPoint)
      let inner = try attach(nested)
      mounts.append(inner)
      contentRoot = inner.mountPoint
    }

    return try importRedistLibrary(
      contentRoot.appending(path: "redist/lib", directoryHint: .isDirectory),
      storageRoot: storageRoot,
      signatureValidator: validateAppleSignature
    )
  }

  static func importRedistLibrary(
    _ sourceLibrary: URL,
    storageRoot: URL,
    signatureValidator: (URL) throws -> Void
  ) throws -> ImportedGPTKRuntime {
    let version = try detectedVersion(
      framework: sourceLibrary.appending(
        path: "external/D3DMetal.framework",
        directoryHint: .isDirectory
      )
    )
    guard version.hasPrefix("4."), isSafeVersion(version) else {
      throw GPTKPackageImportError.unsupportedVersion
    }
    try validateLibraryLayout(sourceLibrary)
    try Task.checkCancellation()

    let manager = FileManager.default
    let storeRoot = GPTKRuntimeStore.root(storageRoot: storageRoot)
    try manager.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    let staging = storeRoot.appending(
      path: ".importing-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? manager.removeItem(at: staging) }
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    let stagedLibrary = staging.appending(path: "lib", directoryHint: .isDirectory)
    try manager.copyItem(at: sourceLibrary, to: stagedLibrary)
    try Task.checkCancellation()

    let stagedFramework = stagedLibrary.appending(
      path: "external/D3DMetal.framework",
      directoryHint: .isDirectory
    )
    try removeQuarantine(from: staging)
    try signatureValidator(stagedFramework)
    try validateLibraryLayout(stagedLibrary)

    let d3d11 = stagedLibrary.appending(path: "wine/x86_64-windows/d3d11.dll")
    let frameworkBinary = try frameworkExecutable(in: stagedFramework)
    let manifest = GPTKRuntimeManifest(
      schemaVersion: 1,
      version: version,
      d3d11SHA256: try sha256(d3d11),
      frameworkSHA256: try sha256(frameworkBinary)
    )
    let manifestData = try sortedJSONEncoder().encode(manifest)
    try manifestData.write(
      to: staging.appending(path: GPTKRuntimeStore.manifestName),
      options: .atomic
    )
    try Task.checkCancellation()

    let destination = GPTKRuntimeStore.activeRoot(storageRoot: storageRoot)
    if manager.fileExists(atPath: destination.path) {
      guard
        manager.fileExists(
          atPath: destination.appending(path: GPTKRuntimeStore.manifestName).path
        )
      else {
        throw GPTKPackageImportError.unsafeDestination
      }
      try manager.removeItem(at: destination)
    }
    try manager.moveItem(at: staging, to: destination)
    return try GPTKRuntimeStore.current(storageRoot: storageRoot)
  }

  static func validateInstalledRuntime(_ runtime: ImportedGPTKRuntime) throws {
    try validateLibraryLayout(runtime.libraryRoot)
    let d3d11 = runtime.windowsModules.appending(path: "d3d11.dll")
    let frameworkBinary = try frameworkExecutable(in: runtime.framework)
    guard try sha256(d3d11) == runtime.d3d11SHA256,
      try sha256(frameworkBinary) == runtime.frameworkSHA256
    else {
      throw GPTKPackageImportError.invalidPackage
    }
  }

  static func isSafeVersion(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 64,
      value != ".", value != "..",
      !value.contains("/")
    else { return false }
    return value.utf8.allSatisfy {
      (48...57).contains($0)
        || (65...90).contains($0)
        || (97...122).contains($0)
        || $0 == 45
        || $0 == 46
        || $0 == 95
    }
  }

  static func mountPoint(fromPlist data: Data) -> URL? {
    plistEntities(data).compactMap { $0["mount-point"] as? String }
      .first(where: { !$0.isEmpty })
      .map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  static func device(fromPlist data: Data) -> String? {
    plistEntities(data).compactMap { $0["dev-entry"] as? String }
      .first(where: { !$0.isEmpty })
  }

  private static func plistEntities(_ data: Data) -> [[String: Any]] {
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = plist as? [String: Any],
      let entities = dictionary["system-entities"] as? [[String: Any]]
    else { return [] }
    return entities
  }

  private static func attach(_ dmg: URL) throws -> MountedImage {
    let result = try run(
      "/usr/bin/hdiutil",
      ["attach", "-readonly", "-nobrowse", "-plist", dmg.path]
    )
    guard result.status == 0,
      let mountPoint = mountPoint(fromPlist: result.standardOutput)
    else {
      if let device = device(fromPlist: result.standardOutput) {
        _ = try? run("/usr/bin/hdiutil", ["detach", "-force", device])
      }
      throw GPTKPackageImportError.mountFailed
    }
    return MountedImage(
      mountPoint: mountPoint,
      device: device(fromPlist: result.standardOutput)
    )
  }

  private static func nestedEvaluationImage(in root: URL) throws -> URL {
    let images = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ).filter {
      $0.pathExtension.lowercased() == "dmg"
        && $0.lastPathComponent.localizedCaseInsensitiveContains("Evaluation")
    }
    guard images.count == 1 else {
      throw GPTKPackageImportError.nestedImageMissing
    }
    return images[0]
  }

  private static func detectedVersion(framework: URL) throws -> String {
    let infoCandidates = [
      framework.appending(path: "Resources/Info.plist"),
      framework.appending(path: "Versions/Current/Resources/Info.plist"),
      framework.appending(path: "Contents/Info.plist"),
    ]
    for info in infoCandidates {
      guard let dictionary = NSDictionary(contentsOf: info) else { continue }
      if let version = dictionary["CFBundleShortVersionString"] as? String
        ?? dictionary["CFBundleVersion"] as? String
      {
        return version
      }
    }
    throw GPTKPackageImportError.invalidPackage
  }

  private static func validateLibraryLayout(_ library: URL) throws {
    let manager = FileManager.default
    let windows = library.appending(
      path: "wine/x86_64-windows",
      directoryHint: .isDirectory
    )
    let unix = library.appending(path: "wine/x86_64-unix", directoryHint: .isDirectory)
    let external = library.appending(path: "external", directoryHint: .isDirectory)
    let required = [
      windows.appending(path: "d3d11.dll"),
      windows.appending(path: "dxgi.dll"),
      unix.appending(path: "d3d11.so"),
      unix.appending(path: "dxgi.so"),
      external.appending(path: "libd3dshared.dylib"),
      external.appending(path: "D3DMetal.framework", directoryHint: .isDirectory),
    ]
    guard required.allSatisfy({ manager.fileExists(atPath: $0.path) }) else {
      throw GPTKPackageImportError.invalidPackage
    }
  }

  private static func frameworkExecutable(in framework: URL) throws -> URL {
    let candidates = [
      framework.appending(path: "D3DMetal"),
      framework.appending(path: "Versions/Current/D3DMetal"),
    ]
    guard
      let binary = candidates.first(where: {
        FileManager.default.fileExists(atPath: $0.path)
      })
    else {
      throw GPTKPackageImportError.invalidPackage
    }
    return binary
  }

  private static func validateAppleSignature(_ framework: URL) throws {
    let result = try run(
      "/usr/bin/codesign",
      ["--verify", "--deep", "--strict", framework.path]
    )
    guard result.status == 0 else {
      throw GPTKPackageImportError.signatureRejected
    }
  }

  private static func removeQuarantine(from root: URL) throws {
    let result = try run(
      "/usr/bin/xattr",
      ["-dr", "com.apple.quarantine", root.path]
    )
    guard result.status == 0 else {
      throw GPTKPackageImportError.commandFailed
    }
  }

  private static func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      try Task.checkCancellation()
      digest.update(data: data)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func sortedJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  private static func requireSuccess(_ executable: String, _ arguments: [String]) throws {
    guard try run(executable, arguments).status == 0 else {
      throw GPTKPackageImportError.commandFailed
    }
  }

  private static func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
    try Task.checkCancellation()
    let output = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = [:]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    try Task.checkCancellation()
    return ProcessResult(status: process.terminationStatus, standardOutput: data)
  }
}
