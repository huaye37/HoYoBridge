import CryptoKit
import Foundation

public enum CatalogSchema {
  public static let currentVersion = 1
}

public enum CatalogChannel: String, Codable, Hashable, Sendable {
  case development
  case stable
  case testing
}

public enum RuntimeBackend: String, Codable, Sendable {
  case dxmt
  case gptkD3DMetal
  case crossOverD3DMetal
  case custom
}

public enum RuntimeAcquisition: String, Codable, Sendable {
  case managedDownload
  case detectOnly
  case userProvided
}

public enum CompatibilityTier: String, Codable, Sendable {
  case standard
  case experimental
}

public enum VerificationState: String, Codable, Sendable {
  case verified
  case candidate
  case blocked
}

public enum CompatibilityMode: String, Codable, Sendable {
  case standard
  case experimental
}

public enum VerificationGate: String, Codable, CaseIterable, Sendable {
  case install
  case launch
  case login
  case sustainedRun
  case graphicsCorrectness
}

public struct GameDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let region: String

  public init(id: String, displayName: String, region: String) {
    self.id = id
    self.displayName = displayName
    self.region = region
  }
}

public struct InstalledRuntimeRequirement: Codable, Equatable, Sendable {
  public let bundleIdentifier: String?
  public let teamIdentifier: String
  public let exactVersion: String
  public let requiredPaths: [String]

  public init(
    bundleIdentifier: String? = nil,
    teamIdentifier: String,
    exactVersion: String,
    requiredPaths: [String]
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.teamIdentifier = teamIdentifier
    self.exactVersion = exactVersion
    self.requiredPaths = requiredPaths
  }
}

public struct RuntimeDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let backend: RuntimeBackend
  public let version: String
  public let verification: VerificationState
  public let acquisition: RuntimeAcquisition
  public let sourceURL: String?
  public let byteSize: UInt64?
  public let sha256: String?
  public let installedRequirement: InstalledRuntimeRequirement?
  public let license: String
  public let redistributable: Bool

  public init(
    id: String,
    backend: RuntimeBackend,
    version: String,
    verification: VerificationState,
    acquisition: RuntimeAcquisition,
    sourceURL: String? = nil,
    byteSize: UInt64? = nil,
    sha256: String? = nil,
    installedRequirement: InstalledRuntimeRequirement? = nil,
    license: String,
    redistributable: Bool
  ) {
    self.id = id
    self.backend = backend
    self.version = version
    self.verification = verification
    self.acquisition = acquisition
    self.sourceURL = sourceURL
    self.byteSize = byteSize
    self.sha256 = sha256
    self.installedRequirement = installedRequirement
    self.license = license
    self.redistributable = redistributable
  }

  public var definitionDigest: String {
    var fields = [
      id,
      backend.rawValue,
      version,
      verification.rawValue,
      acquisition.rawValue,
      sourceURL ?? "",
      byteSize.map(String.init) ?? "",
      sha256 ?? "",
      installedRequirement?.bundleIdentifier ?? "",
      installedRequirement?.teamIdentifier ?? "",
      installedRequirement?.exactVersion ?? "",
      license,
      String(redistributable),
    ]
    fields.append(
      contentsOf: installedRequirement?.requiredPaths.map { "required-path:\($0)" } ?? [])
    return Self.sha256(fields: fields)
  }

  private static func sha256(fields: [String]) -> String {
    var data = Data()
    for field in fields {
      let bytes = Data(field.utf8)
      data.append(Data("\(bytes.count):".utf8))
      data.append(bytes)
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public struct MacOSVersionRange: Codable, Equatable, Sendable {
  public let minimumMajor: Int
  public let maximumMajor: Int?

  public init(minimumMajor: Int, maximumMajor: Int? = nil) {
    self.minimumMajor = minimumMajor
    self.maximumMajor = maximumMajor
  }

  public func contains(majorVersion: Int) -> Bool {
    majorVersion >= minimumMajor && maximumMajor.map { majorVersion <= $0 } != false
  }
}

public struct RiskDisclosure: Codable, Equatable, Sendable {
  public let id: String
  public let impact: String
  public let recovery: String

  public init(id: String, impact: String, recovery: String) {
    self.id = id
    self.impact = impact
    self.recovery = recovery
  }
}

public struct VerificationRecord: Codable, Equatable, Sendable {
  public let gameBuildFingerprint: String
  public let runtimeDefinitionDigest: String
  public let profileDefinitionDigest: String
  public let macOSMajorVersion: Int
  public let architecture: String
  public let metalFamilies: [String]
  public let passedGates: [VerificationGate]
  public let verifiedAt: Date
  public let reportDigest: String

  public init(
    gameBuildFingerprint: String,
    runtimeDefinitionDigest: String,
    profileDefinitionDigest: String,
    macOSMajorVersion: Int,
    architecture: String,
    metalFamilies: [String],
    passedGates: [VerificationGate],
    verifiedAt: Date,
    reportDigest: String
  ) {
    self.gameBuildFingerprint = gameBuildFingerprint
    self.runtimeDefinitionDigest = runtimeDefinitionDigest
    self.profileDefinitionDigest = profileDefinitionDigest
    self.macOSMajorVersion = macOSMajorVersion
    self.architecture = architecture
    self.metalFamilies = metalFamilies
    self.passedGates = passedGates
    self.verifiedAt = verifiedAt
    self.reportDigest = reportDigest
  }
}

public struct CompatibilityProfile: Codable, Equatable, Sendable {
  public let id: String
  public let revision: UInt64
  public let gameID: String
  public let gameVersion: String
  public let gameBuildFingerprint: String
  public let macOS: MacOSVersionRange
  public let architectures: [String]
  public let requiredMetalFamilies: [String]
  public let requiresRosetta: Bool
  public let tier: CompatibilityTier
  public let verification: VerificationState
  public let runtimeID: String
  public let priority: Int
  public let launchArguments: [String]
  public let environment: [String: String]
  public let disclosures: [RiskDisclosure]
  public let verificationRecords: [VerificationRecord]

  public init(
    id: String,
    revision: UInt64,
    gameID: String,
    gameVersion: String,
    gameBuildFingerprint: String,
    macOS: MacOSVersionRange,
    architectures: [String],
    requiredMetalFamilies: [String] = [],
    requiresRosetta: Bool,
    tier: CompatibilityTier,
    verification: VerificationState,
    runtimeID: String,
    priority: Int = 0,
    launchArguments: [String] = [],
    environment: [String: String] = [:],
    disclosures: [RiskDisclosure] = [],
    verificationRecords: [VerificationRecord] = []
  ) {
    self.id = id
    self.revision = revision
    self.gameID = gameID
    self.gameVersion = gameVersion
    self.gameBuildFingerprint = gameBuildFingerprint
    self.macOS = macOS
    self.architectures = architectures
    self.requiredMetalFamilies = requiredMetalFamilies
    self.requiresRosetta = requiresRosetta
    self.tier = tier
    self.verification = verification
    self.runtimeID = runtimeID
    self.priority = priority
    self.launchArguments = launchArguments
    self.environment = environment
    self.disclosures = disclosures
    self.verificationRecords = verificationRecords
  }

  public var disclosureDigest: String {
    let fields =
      disclosures
      .sorted { $0.id < $1.id }
      .flatMap { [$0.id, $0.impact, $0.recovery] }
    var data = Data()
    for field in fields {
      let bytes = Data(field.utf8)
      data.append(Data("\(bytes.count):".utf8))
      data.append(bytes)
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public var definitionDigest: String {
    var fields = [
      id,
      String(revision),
      gameID,
      gameVersion,
      gameBuildFingerprint,
      String(macOS.minimumMajor),
      macOS.maximumMajor.map(String.init) ?? "",
      String(requiresRosetta),
      tier.rawValue,
      verification.rawValue,
      runtimeID,
      String(priority),
    ]
    fields.append(contentsOf: architectures.sorted().map { "architecture:\($0)" })
    fields.append(contentsOf: requiredMetalFamilies.sorted().map { "metal:\($0)" })
    fields.append(contentsOf: launchArguments.map { "argument:\($0)" })
    for key in environment.keys.sorted() {
      fields.append("environment-key:\(key)")
      fields.append("environment-value:\(environment[key] ?? "")")
    }
    for disclosure in disclosures.sorted(by: { $0.id < $1.id }) {
      fields.append(contentsOf: [
        "disclosure-id:\(disclosure.id)",
        "disclosure-impact:\(disclosure.impact)",
        "disclosure-recovery:\(disclosure.recovery)",
      ])
    }

    var data = Data()
    for field in fields {
      let bytes = Data(field.utf8)
      data.append(Data("\(bytes.count):".utf8))
      data.append(bytes)
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public struct RevocationList: Codable, Equatable, Sendable {
  public let runtimeIDs: [String]
  public let profileIDs: [String]

  public init(runtimeIDs: [String] = [], profileIDs: [String] = []) {
    self.runtimeIDs = runtimeIDs
    self.profileIDs = profileIDs
  }
}

public struct CompatibilityCatalog: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let revision: UInt64
  public let catalogVersion: String
  public let channel: CatalogChannel
  public let issuedAt: Date
  public let expiresAt: Date
  public let minimumClientVersion: String
  public let games: [GameDefinition]
  public let runtimes: [RuntimeDefinition]
  public let profiles: [CompatibilityProfile]
  public let revocations: RevocationList

  public init(
    schemaVersion: Int = CatalogSchema.currentVersion,
    revision: UInt64,
    catalogVersion: String,
    channel: CatalogChannel,
    issuedAt: Date,
    expiresAt: Date,
    minimumClientVersion: String,
    games: [GameDefinition],
    runtimes: [RuntimeDefinition],
    profiles: [CompatibilityProfile],
    revocations: RevocationList = .init()
  ) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.catalogVersion = catalogVersion
    self.channel = channel
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.minimumClientVersion = minimumClientVersion
    self.games = games
    self.runtimes = runtimes
    self.profiles = profiles
    self.revocations = revocations
  }
}

public struct VerifiedCatalog: Equatable, Sendable {
  public let catalog: CompatibilityCatalog
  public let payloadSHA256: String
}
