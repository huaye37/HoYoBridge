import Foundation

public struct RuntimeActivationRecord: Encodable, Equatable, Sendable {
  public static let currentSchemaVersion: UInt8 = 1

  public let schemaVersion: UInt8
  public let activationID: String
  public let generation: UInt64
  public let catalogRevision: UInt64
  public let catalogPayloadSHA256: String
  public let catalogChannel: CatalogChannel
  public let selectionMode: CompatibilityMode
  public let acknowledgementSHA256: String?
  public let profileID: String
  public let profileRevision: UInt64
  public let profileDefinitionSHA256: String
  public let disclosureSHA256: String
  public let gameID: String
  public let gameVersion: String
  public let gameBuildFingerprint: String
  public let runtimeID: String
  public let runtimeDefinitionSHA256: String
  public let installID: String
  public let artifactSHA256: String
  public let planPolicyVersion: Int
  public let planSHA256: String
  public let treeSealVersion: UInt8
  public let treeSHA256: String
  public let compatibilityTier: CompatibilityTier
}

public enum RuntimeActivationIdentityError: Error, Equatable, Sendable {
  case invalidGeneration
  case invalidCatalogIdentity
  case invalidInstalledRuntime
  case installedRuntimeMismatch
}

public enum RuntimeActivationIdentityBuilder {
  public static func build(
    installed: InstalledRuntimeVersion,
    verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest,
    generation: UInt64
  ) throws -> RuntimeActivationRecord {
    guard generation > 0 else { throw RuntimeActivationIdentityError.invalidGeneration }
    let decision = try CompatibilitySelector.select(from: verifiedCatalog, request: request)
    let install = installed.record
    guard validInstall(install, at: installed.versionURL) else {
      throw RuntimeActivationIdentityError.invalidInstalledRuntime
    }
    guard let runtimeArtifact = decision.runtime.sha256?.lowercased(),
      isSHA256(runtimeArtifact),
      install.runtimeID == decision.runtime.id,
      install.runtimeDefinitionSHA256 == decision.runtime.definitionDigest,
      install.artifactSHA256 == runtimeArtifact
    else {
      throw RuntimeActivationIdentityError.installedRuntimeMismatch
    }

    let catalog = verifiedCatalog.catalog
    let profile = decision.profile
    let profileDefinitionSHA256 = profile.definitionDigest
    let disclosureSHA256 = profile.disclosureDigest
    let gameBuildFingerprint = profile.gameBuildFingerprint.lowercased()
    guard isSHA256(verifiedCatalog.payloadSHA256),
      isSHA256(profileDefinitionSHA256),
      isSHA256(disclosureSHA256),
      isSHA256(gameBuildFingerprint)
    else {
      throw RuntimeActivationIdentityError.invalidCatalogIdentity
    }
    let acknowledgementSHA256: String?
    if profile.tier == .experimental {
      acknowledgementSHA256 = digestAcknowledgement(
        CompatibilitySelector.acknowledgement(for: profile, in: verifiedCatalog)
      )
    } else {
      acknowledgementSHA256 = nil
    }

    var record = RuntimeActivationRecord(
      schemaVersion: RuntimeActivationRecord.currentSchemaVersion,
      activationID: "",
      generation: generation,
      catalogRevision: catalog.revision,
      catalogPayloadSHA256: verifiedCatalog.payloadSHA256,
      catalogChannel: catalog.channel,
      selectionMode: request.mode,
      acknowledgementSHA256: acknowledgementSHA256,
      profileID: profile.id,
      profileRevision: profile.revision,
      profileDefinitionSHA256: profileDefinitionSHA256,
      disclosureSHA256: disclosureSHA256,
      gameID: profile.gameID,
      gameVersion: profile.gameVersion,
      gameBuildFingerprint: gameBuildFingerprint,
      runtimeID: decision.runtime.id,
      runtimeDefinitionSHA256: decision.runtime.definitionDigest,
      installID: install.installID,
      artifactSHA256: install.artifactSHA256,
      planPolicyVersion: install.planPolicyVersion,
      planSHA256: install.planSHA256,
      treeSealVersion: install.treeSealVersion,
      treeSHA256: install.treeSHA256,
      compatibilityTier: profile.tier
    )
    record = replacingActivationID(record, with: activationID(record))
    return record
  }

  private static func validInstall(_ record: RuntimeInstallRecord, at url: URL) -> Bool {
    guard record.schemaVersion == RuntimeInstallRecord.currentSchemaVersion,
      record.planPolicyVersion == SafeArchivePlanner.currentPolicyVersion,
      record.treeSealVersion == SafeStagingTreeSealer.currentVersion,
      record.entryCount == record.entries.count,
      record.regularFileCount >= 0,
      url.lastPathComponent == record.installID,
      [
        record.installID, record.runtimeDefinitionSHA256, record.artifactSHA256,
        record.planSHA256, record.treeSHA256,
      ].allSatisfy(isSHA256)
    else { return false }
    var files = 0
    var total: UInt64 = 0
    for entry in record.entries where entry.kind == .regularFile {
      let (next, overflow) = total.addingReportingOverflow(entry.size)
      if overflow { return false }
      total = next
      files += 1
    }
    return files == record.regularFileCount && total == record.totalBytes
  }

  private static func digestAcknowledgement(_ acknowledgement: ProfileAcknowledgement) -> String {
    var digest = CanonicalSHA256Builder(domain: Array("MGBACK".utf8))
    digest.append(UInt8(1))
    digest.append(acknowledgement.catalogRevision)
    digest.appendSHA256(acknowledgement.catalogPayloadSHA256)
    digest.appendFramed(acknowledgement.profileID)
    digest.append(acknowledgement.profileRevision)
    digest.appendSHA256(acknowledgement.disclosureDigest)
    return digest.finalize()
  }

  static func activationID(_ record: RuntimeActivationRecord) -> String {
    var digest = CanonicalSHA256Builder(domain: Array("MGBCURRENT".utf8))
    digest.append(record.schemaVersion)
    digest.append(record.generation)
    digest.append(record.catalogRevision)
    digest.appendSHA256(record.catalogPayloadSHA256)
    digest.appendFramed(record.catalogChannel.rawValue)
    digest.appendFramed(record.selectionMode.rawValue)
    if let acknowledgementSHA256 = record.acknowledgementSHA256 {
      digest.append(UInt8(1))
      digest.appendSHA256(acknowledgementSHA256)
    } else {
      digest.append(UInt8(0))
    }
    digest.appendFramed(record.profileID)
    digest.append(record.profileRevision)
    digest.appendSHA256(record.profileDefinitionSHA256)
    digest.appendSHA256(record.disclosureSHA256)
    digest.appendFramed(record.gameID)
    digest.appendFramed(record.gameVersion)
    digest.appendSHA256(record.gameBuildFingerprint)
    digest.appendFramed(record.runtimeID)
    digest.appendSHA256(record.runtimeDefinitionSHA256)
    digest.appendSHA256(record.installID)
    digest.appendSHA256(record.artifactSHA256)
    digest.append(UInt32(record.planPolicyVersion))
    digest.appendSHA256(record.planSHA256)
    digest.append(record.treeSealVersion)
    digest.appendSHA256(record.treeSHA256)
    digest.appendFramed(record.compatibilityTier.rawValue)
    return digest.finalize()
  }

  private static func replacingActivationID(
    _ value: RuntimeActivationRecord,
    with activationID: String
  ) -> RuntimeActivationRecord {
    RuntimeActivationRecord(
      schemaVersion: value.schemaVersion, activationID: activationID,
      generation: value.generation, catalogRevision: value.catalogRevision,
      catalogPayloadSHA256: value.catalogPayloadSHA256, catalogChannel: value.catalogChannel,
      selectionMode: value.selectionMode, acknowledgementSHA256: value.acknowledgementSHA256,
      profileID: value.profileID, profileRevision: value.profileRevision,
      profileDefinitionSHA256: value.profileDefinitionSHA256,
      disclosureSHA256: value.disclosureSHA256, gameID: value.gameID,
      gameVersion: value.gameVersion, gameBuildFingerprint: value.gameBuildFingerprint,
      runtimeID: value.runtimeID, runtimeDefinitionSHA256: value.runtimeDefinitionSHA256,
      installID: value.installID, artifactSHA256: value.artifactSHA256,
      planPolicyVersion: value.planPolicyVersion, planSHA256: value.planSHA256,
      treeSealVersion: value.treeSealVersion, treeSHA256: value.treeSHA256,
      compatibilityTier: value.compatibilityTier
    )
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
