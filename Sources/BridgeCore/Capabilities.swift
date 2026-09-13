import Foundation

public enum ComponentAvailability: String, Codable, Sendable {
  case installed
  case missing
  case unknown
}

public struct ComponentStatus: Codable, Equatable, Sendable {
  public let availability: ComponentAvailability
  public let version: String?
  public let path: String?
  public let detail: String?

  public init(
    availability: ComponentAvailability,
    version: String? = nil,
    path: String? = nil,
    detail: String? = nil
  ) {
    self.availability = availability
    self.version = version
    self.path = path
    self.detail = detail
  }
}

public struct MetalCapabilities: Codable, Equatable, Sendable {
  public let available: Bool
  public let deviceName: String?
  public let registryID: UInt64?
  public let supportedFamilies: [String]
  public let recommendedMaxWorkingSetBytes: UInt64?

  public init(
    available: Bool,
    deviceName: String? = nil,
    registryID: UInt64? = nil,
    supportedFamilies: [String] = [],
    recommendedMaxWorkingSetBytes: UInt64? = nil
  ) {
    self.available = available
    self.deviceName = deviceName
    self.registryID = registryID
    self.supportedFamilies = supportedFamilies
    self.recommendedMaxWorkingSetBytes = recommendedMaxWorkingSetBytes
  }
}

public enum FindingSeverity: String, Codable, Sendable {
  case info
  case warning
  case blocker
}

public struct DiagnosticFinding: Codable, Equatable, Sendable {
  public let severity: FindingSeverity
  public let code: String
  public let message: String

  public init(severity: FindingSeverity, code: String, message: String) {
    self.severity = severity
    self.code = code
    self.message = message
  }
}

public struct CapabilityReport: Codable, Equatable, Sendable {
  public let generatedAt: Date
  public let macOSVersion: String
  public let architecture: String
  public let hardwareModel: String?
  public let physicalMemoryBytes: UInt64
  public let freeDiskBytes: UInt64?
  public let metal: MetalCapabilities
  public let rosetta: ComponentStatus
  public let xcode: ComponentStatus
  public let gptk: ComponentStatus
  public let gatekeeper: ComponentStatus
  public var findings: [DiagnosticFinding]

  public init(
    generatedAt: Date = Date(),
    macOSVersion: String,
    architecture: String,
    hardwareModel: String? = nil,
    physicalMemoryBytes: UInt64,
    freeDiskBytes: UInt64? = nil,
    metal: MetalCapabilities,
    rosetta: ComponentStatus,
    xcode: ComponentStatus,
    gptk: ComponentStatus,
    gatekeeper: ComponentStatus,
    findings: [DiagnosticFinding] = []
  ) {
    self.generatedAt = generatedAt
    self.macOSVersion = macOSVersion
    self.architecture = architecture
    self.hardwareModel = hardwareModel
    self.physicalMemoryBytes = physicalMemoryBytes
    self.freeDiskBytes = freeDiskBytes
    self.metal = metal
    self.rosetta = rosetta
    self.xcode = xcode
    self.gptk = gptk
    self.gatekeeper = gatekeeper
    self.findings = findings
  }
}
