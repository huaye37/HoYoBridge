import Foundation
import Testing

@testable import BridgeStatus

@Suite("GPTK 4 runtime")
struct GPTKRuntimeTests {
  @Test("imports a GPTK 4 redist into the managed store")
  func importsRedist() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let redist = try makeRedist(at: root, version: "4.0b2")

    let imported = try GPTKPackageImporter.importRedistLibrary(
      redist,
      storageRoot: root,
      signatureValidator: { _ in }
    )

    #expect(imported.version == "4.0b2")
    #expect(
      try String(
        contentsOf: imported.windowsModules.appending(path: "d3d11.dll"),
        encoding: .utf8
      ) == "gptk-d3d11")
    #expect(try GPTKRuntimeStore.current(storageRoot: root) == imported)
    #expect(imported.d3d11SHA256.count == 64)
    #expect(imported.frameworkSHA256.count == 64)

    try Data("tampered".utf8).write(to: imported.windowsModules.appending(path: "d3d11.dll"))
    #expect(throws: GPTKPackageImportError.invalidPackage) {
      try GPTKRuntimeStore.current(storageRoot: root)
    }
  }

  @Test("prepares an isolated GPTK runtime and leaves DXMT untouched")
  func preparesIsolatedVariant() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let imported = try GPTKPackageImporter.importRedistLibrary(
      makeRedist(at: root, version: "4.0b2"),
      storageRoot: root,
      signatureValidator: { _ in }
    )
    let base = try makeBaseRuntime(at: root)
    let compatibilityShim = root.appending(path: "gptk4-msaa-version.dll")
    try Data("test-compatibility-shim".utf8).write(to: compatibilityShim)

    let variant = try GPTKRuntimePreparer.prepare(
      base: base,
      imported: imported,
      storageRoot: root,
      compatibilityShim: compatibilityShim
    )

    #expect(variant.runtimeRoot != base.runtimeRoot)
    #expect(variant.prefix != base.prefix)
    #expect(
      try String(
        contentsOf: base.runtimeRoot.appending(
          path: "wine/lib/wine/x86_64-windows/d3d11.dll"
        ),
        encoding: .utf8
      )
        == "dxmt-d3d11")
    #expect(
      try String(
        contentsOf: variant.runtimeRoot.appending(
          path: "wine/lib/wine/x86_64-windows/d3d11.dll"
        ),
        encoding: .utf8
      )
        == "gptk-d3d11")
    #expect(
      try FileManager.default.destinationOfSymbolicLink(
        atPath: variant.runtimeRoot.appending(path: "wine/lib/wine/x86_64-unix/d3d11.so").path
      ) == "../../external/libd3dshared.dylib")
    #expect(
      try FileManager.default.destinationOfSymbolicLink(
        atPath: variant.runtimeRoot.appending(
          path: "wine/lib/wine/x86_64-unix/D3DMetal.framework"
        ).path
      ) == "../../external/D3DMetal.framework")
    #expect(variant.isRuntimeReady)
    let environment = GPTKRuntimePreparer.launchEnvironmentEntries(paths: variant)
    #expect(environment["WINEDLLOVERRIDES"]?.contains("d3d11") == true)
    #expect(environment["WINEDLLOVERRIDES"]?.contains("winemetal=") == true)
    #expect(
      environment["DYLD_FALLBACK_FRAMEWORK_PATH"]
        == variant.runtimeRoot.appending(path: "wine/lib/external").path)
    #expect(environment["WINEDLLOVERRIDES"]?.hasPrefix("version=n;versi0n=b;") == true)
    #expect(environment["MGB_GPTK_MSAA_SHIM"] == "1")

    let forwardedVersion = variant.runtimeRoot.appending(
      path: "wine/lib/wine/x86_64-windows/versi0n.dll"
    )
    let forwardedData = try Data(contentsOf: forwardedVersion)
    #expect(forwardedData.range(of: Data("versi0n.dll".utf8)) != nil)
    #expect(forwardedData.range(of: Data("version.dll".utf8)) == nil)
    #expect(
      try Data(
        contentsOf: variant.prefix.appending(
          path: "drive_c/windows/system32/versi0n.dll"
        )
      ) == forwardedData)
    #expect(
      try Data(
        contentsOf: variant.prefix.appending(
          path: "drive_c/windows/system32/version.dll"
        )
      ) == Data("test-compatibility-shim".utf8))

    let preparedAgain = try GPTKRuntimePreparer.prepare(
      base: base,
      imported: imported,
      storageRoot: root,
      compatibilityShim: compatibilityShim
    )
    #expect(preparedAgain == variant)

    try Data("tampered".utf8).write(
      to: variant.prefix.appending(path: "drive_c/windows/system32/version.dll")
    )
    let repaired = try GPTKRuntimePreparer.prepare(
      base: base,
      imported: imported,
      storageRoot: root,
      compatibilityShim: compatibilityShim
    )
    #expect(repaired == variant)
    #expect(
      try Data(
        contentsOf: repaired.prefix.appending(
          path: "drive_c/windows/system32/version.dll"
        )
      ) == Data("test-compatibility-shim".utf8))
  }

  @Test("installs the FPS shim into a DXMT prefix without changing its runtime")
  func installsFPSShimForDXMT() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try makeBaseRuntime(at: root)
    let shim = root.appending(path: "fps-version.dll")
    try Data("fps-shim".utf8).write(to: shim)

    try GenshinFPSUnlock.prepareDXMTPrefix(
      paths: paths,
      compatibilityShim: shim
    )

    let system32 = paths.prefix.appending(path: "drive_c/windows/system32")
    #expect(
      try Data(contentsOf: system32.appending(path: "version.dll"))
        == Data("fps-shim".utf8))
    let forwarded = try Data(contentsOf: system32.appending(path: "versi0n.dll"))
    #expect(forwarded.range(of: Data("versi0n.dll".utf8)) != nil)
    #expect(forwarded.range(of: Data("version.dll".utf8)) == nil)
    #expect(
      try Data(
        contentsOf: paths.runtimeRoot.appending(
          path: "wine/lib/wine/x86_64-windows/version.dll"
        )
      ) == Data("header-version.dll-footer".utf8))
  }

  @Test("parses only known FPS shim statuses")
  func parsesFPSUnlockStatus() {
    #expect(GenshinFPSUnlockStatus(contents: "scanning\n") == .scanning)
    #expect(GenshinFPSUnlockStatus(contents: "active:120") == .active(120))
    #expect(GenshinFPSUnlockStatus(contents: "active:144") == .active(144))
    #expect(GenshinFPSUnlockStatus(contents: "failed:pattern") == .failed)
    #expect(GenshinFPSUnlockStatus(contents: "active:1000") == nil)
  }

  @Test("rejects non GPTK 4 layouts and unsafe versions")
  func rejectsInvalidPackages() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = try makeRedist(at: root, version: "3.0")
    #expect(throws: GPTKPackageImportError.unsupportedVersion) {
      try GPTKPackageImporter.importRedistLibrary(
        old,
        storageRoot: root.appending(path: "old-store"),
        signatureValidator: { _ in }
      )
    }
    #expect(!GPTKPackageImporter.isSafeVersion("../4.0b2"))
    #expect(!GPTKPackageImporter.isSafeVersion("4.0 beta 2"))
    #expect(!GPTKPackageImporter.isSafeVersion("4.0测试"))
  }

  @Test("parses hdiutil plist without accepting arbitrary text")
  func parsesMountPlist() throws {
    let plist: [String: Any] = [
      "system-entities": [
        ["dev-entry": "/dev/disk9"],
        ["dev-entry": "/dev/disk9s1", "mount-point": "/Volumes/GPTK"],
      ]
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    #expect(GPTKPackageImporter.mountPoint(fromPlist: data)?.path == "/Volumes/GPTK")
    #expect(GPTKPackageImporter.device(fromPlist: data) == "/dev/disk9")
    #expect(GPTKPackageImporter.mountPoint(fromPlist: Data("canary".utf8)) == nil)
  }

  private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "MacGameBridge-GPTKTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func makeRedist(at root: URL, version: String) throws -> URL {
    let redist = root.appending(
      path: "redist-\(UUID().uuidString)/lib",
      directoryHint: .isDirectory
    )
    let windows = redist.appending(path: "wine/x86_64-windows", directoryHint: .isDirectory)
    let unix = redist.appending(path: "wine/x86_64-unix", directoryHint: .isDirectory)
    let external = redist.appending(path: "external", directoryHint: .isDirectory)
    let framework = external.appending(
      path: "D3DMetal.framework/Versions/A",
      directoryHint: .isDirectory
    )
    for directory in [windows, unix, external, framework.appending(path: "Resources")] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    try Data("gptk-d3d11".utf8).write(to: windows.appending(path: "d3d11.dll"))
    try Data("gptk-dxgi".utf8).write(to: windows.appending(path: "dxgi.dll"))
    try Data("gptk-d3d12".utf8).write(to: windows.appending(path: "d3d12.dll"))
    try FileManager.default.createSymbolicLink(
      atPath: unix.appending(path: "d3d11.so").path,
      withDestinationPath: "../../external/libd3dshared.dylib"
    )
    try FileManager.default.createSymbolicLink(
      atPath: unix.appending(path: "dxgi.so").path,
      withDestinationPath: "../../external/libd3dshared.dylib"
    )
    try Data("shared".utf8).write(to: external.appending(path: "libd3dshared.dylib"))
    try Data("framework-binary".utf8).write(to: framework.appending(path: "D3DMetal"))
    let info: [String: Any] = [
      "CFBundleExecutable": "D3DMetal",
      "CFBundleIdentifier": "com.apple.D3DMetal",
      "CFBundleShortVersionString": version,
    ]
    let infoData = try PropertyListSerialization.data(
      fromPropertyList: info,
      format: .xml,
      options: 0
    )
    try infoData.write(to: framework.appending(path: "Resources/Info.plist"))
    let frameworkRoot = external.appending(path: "D3DMetal.framework")
    try FileManager.default.createSymbolicLink(
      atPath: frameworkRoot.appending(path: "Versions/Current").path,
      withDestinationPath: "A"
    )
    try FileManager.default.createSymbolicLink(
      atPath: frameworkRoot.appending(path: "D3DMetal").path,
      withDestinationPath: "Versions/Current/D3DMetal"
    )
    try FileManager.default.createSymbolicLink(
      atPath: frameworkRoot.appending(path: "Resources").path,
      withDestinationPath: "Versions/Current/Resources"
    )
    return redist
  }

  private func makeBaseRuntime(at root: URL) throws -> GameRuntimePaths {
    let runtime = root.appending(path: "base-runtime", directoryHint: .isDirectory)
    let prefix = root.appending(path: "base-prefix", directoryHint: .isDirectory)
    let windows = runtime.appending(
      path: "wine/lib/wine/x86_64-windows",
      directoryHint: .isDirectory
    )
    let unix = runtime.appending(
      path: "wine/lib/wine/x86_64-unix",
      directoryHint: .isDirectory
    )
    for directory in [runtime.appending(path: "wine/bin"), windows, unix, prefix] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    for executable in ["wine", "wineserver"] {
      let url = runtime.appending(path: "wine/bin/\(executable)")
      try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    try Data("dxmt-d3d11".utf8).write(to: windows.appending(path: "d3d11.dll"))
    try Data("header-version.dll-footer".utf8).write(
      to: windows.appending(path: "version.dll")
    )
    try Data("base-prefix".utf8).write(to: prefix.appending(path: "state"))
    return GameRuntimePaths(
      projectRoot: root,
      runtimeRoot: runtime,
      prefix: prefix,
      gameExecutable: root.appending(path: "YuanShen.exe")
    )
  }
}
