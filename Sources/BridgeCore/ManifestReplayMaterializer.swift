import Foundation

struct ManifestReplayDecodingScope: Equatable, Sendable {
  let release: GameRelease
  let intent: ManifestIntent
  let categories: Set<ResourceCategory>
  let profileRevision: UInt64
  let schemaBaseline: ManifestSchemaBaseline

  fileprivate init(descriptor: ValidatedReplayDescriptor) {
    release = descriptor.expectedRequest.release
    intent = descriptor.expectedRequest.intent
    categories = descriptor.expectedRequest.categories
    profileRevision = descriptor.profileRevision
    schemaBaseline = descriptor.schemaBaseline
  }
}

extension ManifestReplayDecodingScope: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  var description: String { "<redacted>" }
  var debugDescription: String { "<redacted>" }
  var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

struct ManifestReplayArtifactIdentity: Equatable, Sendable {
  let kind: ManifestEvidenceArtifactKind
  let sha256: ManifestSHA256
  let byteSize: UInt64
  let manifestReferenceSHA256: ManifestReferenceDigest?

  init(_ artifact: ValidatedReplayArtifactData) {
    kind = artifact.kind
    sha256 = artifact.sha256
    byteSize = artifact.byteSize
    manifestReferenceSHA256 = artifact.manifestReferenceSHA256
  }
}

struct DecodedManifestBranch: Equatable, Sendable {
  let artifactIdentity: ManifestReplayArtifactIdentity
  let officialVersion: GameVersion
  let preDownloadVersion: GameVersion?
  let observations: [ManifestObservation]
}

struct DecodedManifestBuildResponse: Equatable, Sendable {
  let artifactIdentity: ManifestReplayArtifactIdentity
  let targetVersion: GameVersion
  let chunkManifestReference: ManifestReferenceDigest
  let observations: [ManifestObservation]
}

enum DecodedManifestPatchOutcome: Equatable, Sendable {
  case directLdiffUnavailable
  case ldiff(manifestReference: ManifestReferenceDigest)
}

struct DecodedManifestPatchResponse: Equatable, Sendable {
  let artifactIdentity: ManifestReplayArtifactIdentity
  let sourceVersion: GameVersion
  let targetVersion: GameVersion
  let outcome: DecodedManifestPatchOutcome
  let observations: [ManifestObservation]
}

struct DecodedSemanticChunkManifest: Equatable, Sendable {
  let artifactIdentity: ManifestReplayArtifactIdentity
  let candidate: SemanticChunkManifest
  let observations: [ManifestObservation]
}

struct DecodedSemanticLdiffPlan: Equatable, Sendable {
  let artifactIdentity: ManifestReplayArtifactIdentity
  let candidate: SemanticSelectedDiffPlan
  let observations: [ManifestObservation]
}

protocol ManifestReplaySemanticDecoding: Sendable {
  func decodeBranch(
    _ artifact: ValidatedReplayArtifactData,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedManifestBranch

  func decodeBuildResponse(
    _ artifact: ValidatedReplayArtifactData,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedManifestBuildResponse

  func decodeChunkManifest(
    _ artifact: ValidatedReplayArtifactData,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedSemanticChunkManifest

  func decodePatchResponse(
    _ artifact: ValidatedReplayArtifactData,
    sourceVersion: GameVersion,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedManifestPatchResponse

  func decodeLdiffManifest(
    _ artifact: ValidatedReplayArtifactData,
    sourceVersion: GameVersion,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedSemanticLdiffPlan
}

struct MaterializedManifestReplayFixture: Equatable, Sendable {
  let fixtureID: ManifestFixtureID
  let expectedRequest: ManifestInspectionRequest
  let inspection: ManifestInspection

  fileprivate init(candidate: ManifestReplayCandidate) {
    fixtureID = candidate.fixtureID
    expectedRequest = candidate.expectedRequest
    inspection = candidate.inspection
  }
}

protocol ManifestReplayRedactedValue: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{}

extension ManifestReplayRedactedValue {
  var description: String { "<redacted>" }
  var debugDescription: String { "<redacted>" }
  var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

extension ManifestReplayArtifactIdentity: ManifestReplayRedactedValue {}
extension DecodedManifestBranch: ManifestReplayRedactedValue {}
extension DecodedManifestBuildResponse: ManifestReplayRedactedValue {}
extension DecodedManifestPatchOutcome: ManifestReplayRedactedValue {}
extension DecodedManifestPatchResponse: ManifestReplayRedactedValue {}
extension DecodedSemanticChunkManifest: ManifestReplayRedactedValue {}
extension DecodedSemanticLdiffPlan: ManifestReplayRedactedValue {}
extension MaterializedManifestReplayFixture: ManifestReplayRedactedValue {}

enum ManifestReplayMaterializer {
  static func materialize(
    _ bundle: ValidatedReplayArtifactBundle,
    using decoder: any ManifestReplaySemanticDecoding
  ) throws -> MaterializedManifestReplayFixture {
    try Task.checkCancellation()
    let descriptor = bundle.descriptor
    let scope = ManifestReplayDecodingScope(descriptor: descriptor)
    let artifacts = try artifactsByKind(bundle.externalArtifacts)
    var usedKinds = Set<ManifestEvidenceArtifactKind>()
    var observationsByCode: [String: ManifestObservation] = [:]

    let branchArtifact = try take(.branchResponse, from: artifacts, used: &usedKinds)
    let decodedBranch = try decode {
      try decoder.decodeBranch(branchArtifact, scope: scope)
    }
    try requireIdentity(decodedBranch.artifactIdentity, for: branchArtifact)
    try appendObservations(decodedBranch.observations, to: &observationsByCode)
    let branches = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: decodedBranch.officialVersion,
      preDownloadVersion: decodedBranch.preDownloadVersion
    )

    guard let targetVersion = targetVersion(for: scope.intent, branches: branches) else {
      return try finish(
        bundle: bundle,
        branches: branches,
        availability: .preDownloadNotPublished,
        target: nil,
        selectedLdiff: nil,
        usedKinds: usedKinds,
        observationsByCode: observationsByCode
      )
    }

    let buildArtifact = try take(.buildResponse, from: artifacts, used: &usedKinds)
    let decodedBuild = try decode {
      try decoder.decodeBuildResponse(
        buildArtifact,
        targetVersion: targetVersion,
        scope: scope
      )
    }
    try requireIdentity(decodedBuild.artifactIdentity, for: buildArtifact)
    try appendObservations(decodedBuild.observations, to: &observationsByCode)
    guard decodedBuild.targetVersion == targetVersion else {
      throw ManifestAdapterError.invalidManifest
    }

    let chunkArtifact = try take(.chunkManifest, from: artifacts, used: &usedKinds)
    guard chunkArtifact.manifestReferenceSHA256 == decodedBuild.chunkManifestReference else {
      throw ManifestAdapterError.invalidManifest
    }
    let decodedChunk = try decode {
      try decoder.decodeChunkManifest(
        chunkArtifact,
        targetVersion: targetVersion,
        scope: scope
      )
    }
    try requireIdentity(decodedChunk.artifactIdentity, for: chunkArtifact)
    try appendObservations(decodedChunk.observations, to: &observationsByCode)
    try Task.checkCancellation()
    let validatedChunk = try ChunkManifestValidator.validate(
      category: .game,
      candidate: decodedChunk.candidate
    )
    let target = try ManifestInspectionFactory.makeBuildManifest(
      targetVersion: targetVersion,
      categories: [.game: validatedChunk.summary]
    )

    guard let sourceVersion = sourceVersion(scope.intent) else {
      return try finish(
        bundle: bundle,
        branches: branches,
        availability: .available,
        target: target,
        selectedLdiff: nil,
        usedKinds: usedKinds,
        observationsByCode: observationsByCode
      )
    }
    guard sourceVersion != targetVersion else {
      return try finish(
        bundle: bundle,
        branches: branches,
        availability: .upToDate,
        target: target,
        selectedLdiff: nil,
        usedKinds: usedKinds,
        observationsByCode: observationsByCode
      )
    }

    let patchArtifact = try take(.patchResponse, from: artifacts, used: &usedKinds)
    let decodedPatch = try decode {
      try decoder.decodePatchResponse(
        patchArtifact,
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        scope: scope
      )
    }
    try requireIdentity(decodedPatch.artifactIdentity, for: patchArtifact)
    try appendObservations(decodedPatch.observations, to: &observationsByCode)
    guard decodedPatch.sourceVersion == sourceVersion,
      decodedPatch.targetVersion == targetVersion
    else {
      throw ManifestAdapterError.invalidManifest
    }
    switch decodedPatch.outcome {
    case .directLdiffUnavailable:
      return try finish(
        bundle: bundle,
        branches: branches,
        availability: .directLdiffUnavailable,
        target: target,
        selectedLdiff: nil,
        usedKinds: usedKinds,
        observationsByCode: observationsByCode
      )
    case .ldiff(let manifestReference):
      let ldiffArtifact = try take(.diffManifest, from: artifacts, used: &usedKinds)
      guard ldiffArtifact.manifestReferenceSHA256 == manifestReference else {
        throw ManifestAdapterError.invalidManifest
      }
      let decodedLdiff = try decode {
        try decoder.decodeLdiffManifest(
          ldiffArtifact,
          sourceVersion: sourceVersion,
          targetVersion: targetVersion,
          scope: scope
        )
      }
      try requireIdentity(decodedLdiff.artifactIdentity, for: ldiffArtifact)
      try appendObservations(decodedLdiff.observations, to: &observationsByCode)
      try Task.checkCancellation()
      let validatedLdiff = try LdiffSelectionValidator.validate(
        category: .game,
        candidate: decodedLdiff.candidate
      )
      guard validatedLdiff.selection.sourceVersion == sourceVersion,
        validatedLdiff.selection.targetVersion == targetVersion
      else {
        throw ManifestAdapterError.invalidManifest
      }
      return try finish(
        bundle: bundle,
        branches: branches,
        availability: .available,
        target: target,
        selectedLdiff: validatedLdiff.selection,
        usedKinds: usedKinds,
        observationsByCode: observationsByCode
      )
    }
  }

  private static func finish(
    bundle: ValidatedReplayArtifactBundle,
    branches: BranchSummary,
    availability: ManifestAvailability,
    target: BuildManifest?,
    selectedLdiff: LdiffSelection?,
    usedKinds: Set<ManifestEvidenceArtifactKind>,
    observationsByCode: [String: ManifestObservation]
  ) throws -> MaterializedManifestReplayFixture {
    try Task.checkCancellation()
    let descriptor = bundle.descriptor
    let observations = observationsByCode.values.sorted { $0.code < $1.code }
    guard usedKinds.count == bundle.externalArtifacts.count,
      usedKinds == Set(bundle.externalArtifacts.map(\.kind)),
      branches == descriptor.branches,
      availability == descriptor.availability,
      target == descriptor.target,
      selectedLdiff == descriptor.selectedLdiff,
      observations == descriptor.observations
    else {
      throw ManifestAdapterError.invalidManifest
    }
    let inspection = try ManifestInspectionFactory.makeInspection(
      request: descriptor.expectedRequest,
      availability: availability,
      branches: branches,
      target: target,
      selectedLdiff: selectedLdiff,
      origin: .fixture(descriptor.fixtureID),
      evidence: bundle.byteEvidence,
      observations: observations
    )
    let candidate = try ManifestReplayCandidate.make(
      fixtureID: descriptor.fixtureID,
      expectedRequest: descriptor.expectedRequest,
      candidate: inspection
    )
    try Task.checkCancellation()
    return MaterializedManifestReplayFixture(candidate: candidate)
  }

  private static func appendObservations(
    _ observations: [ManifestObservation],
    to indexed: inout [String: ManifestObservation]
  ) throws {
    for observation in observations {
      let rebuilt = try ManifestInspectionFactory.makeObservation(
        code: observation.code,
        severity: observation.severity
      )
      guard indexed[rebuilt.code] == nil else {
        throw ManifestAdapterError.invalidManifest
      }
      indexed[rebuilt.code] = rebuilt
    }
    try Task.checkCancellation()
  }

  private static func artifactsByKind(
    _ artifacts: [ValidatedReplayArtifactData]
  ) throws -> [ManifestEvidenceArtifactKind: ValidatedReplayArtifactData] {
    var result: [ManifestEvidenceArtifactKind: ValidatedReplayArtifactData] = [:]
    result.reserveCapacity(artifacts.count)
    for artifact in artifacts {
      guard artifact.kind != .fixtureDescriptor, result[artifact.kind] == nil else {
        throw ManifestAdapterError.invalidManifest
      }
      result[artifact.kind] = artifact
    }
    return result
  }

  private static func take(
    _ kind: ManifestEvidenceArtifactKind,
    from artifacts: [ManifestEvidenceArtifactKind: ValidatedReplayArtifactData],
    used: inout Set<ManifestEvidenceArtifactKind>
  ) throws -> ValidatedReplayArtifactData {
    try Task.checkCancellation()
    guard used.insert(kind).inserted, let artifact = artifacts[kind] else {
      throw ManifestAdapterError.invalidManifest
    }
    return artifact
  }

  private static func requireIdentity(
    _ identity: ManifestReplayArtifactIdentity,
    for artifact: ValidatedReplayArtifactData
  ) throws {
    guard identity == ManifestReplayArtifactIdentity(artifact) else {
      throw ManifestAdapterError.invalidManifest
    }
    try Task.checkCancellation()
  }

  private static func decode<T>(_ operation: () throws -> T) throws -> T {
    try Task.checkCancellation()
    do {
      let result = try operation()
      try Task.checkCancellation()
      return result
    } catch let error as CancellationError {
      throw error
    } catch let error as ManifestAdapterError where error == .schemaDrift {
      throw error
    } catch {
      throw ManifestAdapterError.invalidManifest
    }
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
    case .full, .preDownload(from: nil): nil
    case .update(let source), .preDownload(from: .some(let source)): source
    }
  }
}
