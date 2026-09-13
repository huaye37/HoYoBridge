import CryptoKit
import Foundation

struct ValidatedReplayExternalArtifactBinding: Equatable, Sendable {
  let kind: ManifestEvidenceArtifactKind
  let sha256: ManifestSHA256
  let byteSize: UInt64
  let manifestReferenceSHA256: ManifestReferenceDigest?

  fileprivate init(
    kind: ManifestEvidenceArtifactKind,
    sha256: ManifestSHA256,
    byteSize: UInt64,
    manifestReferenceSHA256: ManifestReferenceDigest?
  ) {
    self.kind = kind
    self.sha256 = sha256
    self.byteSize = byteSize
    self.manifestReferenceSHA256 = manifestReferenceSHA256
  }
}

/// Canonical summary metadata only. This is not replayable evidence or a registry fixture.
struct ValidatedReplayDescriptor: Equatable, Sendable {
  let schemaVersion: UInt8
  let fixtureID: ManifestFixtureID
  let expectedRequest: ManifestInspectionRequest
  let availability: ManifestAvailability
  let branches: BranchSummary
  let target: BuildManifest?
  let selectedLdiff: LdiffSelection?
  let profileRevision: UInt64
  let observedAt: Date
  let expiresAt: Date?
  let schemaBaseline: ManifestSchemaBaseline
  let observations: [ManifestObservation]
  let externalArtifactBindings: [ValidatedReplayExternalArtifactBinding]
  let fixtureDescriptorSHA256: String
  let fixtureDescriptorByteSize: UInt64

  var expectedArtifactKinds: [ManifestEvidenceArtifactKind] {
    externalArtifactBindings.map(\.kind)
  }

  fileprivate init(
    schemaVersion: UInt8,
    fixtureID: ManifestFixtureID,
    expectedRequest: ManifestInspectionRequest,
    availability: ManifestAvailability,
    branches: BranchSummary,
    target: BuildManifest?,
    selectedLdiff: LdiffSelection?,
    profileRevision: UInt64,
    observedAt: Date,
    expiresAt: Date?,
    schemaBaseline: ManifestSchemaBaseline,
    observations: [ManifestObservation],
    externalArtifactBindings: [ValidatedReplayExternalArtifactBinding],
    fixtureDescriptorSHA256: String,
    fixtureDescriptorByteSize: UInt64
  ) {
    self.schemaVersion = schemaVersion
    self.fixtureID = fixtureID
    self.expectedRequest = expectedRequest
    self.availability = availability
    self.branches = branches
    self.target = target
    self.selectedLdiff = selectedLdiff
    self.profileRevision = profileRevision
    self.observedAt = observedAt
    self.expiresAt = expiresAt
    self.schemaBaseline = schemaBaseline
    self.observations = observations
    self.externalArtifactBindings = externalArtifactBindings
    self.fixtureDescriptorSHA256 = fixtureDescriptorSHA256
    self.fixtureDescriptorByteSize = fixtureDescriptorByteSize
  }
}

enum ManifestReplayDescriptorDecodingError: Error, Equatable, Sendable {
  case oversized
  case malformed
  case invalidDescriptor
  case nonCanonical
}

enum ManifestReplayDescriptorDecoder {
  static let currentSchemaVersion: UInt8 = 3
  static let maximumBytes = 64 * 1_024
  static let maximumDepth = 16

  static func decode(_ data: Data) throws -> ValidatedReplayDescriptor {
    guard !data.isEmpty else { throw ManifestReplayDescriptorDecodingError.malformed }
    guard data.count <= maximumBytes else {
      throw ManifestReplayDescriptorDecodingError.oversized
    }
    guard validJSONDepth(data) else {
      throw ManifestReplayDescriptorDecodingError.malformed
    }
    let dto: ReplayDescriptorDTO
    do {
      dto = try JSONDecoder().decode(ReplayDescriptorDTO.self, from: data)
    } catch {
      throw ManifestReplayDescriptorDecodingError.malformed
    }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      guard try encoder.encode(dto) == data else {
        throw ManifestReplayDescriptorDecodingError.nonCanonical
      }
    } catch let error as ManifestReplayDescriptorDecodingError {
      throw error
    } catch {
      throw ManifestReplayDescriptorDecodingError.malformed
    }
    do {
      return try build(dto, raw: data)
    } catch {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
  }

  private static func build(
    _ dto: ReplayDescriptorDTO,
    raw: Data
  ) throws -> ValidatedReplayDescriptor {
    guard dto.schemaVersion == currentSchemaVersion,
      dto.scope.release == "genshinOfficialCN",
      dto.scope.categories == ["game"],
      dto.evidenceMetadata.profileRevision > 0,
      dto.observations.count <= 256,
      let byteSize = UInt64(exactly: raw.count)
    else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    let fixtureID = try ManifestFixtureID(dto.scope.fixtureID)
    let intent = try makeIntent(dto.scope.intent)
    let request = try ManifestInspectionRequest(
      release: .genshinOfficialCN,
      intent: intent,
      categories: [.game],
      cachePolicy: .fixtureOnly(id: fixtureID)
    )
    let availability = try makeAvailability(dto.availability)
    let branches = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: try GameVersion(dto.branches.officialVersion),
      preDownloadVersion: try dto.branches.preDownloadVersion.map(GameVersion.init)
    )
    let slotTargetVersion = targetVersion(for: intent, branches: branches)
    let target = try dto.target.map { value in
      guard let slotTargetVersion else {
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      return try makeTarget(value, targetVersion: slotTargetVersion)
    }
    let selectedLdiff = try dto.selectedLdiff.map { value in
      guard let sourceVersion = sourceVersion(intent), let slotTargetVersion else {
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      return try makeSelectedLdiff(
        value,
        sourceVersion: sourceVersion,
        targetVersion: slotTargetVersion
      )
    }
    let observations = try dto.observations.map(makeObservation)
    try ManifestInspectionFactory.validateInspectionShape(
      request: request,
      availability: availability,
      branches: branches,
      target: target,
      selectedLdiff: selectedLdiff,
      observations: observations
    )
    let observedAt = try makeDate(dto.evidenceMetadata.observedAtUnixSeconds)
    let expiresAt = try dto.evidenceMetadata.expiresAtUnixSeconds.map(makeDate)
    guard expiresAt.map({ $0 > observedAt }) != false else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    let expectedKinds = ManifestInspectionFactory.expectedEvidenceArtifactKinds(
      availability: availability,
      target: target,
      selectedLdiff: selectedLdiff,
      includesFixtureDescriptor: false
    )
    let bindings = try makeExternalArtifactBindings(
      dto.externalArtifactBindings,
      expectedKinds: expectedKinds,
      descriptorByteSize: byteSize
    )
    return ValidatedReplayDescriptor(
      schemaVersion: dto.schemaVersion,
      fixtureID: fixtureID,
      expectedRequest: request,
      availability: availability,
      branches: branches,
      target: target,
      selectedLdiff: selectedLdiff,
      profileRevision: dto.evidenceMetadata.profileRevision,
      observedAt: observedAt,
      expiresAt: expiresAt,
      schemaBaseline: try ManifestSchemaBaseline(dto.evidenceMetadata.schemaBaseline),
      observations: observations,
      externalArtifactBindings: bindings,
      fixtureDescriptorSHA256: sha256(raw),
      fixtureDescriptorByteSize: byteSize
    )
  }

  private static func makeExternalArtifactBindings(
    _ values: [ReplayExternalArtifactBindingDTO],
    expectedKinds: [ManifestEvidenceArtifactKind],
    descriptorByteSize: UInt64
  ) throws -> [ValidatedReplayExternalArtifactBinding] {
    guard values.count == expectedKinds.count else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    let limits = ManifestReplayArtifactBundleLimits.default
    var totalByteSize = descriptorByteSize
    var result: [ValidatedReplayExternalArtifactBinding] = []
    result.reserveCapacity(values.count)
    for (value, expectedKind) in zip(values, expectedKinds) {
      guard value.kind == expectedKind.rawValue, value.byteSize > 0,
        let maximumBytes = limits.maximumBytes(for: expectedKind),
        value.byteSize <= maximumBytes
      else {
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      let sha256 = try parseLowercaseSHA256(value.sha256)
      let manifestReferenceSHA256: ManifestReferenceDigest?
      switch expectedKind {
      case .chunkManifest, .diffManifest:
        guard let reference = value.manifestReferenceSHA256 else {
          throw ManifestReplayDescriptorDecodingError.invalidDescriptor
        }
        manifestReferenceSHA256 = try ManifestReferenceDigest.parseLowercaseHex(reference)
      case .branchResponse, .buildResponse, .patchResponse:
        guard value.manifestReferenceSHA256 == nil else {
          throw ManifestReplayDescriptorDecodingError.invalidDescriptor
        }
        manifestReferenceSHA256 = nil
      case .fixtureDescriptor:
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      let (nextTotal, overflow) = totalByteSize.addingReportingOverflow(value.byteSize)
      guard !overflow, nextTotal <= limits.totalBytes else {
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      totalByteSize = nextTotal
      result.append(
        ValidatedReplayExternalArtifactBinding(
          kind: expectedKind,
          sha256: sha256,
          byteSize: value.byteSize,
          manifestReferenceSHA256: manifestReferenceSHA256
        ))
    }
    return result
  }

  private static func parseLowercaseSHA256(_ value: String) throws -> ManifestSHA256 {
    guard value.utf8.count == 64,
      value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    return try ManifestSHA256(value)
  }

  private static func makeIntent(_ dto: ReplayIntentDTO) throws -> ManifestIntent {
    switch dto.kind {
    case "full":
      guard dto.sourceVersion == nil else {
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      return .full
    case "update":
      guard let sourceVersion = dto.sourceVersion else {
        throw ManifestReplayDescriptorDecodingError.invalidDescriptor
      }
      return try .update(from: GameVersion(sourceVersion))
    case "preDownload":
      return try .preDownload(from: dto.sourceVersion.map(GameVersion.init))
    default:
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
  }

  private static func makeAvailability(_ value: String) throws -> ManifestAvailability {
    guard let availability = ManifestAvailability(rawValue: value) else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    return availability
  }

  private static func makeTarget(
    _ dto: ReplayTargetDTO,
    targetVersion: GameVersion
  ) throws -> BuildManifest {
    let sizes = try ManifestInspectionFactory.makeChunkSizeSummary(
      targetInstalledBytes: dto.game.targetInstalledBytes,
      referencedChunkCompressedBytes: dto.game.referencedChunkCompressedBytes,
      uniqueChunkObjectBytes: dto.game.uniqueChunkObjectBytes
    )
    let game = try ManifestInspectionFactory.makeChunkManifest(
      fileCount: dto.game.fileCount,
      directoryCount: dto.game.directoryCount,
      chunkReferenceCount: dto.game.chunkReferenceCount,
      uniqueChunkObjectCount: dto.game.uniqueChunkObjectCount,
      sizes: sizes
    )
    return try ManifestInspectionFactory.makeBuildManifest(
      targetVersion: targetVersion,
      categories: [.game: game]
    )
  }

  private static func makeSelectedLdiff(
    _ dto: ReplaySelectedLdiffDTO,
    sourceVersion: GameVersion,
    targetVersion: GameVersion
  ) throws -> LdiffSelection {
    let game = try ManifestInspectionFactory.makeLdiffSelectionSummary(
      manifestFileRecordCount: dto.game.manifestFileRecordCount,
      selectedPatchFileCount: dto.game.selectedPatchFileCount,
      fileRecordsWithoutSelectedPatchCount: dto.game.fileRecordsWithoutSelectedPatchCount,
      selectedDeletionCount: dto.game.selectedDeletionCount,
      uniquePatchObjectCount: dto.game.uniquePatchObjectCount,
      selectedPatchObjectBytes: dto.game.selectedPatchObjectBytes
    )
    return try ManifestInspectionFactory.makeLdiffSelection(
      sourceVersion: sourceVersion,
      targetVersion: targetVersion,
      categories: [.game: game]
    )
  }

  private static func targetVersion(
    for intent: ManifestIntent,
    branches: BranchSummary
  ) -> GameVersion? {
    switch intent {
    case .full, .update: branches.officialVersion
    case .preDownload: branches.preDownloadVersion
    }
  }

  private static func sourceVersion(_ intent: ManifestIntent) -> GameVersion? {
    switch intent {
    case .full: nil
    case .update(let source), .preDownload(from: .some(let source)): source
    case .preDownload(from: nil): nil
    }
  }

  private static func makeObservation(_ dto: ReplayObservationDTO) throws -> ManifestObservation {
    let severity: ManifestObservationSeverity
    switch dto.severity {
    case "info": severity = .info
    case "warning": severity = .warning
    case "error": severity = .error
    default: throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    return try ManifestInspectionFactory.makeObservation(code: dto.code, severity: severity)
  }

  private static func makeDate(_ seconds: Int64) throws -> Date {
    let maximumUnixSeconds: Int64 = 253_402_300_799
    guard seconds >= 0, seconds <= maximumUnixSeconds else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    let value = TimeInterval(seconds)
    guard value.isFinite else {
      throw ManifestReplayDescriptorDecodingError.invalidDescriptor
    }
    return Date(timeIntervalSince1970: value)
  }

  private static func validJSONDepth(_ data: Data) -> Bool {
    var depth = 0
    var inString = false
    var escaped = false
    for byte in data {
      if inString {
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          inString = false
        }
      } else if byte == 34 {
        inString = true
      } else if byte == 123 || byte == 91 {
        depth += 1
        if depth > maximumDepth { return false }
      } else if byte == 125 || byte == 93 {
        depth -= 1
        if depth < 0 { return false }
      }
    }
    return depth == 0 && !inString
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private struct ReplayDescriptorDTO: Codable {
  let schemaVersion: UInt8
  let scope: ReplayScopeDTO
  let availability: String
  let branches: ReplayBranchesDTO
  let target: ReplayTargetDTO?
  let selectedLdiff: ReplaySelectedLdiffDTO?
  let externalArtifactBindings: [ReplayExternalArtifactBindingDTO]
  let evidenceMetadata: ReplayEvidenceMetadataDTO
  let observations: [ReplayObservationDTO]
}

private struct ReplayExternalArtifactBindingDTO: Codable {
  let kind: String
  let sha256: String
  let byteSize: UInt64
  let manifestReferenceSHA256: String?
}

private struct ReplayScopeDTO: Codable {
  let fixtureID: String
  let release: String
  let intent: ReplayIntentDTO
  let categories: [String]
}

private struct ReplayIntentDTO: Codable {
  let kind: String
  let sourceVersion: String?
}

private struct ReplayBranchesDTO: Codable {
  let officialVersion: String
  let preDownloadVersion: String?
}

private struct ReplayTargetDTO: Codable {
  let game: ReplayChunkSummaryDTO
}

private struct ReplayChunkSummaryDTO: Codable {
  let fileCount: UInt64
  let directoryCount: UInt64
  let chunkReferenceCount: UInt64
  let uniqueChunkObjectCount: UInt64
  let targetInstalledBytes: UInt64
  let referencedChunkCompressedBytes: UInt64
  let uniqueChunkObjectBytes: UInt64
}

private struct ReplaySelectedLdiffDTO: Codable {
  let game: ReplayLdiffSelectionSummaryDTO
}

private struct ReplayLdiffSelectionSummaryDTO: Codable {
  let manifestFileRecordCount: UInt64
  let selectedPatchFileCount: UInt64
  let fileRecordsWithoutSelectedPatchCount: UInt64
  let selectedDeletionCount: UInt64
  let uniquePatchObjectCount: UInt64
  let selectedPatchObjectBytes: UInt64
}

private struct ReplayEvidenceMetadataDTO: Codable {
  let profileRevision: UInt64
  let observedAtUnixSeconds: Int64
  let expiresAtUnixSeconds: Int64?
  let schemaBaseline: String
}

private struct ReplayObservationDTO: Codable {
  let code: String
  let severity: String
}
