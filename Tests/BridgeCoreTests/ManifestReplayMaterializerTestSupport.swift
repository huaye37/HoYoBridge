import CryptoKit
import Foundation

@testable import BridgeCore

enum MaterializerTestShape: Equatable, Sendable {
  case full
  case update
  case preDownloadFull
  case preDownloadUpdate
  case upToDate
  case unpublished
  case unavailable
  case emptyUpdate
}

struct MaterializerTestFixture {
  let bundle: ValidatedReplayArtifactBundle
  let decoder: SyntheticManifestReplayDecoder
  let expectedCalls: [ManifestEvidenceArtifactKind]

  static func make(
    _ shape: MaterializerTestShape,
    id: String? = nil,
    artifactDataOverrides: [ManifestEvidenceArtifactKind: Data] = [:]
  ) throws -> MaterializerTestFixture {
    let spec = try MaterializerTestSpec(shape: shape, id: id)
    let externalKinds = spec.bindingKinds
    let artifactData = Dictionary(
      uniqueKeysWithValues: externalKinds.map { kind in
        (
          kind,
          artifactDataOverrides[kind]
            ?? Data("\(spec.fixtureID.value):\(kind.rawValue)".utf8)
        )
      })
    let chunkReference = try reference(
      id: "\(spec.fixtureID.value)-chunk", kind: .chunk)
    let ldiffReference = try reference(
      id: "\(spec.fixtureID.value)-ldiff", kind: .ldiff)
    let bindings = try externalKinds.map { kind -> MaterializerBindingDTO in
      let data = try required(artifactData[kind])
      let reference: String?
      switch kind {
      case .chunkManifest: reference = chunkReference.lowercaseHex
      case .diffManifest: reference = ldiffReference.lowercaseHex
      default: reference = nil
      }
      return MaterializerBindingDTO(
        kind: kind.rawValue,
        sha256: sha256(data),
        byteSize: UInt64(data.count),
        manifestReferenceSHA256: reference
      )
    }
    let descriptorDTO = MaterializerDescriptorDTO(
      schemaVersion: 3,
      scope: MaterializerScopeDTO(
        fixtureID: spec.fixtureID.value,
        release: GameRelease.genshinOfficialCN.rawValue,
        intent: MaterializerIntentDTO(
          kind: spec.intentKind,
          sourceVersion: spec.sourceVersion?.value
        ),
        categories: [ResourceCategory.game.rawValue]
      ),
      availability: spec.availability.rawValue,
      branches: MaterializerBranchesDTO(
        officialVersion: spec.officialVersion.value,
        preDownloadVersion: spec.preDownloadVersion?.value
      ),
      target: spec.hasTarget ? MaterializerTargetDTO(game: .chunk) : nil,
      selectedLdiff: spec.hasLdiff
        ? MaterializerSelectedLdiffDTO(game: spec.isEmptyLdiff ? .empty : .nonempty)
        : nil,
      externalArtifactBindings: bindings,
      evidenceMetadata: MaterializerEvidenceDTO(
        profileRevision: 1,
        observedAtUnixSeconds: 1,
        expiresAtUnixSeconds: 2,
        schemaBaseline: ManifestProtobufStructuralMapper.requiredSchemaBaseline
      ),
      observations: spec.expectedCalls
        .map { MaterializerObservationDTO(code: $0.rawValue, severity: "info") }
        .sorted { $0.code < $1.code }
    )
    let descriptor = try ManifestReplayDescriptorDecoder.decode(
      try canonicalData(descriptorDTO))
    let inputs = try externalKinds.map { kind in
      ManifestReplayArtifactData(kind: kind, data: try required(artifactData[kind]))
    }
    let bundle = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor,
      artifacts: inputs
    )
    let byKind = Dictionary(
      uniqueKeysWithValues: bundle.externalArtifacts.map { ($0.kind, $0) })
    let observation: (ManifestEvidenceArtifactKind) throws -> [ManifestObservation] = { kind in
      [try ManifestInspectionFactory.makeObservation(code: kind.rawValue, severity: .info)]
    }
    var payloads: [String: SyntheticManifestReplayPayload] = [:]
    let branchArtifact = try required(byKind[.branchResponse])
    payloads[branchArtifact.sha256.lowercaseHex] = .branch(
      DecodedManifestBranch(
        artifactIdentity: ManifestReplayArtifactIdentity(branchArtifact),
        officialVersion: spec.officialVersion,
        preDownloadVersion: spec.preDownloadVersion,
        observations: try observation(.branchResponse)
      ))
    if spec.hasTarget {
      let buildArtifact = try required(byKind[.buildResponse])
      payloads[buildArtifact.sha256.lowercaseHex] = .build(
        DecodedManifestBuildResponse(
          artifactIdentity: ManifestReplayArtifactIdentity(buildArtifact),
          targetVersion: try required(spec.targetVersion),
          chunkManifestReference: chunkReference,
          observations: try observation(.buildResponse)
        ))
      let chunkArtifact = try required(byKind[.chunkManifest])
      payloads[chunkArtifact.sha256.lowercaseHex] = .chunk(
        DecodedSemanticChunkManifest(
          artifactIdentity: ManifestReplayArtifactIdentity(chunkArtifact),
          candidate: try semanticChunkManifest(),
          observations: try observation(.chunkManifest)
        ))
    }
    if spec.needsPatch {
      let patchArtifact = try required(byKind[.patchResponse])
      let outcome: DecodedManifestPatchOutcome =
        spec.hasLdiff
        ? .ldiff(manifestReference: ldiffReference)
        : .directLdiffUnavailable
      payloads[patchArtifact.sha256.lowercaseHex] = .patch(
        DecodedManifestPatchResponse(
          artifactIdentity: ManifestReplayArtifactIdentity(patchArtifact),
          sourceVersion: try required(spec.sourceVersion),
          targetVersion: try required(spec.targetVersion),
          outcome: outcome,
          observations: try observation(.patchResponse)
        ))
    }
    if spec.hasLdiff {
      let ldiffArtifact = try required(byKind[.diffManifest])
      payloads[ldiffArtifact.sha256.lowercaseHex] = .ldiff(
        DecodedSemanticLdiffPlan(
          artifactIdentity: ManifestReplayArtifactIdentity(ldiffArtifact),
          candidate: try semanticLdiffPlan(
            source: try required(spec.sourceVersion),
            target: try required(spec.targetVersion),
            empty: spec.isEmptyLdiff
          ),
          observations: try observation(.diffManifest)
        ))
    }
    let decoder = SyntheticManifestReplayDecoder(
      artifacts: bundle.externalArtifacts,
      payloads: payloads
    )
    return MaterializerTestFixture(
      bundle: bundle,
      decoder: decoder,
      expectedCalls: spec.expectedCalls
    )
  }

  private static func reference(
    id: String,
    kind: ManifestReferenceKind
  ) throws -> ManifestReferenceDigest {
    try ManifestReferenceDigest.make(
      release: .genshinOfficialCN,
      category: .game,
      manifestID: ManifestReferenceID(id),
      profileRevision: 1,
      kind: kind
    )
  }

  private static func semanticChunkManifest() throws -> SemanticChunkManifest {
    let object = try SemanticChunkObject(
      id: "chunk-object",
      compressedBytes: 3,
      uncompressedBytes: 4,
      uncompressedMD5: String(repeating: "a", count: 32),
      compressedXXHash: 42
    )
    return SemanticChunkManifest(files: [
      SemanticChunkFile(
        path: "game.bin",
        kind: .file,
        installedBytes: 4,
        wholeMD5: String(repeating: "b", count: 32),
        references: [SemanticChunkReference(object: object, fileOffset: 0)]
      )
    ])
  }

  private static func semanticLdiffPlan(
    source: GameVersion,
    target: GameVersion,
    empty: Bool
  ) throws -> SemanticSelectedDiffPlan {
    guard !empty else {
      return SemanticSelectedDiffPlan(
        sourceVersion: source,
        targetVersion: target,
        manifestFileRecordCount: 0,
        selectedFiles: [],
        unselectedFiles: [],
        deletions: []
      )
    }
    let object = try SemanticSelectedPatchObject(
      id: "patch-object", objectBytes: 5, remoteName: "patch-remote")
    let patch = try SemanticSelectedPatchSlice(
      object: object,
      patchOffset: 0,
      patchLength: 5,
      originalBytes: 4,
      originalMD5: String(repeating: "c", count: 32),
      buildID: "build-1",
      originalName: "original.bin"
    )
    return SemanticSelectedDiffPlan(
      sourceVersion: source,
      targetVersion: target,
      manifestFileRecordCount: 1,
      selectedFiles: [
        SemanticSelectedDiffFile(
          path: "game.bin",
          targetBytes: 4,
          targetMD5: String(repeating: "d", count: 32),
          patch: patch
        )
      ],
      unselectedFiles: [],
      deletions: []
    )
  }

  private static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func required<T>(_ value: T?) throws -> T {
    guard let value else { throw ManifestAdapterError.invalidManifest }
    return value
  }
}

enum SyntheticManifestReplayPayload: Equatable, Sendable {
  case branch(DecodedManifestBranch)
  case build(DecodedManifestBuildResponse)
  case chunk(DecodedSemanticChunkManifest)
  case patch(DecodedManifestPatchResponse)
  case ldiff(DecodedSemanticLdiffPlan)
}

final class SyntheticManifestReplayDecoder: ManifestReplaySemanticDecoding,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var payloads: [String: SyntheticManifestReplayPayload]
  private var shaByKind: [ManifestEvidenceArtifactKind: String]
  private var callsStorage: [ManifestEvidenceArtifactKind] = []
  private var failures: [ManifestEvidenceArtifactKind: SyntheticDecoderFailure] = [:]
  private var cancellingKinds = Set<ManifestEvidenceArtifactKind>()

  init(
    artifacts: [ValidatedReplayArtifactData],
    payloads: [String: SyntheticManifestReplayPayload]
  ) {
    shaByKind = Dictionary(
      uniqueKeysWithValues: artifacts.map {
        ($0.kind, $0.sha256.lowercaseHex)
      })
    self.payloads = payloads
  }

  var calls: [ManifestEvidenceArtifactKind] {
    lock.withLock { callsStorage }
  }

  func update(
    _ kind: ManifestEvidenceArtifactKind,
    transform: (SyntheticManifestReplayPayload) throws -> SyntheticManifestReplayPayload
  ) throws {
    try lock.withLock {
      guard let sha = shaByKind[kind], let payload = payloads[sha] else {
        throw ManifestAdapterError.invalidManifest
      }
      payloads[sha] = try transform(payload)
    }
  }

  func fail(at kind: ManifestEvidenceArtifactKind) {
    lock.withLock { failures[kind] = .invalidManifest }
  }

  func throwSchemaDrift(at kind: ManifestEvidenceArtifactKind) {
    lock.withLock { failures[kind] = .schemaDrift }
  }

  func throwUnknownError(at kind: ManifestEvidenceArtifactKind) {
    lock.withLock { failures[kind] = .unknown }
  }

  func cancel(at kind: ManifestEvidenceArtifactKind) {
    lock.withLock { _ = cancellingKinds.insert(kind) }
  }

  func storedPayload(
    for kind: ManifestEvidenceArtifactKind
  ) -> SyntheticManifestReplayPayload? {
    lock.withLock {
      guard let sha = shaByKind[kind] else { return nil }
      return payloads[sha]
    }
  }

  func decodeBranch(
    _ artifact: ValidatedReplayArtifactData,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedManifestBranch {
    try requireScope(scope)
    guard case .branch(let value) = try payload(for: artifact, expected: .branchResponse) else {
      throw ManifestAdapterError.invalidManifest
    }
    return value
  }

  func decodeBuildResponse(
    _ artifact: ValidatedReplayArtifactData,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedManifestBuildResponse {
    try requireScope(scope)
    guard case .build(let value) = try payload(for: artifact, expected: .buildResponse) else {
      throw ManifestAdapterError.invalidManifest
    }
    return value
  }

  func decodeChunkManifest(
    _ artifact: ValidatedReplayArtifactData,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedSemanticChunkManifest {
    try requireScope(scope)
    guard case .chunk(let value) = try payload(for: artifact, expected: .chunkManifest) else {
      throw ManifestAdapterError.invalidManifest
    }
    return value
  }

  func decodePatchResponse(
    _ artifact: ValidatedReplayArtifactData,
    sourceVersion: GameVersion,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedManifestPatchResponse {
    try requireScope(scope)
    guard case .patch(let value) = try payload(for: artifact, expected: .patchResponse) else {
      throw ManifestAdapterError.invalidManifest
    }
    return value
  }

  func decodeLdiffManifest(
    _ artifact: ValidatedReplayArtifactData,
    sourceVersion: GameVersion,
    targetVersion: GameVersion,
    scope: ManifestReplayDecodingScope
  ) throws -> DecodedSemanticLdiffPlan {
    try requireScope(scope)
    guard case .ldiff(let value) = try payload(for: artifact, expected: .diffManifest) else {
      throw ManifestAdapterError.invalidManifest
    }
    return value
  }

  private func requireScope(_ scope: ManifestReplayDecodingScope) throws {
    guard scope.schemaBaseline.value == ManifestProtobufStructuralMapper.requiredSchemaBaseline
    else {
      throw ManifestAdapterError.schemaDrift
    }
  }

  private func payload(
    for artifact: ValidatedReplayArtifactData,
    expected kind: ManifestEvidenceArtifactKind
  ) throws -> SyntheticManifestReplayPayload {
    let state = lock.withLock {
      () -> (
        SyntheticManifestReplayPayload?, SyntheticDecoderFailure?, Bool
      ) in
      callsStorage.append(kind)
      return (
        payloads[artifact.sha256.lowercaseHex],
        failures[kind],
        cancellingKinds.contains(kind)
      )
    }
    if state.2 { withUnsafeCurrentTask { $0?.cancel() } }
    switch state.1 {
    case .invalidManifest: throw ManifestAdapterError.invalidManifest
    case .schemaDrift: throw ManifestAdapterError.schemaDrift
    case .unknown: throw SyntheticDecoderUnknownError()
    case nil: break
    }
    guard artifact.kind == kind, let payload = state.0 else {
      throw ManifestAdapterError.invalidManifest
    }
    return payload
  }
}

private enum SyntheticDecoderFailure {
  case invalidManifest
  case schemaDrift
  case unknown
}

private struct SyntheticDecoderUnknownError: Error {}

private struct MaterializerTestSpec {
  let fixtureID: ManifestFixtureID
  let intentKind: String
  let sourceVersion: GameVersion?
  let officialVersion: GameVersion
  let preDownloadVersion: GameVersion?
  let targetVersion: GameVersion?
  let availability: ManifestAvailability
  let hasTarget: Bool
  let needsPatch: Bool
  let hasLdiff: Bool
  let isEmptyLdiff: Bool
  let bindingKinds: [ManifestEvidenceArtifactKind]
  let expectedCalls: [ManifestEvidenceArtifactKind]

  init(shape: MaterializerTestShape, id: String?) throws {
    let source = try GameVersion("1.0.0")
    let official = try GameVersion("2.0.0")
    let preload = try GameVersion("2.1.0-pre")
    officialVersion = official
    switch shape {
    case .full:
      fixtureID = try ManifestFixtureID(id ?? "materializer-full")
      intentKind = "full"
      sourceVersion = nil
      preDownloadVersion = nil
      targetVersion = official
      availability = .available
      hasTarget = true
      needsPatch = false
      hasLdiff = false
      isEmptyLdiff = false
    case .update, .emptyUpdate:
      fixtureID = try ManifestFixtureID(id ?? "materializer-update")
      intentKind = "update"
      sourceVersion = source
      preDownloadVersion = nil
      targetVersion = official
      availability = .available
      hasTarget = true
      needsPatch = true
      hasLdiff = true
      isEmptyLdiff = shape == .emptyUpdate
    case .preDownloadFull:
      fixtureID = try ManifestFixtureID(id ?? "materializer-preload-full")
      intentKind = "preDownload"
      sourceVersion = nil
      preDownloadVersion = preload
      targetVersion = preload
      availability = .available
      hasTarget = true
      needsPatch = false
      hasLdiff = false
      isEmptyLdiff = false
    case .preDownloadUpdate:
      fixtureID = try ManifestFixtureID(id ?? "materializer-preload-update")
      intentKind = "preDownload"
      sourceVersion = official
      preDownloadVersion = preload
      targetVersion = preload
      availability = .available
      hasTarget = true
      needsPatch = true
      hasLdiff = true
      isEmptyLdiff = false
    case .upToDate:
      fixtureID = try ManifestFixtureID(id ?? "materializer-up-to-date")
      intentKind = "update"
      sourceVersion = official
      preDownloadVersion = nil
      targetVersion = official
      availability = .upToDate
      hasTarget = true
      needsPatch = false
      hasLdiff = false
      isEmptyLdiff = false
    case .unpublished:
      fixtureID = try ManifestFixtureID(id ?? "materializer-unpublished")
      intentKind = "preDownload"
      sourceVersion = nil
      preDownloadVersion = nil
      targetVersion = nil
      availability = .preDownloadNotPublished
      hasTarget = false
      needsPatch = false
      hasLdiff = false
      isEmptyLdiff = false
    case .unavailable:
      fixtureID = try ManifestFixtureID(id ?? "materializer-unavailable")
      intentKind = "update"
      sourceVersion = source
      preDownloadVersion = nil
      targetVersion = official
      availability = .directLdiffUnavailable
      hasTarget = true
      needsPatch = true
      hasLdiff = false
      isEmptyLdiff = false
    }
    var bindings: [ManifestEvidenceArtifactKind] = [.branchResponse]
    if hasTarget { bindings.append(.buildResponse) }
    if needsPatch { bindings.append(.patchResponse) }
    if hasTarget { bindings.append(.chunkManifest) }
    if hasLdiff { bindings.append(.diffManifest) }
    bindingKinds = bindings
    var calls: [ManifestEvidenceArtifactKind] = [.branchResponse]
    if hasTarget { calls += [.buildResponse, .chunkManifest] }
    if needsPatch { calls.append(.patchResponse) }
    if hasLdiff { calls.append(.diffManifest) }
    expectedCalls = calls
  }
}

private struct MaterializerDescriptorDTO: Encodable {
  let schemaVersion: UInt8
  let scope: MaterializerScopeDTO
  let availability: String
  let branches: MaterializerBranchesDTO
  let target: MaterializerTargetDTO?
  let selectedLdiff: MaterializerSelectedLdiffDTO?
  let externalArtifactBindings: [MaterializerBindingDTO]
  let evidenceMetadata: MaterializerEvidenceDTO
  let observations: [MaterializerObservationDTO]
}

private struct MaterializerScopeDTO: Encodable {
  let fixtureID: String
  let release: String
  let intent: MaterializerIntentDTO
  let categories: [String]
}

private struct MaterializerIntentDTO: Encodable {
  let kind: String
  let sourceVersion: String?
}

private struct MaterializerBranchesDTO: Encodable {
  let officialVersion: String
  let preDownloadVersion: String?
}

private struct MaterializerTargetDTO: Encodable {
  let game: MaterializerChunkSummaryDTO
}

private struct MaterializerChunkSummaryDTO: Encodable {
  let fileCount: UInt64
  let directoryCount: UInt64
  let chunkReferenceCount: UInt64
  let uniqueChunkObjectCount: UInt64
  let targetInstalledBytes: UInt64
  let referencedChunkCompressedBytes: UInt64
  let uniqueChunkObjectBytes: UInt64

  static let chunk = MaterializerChunkSummaryDTO(
    fileCount: 1,
    directoryCount: 0,
    chunkReferenceCount: 1,
    uniqueChunkObjectCount: 1,
    targetInstalledBytes: 4,
    referencedChunkCompressedBytes: 3,
    uniqueChunkObjectBytes: 3
  )
}

private struct MaterializerSelectedLdiffDTO: Encodable {
  let game: MaterializerLdiffSummaryDTO
}

private struct MaterializerLdiffSummaryDTO: Encodable {
  let manifestFileRecordCount: UInt64
  let selectedPatchFileCount: UInt64
  let fileRecordsWithoutSelectedPatchCount: UInt64
  let selectedDeletionCount: UInt64
  let uniquePatchObjectCount: UInt64
  let selectedPatchObjectBytes: UInt64

  static let nonempty = MaterializerLdiffSummaryDTO(
    manifestFileRecordCount: 1,
    selectedPatchFileCount: 1,
    fileRecordsWithoutSelectedPatchCount: 0,
    selectedDeletionCount: 0,
    uniquePatchObjectCount: 1,
    selectedPatchObjectBytes: 5
  )
  static let empty = MaterializerLdiffSummaryDTO(
    manifestFileRecordCount: 0,
    selectedPatchFileCount: 0,
    fileRecordsWithoutSelectedPatchCount: 0,
    selectedDeletionCount: 0,
    uniquePatchObjectCount: 0,
    selectedPatchObjectBytes: 0
  )
}

private struct MaterializerBindingDTO: Encodable {
  let kind: String
  let sha256: String
  let byteSize: UInt64
  let manifestReferenceSHA256: String?
}

private struct MaterializerEvidenceDTO: Encodable {
  let profileRevision: UInt64
  let observedAtUnixSeconds: Int64
  let expiresAtUnixSeconds: Int64?
  let schemaBaseline: String
}

private struct MaterializerObservationDTO: Encodable {
  let code: String
  let severity: String
}
