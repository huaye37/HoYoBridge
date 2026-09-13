import Darwin
import Foundation
import Metal

public struct SystemProbe: Sendable {
  private let commandRunner: any CommandRunning

  public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
    self.commandRunner = commandRunner
  }

  public func capture() -> CapabilityReport {
    let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    let version = [
      operatingSystemVersion.majorVersion,
      operatingSystemVersion.minorVersion,
      operatingSystemVersion.patchVersion,
    ].map(String.init).joined(separator: ".")

    var report = CapabilityReport(
      macOSVersion: version,
      architecture: Self.machineArchitecture(),
      hardwareModel: Self.sysctlString("hw.model"),
      physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
      freeDiskBytes: Self.freeDiskBytes(),
      metal: Self.metalCapabilities(),
      rosetta: detectRosetta(),
      xcode: detectXcode(),
      gptk: GPTKDetector.detect(),
      gatekeeper: detectGatekeeper()
    )
    report.findings = CapabilityAnalyzer.findings(for: report)
    return report
  }

  private func detectRosetta() -> ComponentStatus {
    guard
      let result = try? commandRunner.run(
        "/usr/sbin/pkgutil",
        arguments: ["--pkg-info", "com.apple.pkg.RosettaUpdateAuto"]
      )
    else {
      return .init(availability: .unknown, detail: "Unable to query Rosetta package information.")
    }

    guard result.exitCode == 0 else {
      return .init(availability: .missing, detail: result.standardError)
    }

    let versionLine = result.standardOutput
      .split(separator: "\n")
      .first { $0.hasPrefix("version:") }
    let version = versionLine.map {
      String($0.dropFirst("version:".count)).trimmingCharacters(in: .whitespaces)
    }
    return .init(
      availability: .installed, version: version, detail: "Rosetta package is installed.")
  }

  private func detectXcode() -> ComponentStatus {
    guard let result = try? commandRunner.run("/usr/bin/xcodebuild", arguments: ["-version"]) else {
      return .init(availability: .unknown, detail: "Unable to execute xcodebuild.")
    }
    guard result.exitCode == 0 else {
      return .init(availability: .missing, detail: result.standardError)
    }

    let version = result.standardOutput
      .split(separator: "\n")
      .first
      .map(String.init)
    return .init(availability: .installed, version: version, detail: result.standardOutput)
  }

  private func detectGatekeeper() -> ComponentStatus {
    guard let result = try? commandRunner.run("/usr/sbin/spctl", arguments: ["--status"]) else {
      return .init(availability: .unknown, detail: "Unable to query Gatekeeper status.")
    }
    let detail = [result.standardOutput, result.standardError]
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return .init(availability: .installed, detail: detail)
  }

  private static func machineArchitecture() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func freeDiskBytes() -> UInt64? {
    guard
      let value = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[
        .systemFreeSize] as? NSNumber
    else {
      return nil
    }
    return value.uint64Value
  }

  private static func metalCapabilities() -> MetalCapabilities {
    guard let device = MTLCreateSystemDefaultDevice() else {
      return .init(available: false)
    }

    var families: [String] = []
    if device.supportsFamily(.apple7) { families.append("apple7") }
    if device.supportsFamily(.apple8) { families.append("apple8") }
    if device.supportsFamily(.apple9) { families.append("apple9") }
    if #available(macOS 26.0, *), device.supportsFamily(.apple10) { families.append("apple10") }
    if device.supportsFamily(.mac2) { families.append("mac2") }

    return .init(
      available: true,
      deviceName: device.name,
      registryID: device.registryID,
      supportedFamilies: families,
      recommendedMaxWorkingSetBytes: device.recommendedMaxWorkingSetSize
    )
  }
}
