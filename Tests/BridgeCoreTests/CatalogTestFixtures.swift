import CryptoKit
import Foundation

@testable import BridgeCore

enum CatalogTestFixtures {
  static let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)
  static let now = Date(timeIntervalSince1970: 1_800_000_000)
  static let expiresAt = Date(timeIntervalSince1970: 1_900_000_000)
  static let gameFingerprint = String(repeating: "a", count: 64)
  static let reportDigest = String(repeating: "b", count: 64)
  static let artifactDigest = String(repeating: "c", count: 64)

  static func runtime(
    id: String = "runtime-stable",
    verification: VerificationState = .verified,
    acquisition: RuntimeAcquisition = .managedDownload,
    sourceURL: String? = "https://downloads.example.invalid/runtime-1.0.zip",
    byteSize: UInt64? = 1_024,
    sha256: String? = artifactDigest,
    redistributable: Bool = true
  ) -> RuntimeDefinition {
    RuntimeDefinition(
      id: id,
      backend: .dxmt,
      version: "1.0.0",
      verification: verification,
      acquisition: acquisition,
      sourceURL: sourceURL,
      byteSize: byteSize,
      sha256: sha256,
      license: "MIT",
      redistributable: redistributable
    )
  }

  static func standardProfile(
    id: String = "profile-standard",
    runtime: RuntimeDefinition,
    priority: Int = 100,
    macOS: MacOSVersionRange = .init(minimumMajor: 27, maximumMajor: 27)
  ) -> CompatibilityProfile {
    let base = CompatibilityProfile(
      id: id,
      revision: 1,
      gameID: "genshin-cn",
      gameVersion: "1.0.0",
      gameBuildFingerprint: gameFingerprint,
      macOS: macOS,
      architectures: ["arm64"],
      requiredMetalFamilies: ["apple10"],
      requiresRosetta: true,
      tier: .standard,
      verification: .verified,
      runtimeID: runtime.id,
      priority: priority
    )
    let record = VerificationRecord(
      gameBuildFingerprint: gameFingerprint,
      runtimeDefinitionDigest: runtime.definitionDigest,
      profileDefinitionDigest: base.definitionDigest,
      macOSMajorVersion: macOS.minimumMajor,
      architecture: "arm64",
      metalFamilies: ["apple10"],
      passedGates: VerificationGate.allCases,
      verifiedAt: issuedAt,
      reportDigest: reportDigest
    )
    return CompatibilityProfile(
      id: base.id,
      revision: base.revision,
      gameID: base.gameID,
      gameVersion: base.gameVersion,
      gameBuildFingerprint: base.gameBuildFingerprint,
      macOS: base.macOS,
      architectures: base.architectures,
      requiredMetalFamilies: base.requiredMetalFamilies,
      requiresRosetta: base.requiresRosetta,
      tier: base.tier,
      verification: base.verification,
      runtimeID: base.runtimeID,
      priority: base.priority,
      launchArguments: base.launchArguments,
      environment: base.environment,
      disclosures: base.disclosures,
      verificationRecords: [record]
    )
  }

  static func experimentalProfile(
    id: String = "profile-experimental",
    revision: UInt64 = 1,
    runtimeID: String = "runtime-candidate",
    disclosureImpact: String = "This configuration has not completed sustained-run validation.",
    disclosures: [RiskDisclosure]? = nil
  ) -> CompatibilityProfile {
    CompatibilityProfile(
      id: id,
      revision: revision,
      gameID: "genshin-cn",
      gameVersion: "1.0.0",
      gameBuildFingerprint: gameFingerprint,
      macOS: .init(minimumMajor: 27, maximumMajor: 27),
      architectures: ["arm64"],
      requiredMetalFamilies: ["apple10"],
      requiresRosetta: true,
      tier: .experimental,
      verification: .candidate,
      runtimeID: runtimeID,
      priority: 50,
      disclosures: disclosures ?? [
        .init(
          id: "unverified-runtime",
          impact: disclosureImpact,
          recovery: "Stop the game and switch back to the last verified profile."
        )
      ]
    )
  }

  static func catalog(
    revision: UInt64 = 10,
    minimumClientVersion: String = "0.1.0",
    channel: CatalogChannel = .testing,
    expiresAt: Date = expiresAt,
    runtimes: [RuntimeDefinition],
    profiles: [CompatibilityProfile]
  ) -> CompatibilityCatalog {
    CompatibilityCatalog(
      revision: revision,
      catalogVersion: "1.0.0",
      channel: channel,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      minimumClientVersion: minimumClientVersion,
      games: [.init(id: "genshin-cn", displayName: "Test Game", region: "CN")],
      runtimes: runtimes,
      profiles: profiles
    )
  }

  static func request(
    mode: CompatibilityMode,
    preferredProfileID: String? = nil,
    acknowledgements: Set<ProfileAcknowledgement> = []
  ) -> CompatibilityRequest {
    CompatibilityRequest(
      gameID: "genshin-cn",
      gameVersion: "1.0.0",
      gameBuildFingerprint: gameFingerprint,
      macOSMajorVersion: 27,
      architecture: "arm64",
      metalFamilies: ["apple10"],
      rosettaAvailable: true,
      mode: mode,
      preferredProfileID: preferredProfileID,
      acknowledgements: acknowledgements
    )
  }

  static func verifiedCatalog(_ catalog: CompatibilityCatalog) -> VerifiedCatalog {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let payload = try! encoder.encode(catalog)
    let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    return VerifiedCatalog(catalog: catalog, payloadSHA256: digest)
  }
}
