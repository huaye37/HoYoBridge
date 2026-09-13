import CryptoKit
import Darwin
import Foundation

enum GPTKRuntimePreparationError: Error, Equatable {
  case invalidBaseRuntime
  case invalidGPTKRuntime
  case compatibilityShimMissing
  case compatibilityShimInvalid
  case unsupportedVersionModule
  case copyFailed
  case unsafeDestination
}

enum GPTKRuntimePreparer {
  private static let markerName = ".mgb-gptk4-variant"
  private static let compatibilityShimName = "gptk4-msaa-version.dll"
  private static let compatibilityShimSHA256 =
    "a72a43f5623984a67b70a0c203e0229c97e5ed4e4657eec9c6ff56c6cc2c49f1"

  static func prepare(
    base: GameRuntimePaths,
    imported: ImportedGPTKRuntime,
    storageRoot: URL = GameRuntimePaths.userStorageRoot,
    compatibilityShim suppliedCompatibilityShim: URL? = nil
  ) throws -> GameRuntimePaths {
    guard base.isRuntimeReady else {
      throw GPTKRuntimePreparationError.invalidBaseRuntime
    }
    do {
      try GPTKPackageImporter.validateInstalledRuntime(imported)
    } catch {
      throw GPTKRuntimePreparationError.invalidGPTKRuntime
    }

    let compatibilityShim = try resolveCompatibilityShim(suppliedCompatibilityShim)
    let shimSHA256 = try sha256(compatibilityShim)
    if suppliedCompatibilityShim == nil, shimSHA256 != compatibilityShimSHA256 {
      throw GPTKRuntimePreparationError.compatibilityShimInvalid
    }

    let variantID = "genshin-cn-crossover11-steam-gptk4-\(imported.version)"
    let runtimeTarget = storageRoot.appending(
      path: "Runtimes/\(variantID)",
      directoryHint: .isDirectory
    )
    let prefixTarget = storageRoot.appending(
      path: "Prefixes/\(variantID)",
      directoryHint: .isDirectory
    )
    let marker = markerContents(imported: imported, compatibilityShimSHA256: shimSHA256)
    let result = GameRuntimePaths(
      projectRoot: storageRoot,
      runtimeRoot: runtimeTarget,
      prefix: prefixTarget,
      gameExecutable: base.gameExecutable
    )
    if preparedVariantIsValid(
      result,
      marker: marker,
      compatibilityShimSHA256: shimSHA256
    ) {
      return result
    }

    try Task.checkCancellation()
    let manager = FileManager.default
    try manager.createDirectory(at: storageRoot, withIntermediateDirectories: true)
    let staging = storageRoot.appending(
      path: ".gptk4-preparing-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let stagedRuntime = staging.appending(path: "runtime", directoryHint: .isDirectory)
    let stagedPrefix = staging.appending(path: "prefix", directoryHint: .isDirectory)
    defer { try? manager.removeItem(at: staging) }
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)

    try cloneTree(from: base.runtimeRoot, to: stagedRuntime)
    try cloneTree(from: base.prefix, to: stagedPrefix)
    try overlay(
      imported: imported,
      runtimeRoot: stagedRuntime,
      prefix: stagedPrefix,
      compatibilityShim: compatibilityShim
    )
    try marker.write(
      to: stagedRuntime.appending(path: markerName),
      atomically: true,
      encoding: .utf8
    )
    try marker.write(
      to: stagedPrefix.appending(path: markerName),
      atomically: true,
      encoding: .utf8
    )
    try Task.checkCancellation()

    try publishManaged(stagedRuntime, to: runtimeTarget)
    try publishManaged(stagedPrefix, to: prefixTarget)
    guard result.isRuntimeReady else {
      throw GPTKRuntimePreparationError.copyFailed
    }
    return result
  }

  static func launchEnvironmentEntries(paths: GameRuntimePaths) -> [String: String] {
    let external = paths.runtimeRoot.appending(
      path: "wine/lib/external",
      directoryHint: .isDirectory
    )
    return [
      "WINEDLLOVERRIDES":
        "version=n;versi0n=b;d3d9,d3d10,d3d10_1,d3d10core,d3d11,d3d12,d3d12core,dxgi,nvapi64,nvngx=b;winemetal=",
      "DYLD_FALLBACK_LIBRARY_PATH": external.path,
      "DYLD_FALLBACK_FRAMEWORK_PATH": external.path,
      "MGB_GPTK_MSAA_SHIM": "1",
    ]
  }

  private static func overlay(
    imported: ImportedGPTKRuntime,
    runtimeRoot: URL,
    prefix: URL,
    compatibilityShim: URL
  ) throws {
    let manager = FileManager.default
    let wineRoot = runtimeRoot.appending(path: "wine", directoryHint: .isDirectory)
    let destinationWindows = wineRoot.appending(
      path: "lib/wine/x86_64-windows",
      directoryHint: .isDirectory
    )
    let destinationUnix = wineRoot.appending(
      path: "lib/wine/x86_64-unix",
      directoryHint: .isDirectory
    )
    let destinationExternal = wineRoot.appending(
      path: "lib/external",
      directoryHint: .isDirectory
    )
    try manager.createDirectory(at: destinationWindows, withIntermediateDirectories: true)
    try manager.createDirectory(at: destinationUnix, withIntermediateDirectories: true)
    try manager.createDirectory(at: destinationExternal, withIntermediateDirectories: true)

    let modules = try manager.contentsOfDirectory(
      at: imported.windowsModules,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ).filter { isGPTKModule($0.lastPathComponent) }
    guard modules.contains(where: { $0.lastPathComponent == "d3d11.dll" }),
      modules.contains(where: { $0.lastPathComponent == "dxgi.dll" })
    else {
      throw GPTKRuntimePreparationError.invalidGPTKRuntime
    }

    for module in modules {
      try replace(module, at: destinationWindows.appending(path: module.lastPathComponent))
      let stem = module.deletingPathExtension().lastPathComponent
      let unixModule = imported.unixModules.appending(path: "\(stem).so")
      if manager.fileExists(atPath: unixModule.path)
        || (try? manager.destinationOfSymbolicLink(atPath: unixModule.path)) != nil
      {
        try replace(unixModule, at: destinationUnix.appending(path: "\(stem).so"))
      }
    }

    for item in try manager.contentsOfDirectory(
      at: imported.externalLibraries,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) {
      try replace(item, at: destinationExternal.appending(path: item.lastPathComponent))
    }

    let frameworkLink = destinationUnix.appending(
      path: "D3DMetal.framework",
      directoryHint: .isDirectory
    )
    if manager.fileExists(atPath: frameworkLink.path)
      || (try? manager.destinationOfSymbolicLink(atPath: frameworkLink.path)) != nil
    {
      try manager.removeItem(at: frameworkLink)
    }
    try manager.createSymbolicLink(
      atPath: frameworkLink.path,
      withDestinationPath: "../../external/D3DMetal.framework"
    )

    try activateNGX(
      windows: destinationWindows,
      unix: destinationUnix,
      prefix: prefix
    )
    try installMSAACompatibilityShim(
      compatibilityShim,
      windows: destinationWindows,
      prefix: prefix
    )
  }

  private static func installMSAACompatibilityShim(
    _ compatibilityShim: URL,
    windows: URL,
    prefix: URL
  ) throws {
    let manager = FileManager.default
    let originalVersion = windows.appending(path: "version.dll")
    guard manager.fileExists(atPath: originalVersion.path) else {
      throw GPTKRuntimePreparationError.unsupportedVersionModule
    }

    var versionData = try Data(contentsOf: originalVersion)
    let originalName = Data("version.dll".utf8)
    let forwardedName = Data("versi0n.dll".utf8)
    guard let match = versionData.range(of: originalName),
      versionData[match.upperBound...].range(of: originalName) == nil
    else {
      throw GPTKRuntimePreparationError.unsupportedVersionModule
    }
    versionData.replaceSubrange(match, with: forwardedName)

    let forwardedVersion = windows.appending(path: "versi0n.dll")
    try versionData.write(to: forwardedVersion, options: .atomic)

    let system32 = prefix.appending(
      path: "drive_c/windows/system32",
      directoryHint: .isDirectory
    )
    try manager.createDirectory(at: system32, withIntermediateDirectories: true)
    try replace(
      forwardedVersion,
      at: system32.appending(path: "versi0n.dll")
    )
    try replace(
      compatibilityShim,
      at: system32.appending(path: "version.dll")
    )
  }

  private static func resolveCompatibilityShim(_ supplied: URL?) throws -> URL {
    if let supplied { return supplied }
    guard let resources = Bundle.main.resourceURL else {
      throw GPTKRuntimePreparationError.compatibilityShimMissing
    }
    let bundled = resources.appending(
      path: "RuntimeAssets/\(compatibilityShimName)"
    )
    guard FileManager.default.fileExists(atPath: bundled.path) else {
      throw GPTKRuntimePreparationError.compatibilityShimMissing
    }
    return bundled
  }

  private static func activateNGX(windows: URL, unix: URL, prefix: URL) throws {
    let manager = FileManager.default
    for (directory, extensionName) in [(windows, "dll"), (unix, "so")] {
      let source = directory.appending(path: "nvngx-on-metalfx.\(extensionName)")
      guard
        manager.fileExists(atPath: source.path)
          || (try? manager.destinationOfSymbolicLink(atPath: source.path)) != nil
      else { continue }
      try replace(source, at: directory.appending(path: "nvngx.\(extensionName)"))
    }

    let system32 = prefix.appending(
      path: "drive_c/windows/system32",
      directoryHint: .isDirectory
    )
    try manager.createDirectory(at: system32, withIntermediateDirectories: true)
    let seeds = [
      ("nvapi64.dll", "nvapi64.dll"),
      ("nvngx-on-metalfx.dll", "nvngx.dll"),
    ]
    for (sourceName, destinationName) in seeds {
      let source = windows.appending(path: sourceName)
      guard manager.fileExists(atPath: source.path) else { continue }
      try replace(source, at: system32.appending(path: destinationName))
    }
  }

  private static func isGPTKModule(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    guard lowercased.hasSuffix(".dll") else { return false }
    return ["d3d", "dxgi", "nv"].contains { lowercased.hasPrefix($0) }
  }

  private static func replace(_ source: URL, at destination: URL) throws {
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.path)
      || (try? manager.destinationOfSymbolicLink(atPath: destination.path)) != nil
    {
      try manager.removeItem(at: destination)
    }
    if let target = try? manager.destinationOfSymbolicLink(atPath: source.path) {
      try manager.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
    } else {
      try manager.copyItem(at: source, to: destination)
    }
  }

  private static func cloneTree(from source: URL, to destination: URL) throws {
    let result = source.path.withCString { sourcePath in
      destination.path.withCString { destinationPath in
        clonefile(sourcePath, destinationPath, 0)
      }
    }
    if result == 0 { return }
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      throw GPTKRuntimePreparationError.copyFailed
    }
  }

  private static func publishManaged(_ source: URL, to destination: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if manager.fileExists(atPath: destination.path) {
      guard manager.fileExists(atPath: destination.appending(path: markerName).path) else {
        throw GPTKRuntimePreparationError.unsafeDestination
      }
      try manager.removeItem(at: destination)
    }
    try manager.moveItem(at: source, to: destination)
  }

  private static func markerContents(
    imported: ImportedGPTKRuntime,
    compatibilityShimSHA256: String
  ) -> String {
    "schema=3\nprofile=genshin-cn-gptk4-v3\nversion=\(imported.version)\nd3d11SHA256=\(imported.d3d11SHA256)\nframeworkSHA256=\(imported.frameworkSHA256)\ncompatibilityShimSHA256=\(compatibilityShimSHA256)\n"
  }

  private static func hasMarker(_ marker: String, at root: URL) -> Bool {
    (try? String(contentsOf: root.appending(path: markerName), encoding: .utf8)) == marker
  }

  private static func preparedVariantIsValid(
    _ paths: GameRuntimePaths,
    marker: String,
    compatibilityShimSHA256: String
  ) -> Bool {
    guard paths.isRuntimeReady,
      hasMarker(marker, at: paths.runtimeRoot),
      hasMarker(marker, at: paths.prefix)
    else { return false }

    let system32 = paths.prefix.appending(
      path: "drive_c/windows/system32",
      directoryHint: .isDirectory
    )
    let runtimeForwarder = paths.runtimeRoot.appending(
      path: "wine/lib/wine/x86_64-windows/versi0n.dll"
    )
    let prefixForwarder = system32.appending(path: "versi0n.dll")
    guard
      (try? sha256(system32.appending(path: "version.dll")))
        == compatibilityShimSHA256,
      let runtimeSHA256 = try? sha256(runtimeForwarder),
      let prefixSHA256 = try? sha256(prefixForwarder)
    else { return false }
    return runtimeSHA256 == prefixSHA256
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
}
