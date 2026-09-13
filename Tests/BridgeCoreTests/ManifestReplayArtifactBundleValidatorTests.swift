import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct ManifestReplayArtifactBundleValidatorTests {
  @Test
  func hashesOwnedBytesAndBuildsStableFactoryEvidence() throws {
    let branchBytes = Data("abc".utf8)
    let descriptor = try descriptor(.update, artifactData: [.branchResponse: branchBytes])
    var inputs = artifacts(for: descriptor)
    let branchIndex = try #require(inputs.firstIndex { $0.kind == .branchResponse })
    inputs[branchIndex] = ManifestReplayArtifactData(
      kind: .branchResponse, data: branchBytes)

    let bundle = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor,
      artifacts: Array(inputs.reversed())
    )

    #expect(bundle.externalArtifacts.map(\.kind) == descriptor.expectedArtifactKinds)
    #expect(
      bundle.byteEvidence.artifacts.map(\.kind) == descriptor.expectedArtifactKinds + [
        .fixtureDescriptor
      ])
    let branch = try #require(
      bundle.externalArtifacts.first { $0.kind == .branchResponse })
    #expect(
      branch.sha256.lowercaseHex
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(branch.byteSize == 3)
    #expect(branch.data == Data("abc".utf8))
    #expect(branch.manifestReferenceSHA256 == nil)
    let chunk = try #require(
      bundle.externalArtifacts.first { $0.kind == .chunkManifest })
    let chunkBinding = try #require(
      descriptor.externalArtifactBindings.first { $0.kind == .chunkManifest })
    #expect(chunk.manifestReferenceSHA256 == chunkBinding.manifestReferenceSHA256)
    let descriptorEvidence = try #require(bundle.byteEvidence.artifacts.last)
    #expect(descriptorEvidence.kind == .fixtureDescriptor)
    #expect(descriptorEvidence.sha256.lowercaseHex == descriptor.fixtureDescriptorSHA256)
    #expect(descriptorEvidence.byteSize == descriptor.fixtureDescriptorByteSize)
    let externalBytes = bundle.externalArtifacts.reduce(UInt64(0)) { $0 + $1.byteSize }
    #expect(bundle.totalByteSize == descriptor.fixtureDescriptorByteSize + externalBytes)
    #expect(bundle.byteEvidence.profileRevision == descriptor.profileRevision)
    #expect(bundle.byteEvidence.schemaBaseline == descriptor.schemaBaseline)
  }

  @Test
  func snapshotsDataReferencingMutableStorageBeforeReturn() throws {
    let descriptor = try descriptor(
      .unpublished, artifactData: [.branchResponse: Data("abc".utf8)])
    let mutable = NSMutableData(data: Data("abc".utf8))
    let shared = Data(referencing: mutable)
    let bundle = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor,
      artifacts: [ManifestReplayArtifactData(kind: .branchResponse, data: shared)]
    )

    let mutableBytes = mutable.mutableBytes.assumingMemoryBound(to: UInt8.self)
    mutableBytes[0] = 0x78
    mutableBytes[1] = 0x79
    mutableBytes[2] = 0x7A
    #expect(Data(bytes: mutable.bytes, count: mutable.length) == Data("xyz".utf8))
    let snapshot = try #require(bundle.externalArtifacts.first)
    #expect(snapshot.data == Data("abc".utf8))
    #expect(
      snapshot.sha256.lowercaseHex
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(
      bundle.byteEvidence.artifacts[0].sha256.lowercaseHex
        == snapshot.sha256.lowercaseHex)
  }

  @Test
  func rejectsMissingExtraDuplicateDescriptorAndEmptyArtifacts() throws {
    let unpublishedDescriptor = try descriptor(.unpublished)
    let branch = ManifestReplayArtifactData(
      kind: .branchResponse, data: Data("branch".utf8))
    let invalidInputs: [[ManifestReplayArtifactData]] = [
      [],
      [branch, ManifestReplayArtifactData(kind: .buildResponse, data: Data("build".utf8))],
      [ManifestReplayArtifactData(kind: .fixtureDescriptor, data: Data("fixture".utf8))],
      [ManifestReplayArtifactData(kind: .branchResponse, data: Data())],
    ]
    for invalid in invalidInputs {
      #expect(throws: ManifestReplayArtifactBundleValidationError.invalidBundle) {
        try ManifestReplayArtifactBundleValidator.validate(
          descriptor: unpublishedDescriptor, artifacts: invalid)
      }
    }
    let full = try descriptor(.full)
    let duplicateWithExactCount = [
      ManifestReplayArtifactData(kind: .branchResponse, data: Data("one".utf8)),
      ManifestReplayArtifactData(kind: .branchResponse, data: Data("two".utf8)),
      ManifestReplayArtifactData(kind: .chunkManifest, data: Data("chunk".utf8)),
    ]
    #expect(throws: ManifestReplayArtifactBundleValidationError.invalidBundle) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: full, artifacts: duplicateWithExactCount)
    }
  }

  @Test
  func enforcesKindAndTotalCapsAndRejectsLooserLimits() throws {
    let descriptor = try descriptor(
      .unpublished, artifactData: [.branchResponse: Data("abc".utf8)])
    let threeBytes = [
      ManifestReplayArtifactData(
        kind: .branchResponse, data: Data("abc".utf8),
      )
    ]
    let defaults = ManifestReplayArtifactBundleLimits.default
    #expect(defaults.branchResponseBytes == 1 * 1_024 * 1_024)
    #expect(defaults.buildResponseBytes == 8 * 1_024 * 1_024)
    #expect(defaults.patchResponseBytes == 8 * 1_024 * 1_024)
    #expect(defaults.chunkManifestBytes == 64 * 1_024 * 1_024)
    #expect(defaults.diffManifestBytes == 64 * 1_024 * 1_024)
    #expect(defaults.totalBytes == 128 * 1_024 * 1_024)

    #expect(throws: ManifestReplayArtifactBundleValidationError.oversized) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor, artifacts: threeBytes,
        limits: limits(branch: 2, total: defaults.totalBytes))
    }
    #expect(throws: ManifestReplayArtifactBundleValidationError.oversized) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor, artifacts: threeBytes,
        limits: limits(
          branch: 3,
          total: descriptor.fixtureDescriptorByteSize + 2))
    }
    #expect(throws: ManifestReplayArtifactBundleValidationError.invalidBundle) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor, artifacts: threeBytes,
        limits: limits(
          branch: defaults.branchResponseBytes + 1,
          total: defaults.totalBytes))
    }
    let exactBoundary = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor, artifacts: threeBytes,
      limits: limits(
        branch: 3,
        total: descriptor.fixtureDescriptorByteSize + 3))
    #expect(exactBoundary.externalArtifacts[0].byteSize == 3)
    #expect(exactBoundary.totalByteSize == descriptor.fixtureDescriptorByteSize + 3)
  }

  @Test
  func sameSizeArtifactSwapFailsClosedAgainstDescriptorBinding() throws {
    let firstBytes = Data("abc".utf8)
    let secondBytes = Data("abd".utf8)
    let firstDescriptor = try descriptor(
      .unpublished, artifactData: [.branchResponse: firstBytes])
    let secondDescriptor = try descriptor(
      .unpublished, artifactData: [.branchResponse: secondBytes])
    let first = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: firstDescriptor,
      artifacts: [
        ManifestReplayArtifactData(
          kind: .branchResponse, data: firstBytes,
        )
      ])
    let second = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: secondDescriptor,
      artifacts: [
        ManifestReplayArtifactData(
          kind: .branchResponse, data: secondBytes,
        )
      ])

    #expect(first.externalArtifacts[0].byteSize == second.externalArtifacts[0].byteSize)
    #expect(first.externalArtifacts[0].sha256 != second.externalArtifacts[0].sha256)
    #expect(first.byteEvidence.artifacts[0].sha256 != second.byteEvidence.artifacts[0].sha256)
    #expect(firstDescriptor.fixtureDescriptorSHA256 != secondDescriptor.fixtureDescriptorSHA256)
    #expect(throws: ManifestReplayArtifactBundleValidationError.artifactMismatch) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: firstDescriptor,
        artifacts: [ManifestReplayArtifactData(kind: .branchResponse, data: secondBytes)])
    }
    #expect(throws: ManifestReplayArtifactBundleValidationError.artifactMismatch) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: secondDescriptor,
        artifacts: [ManifestReplayArtifactData(kind: .branchResponse, data: firstBytes)])
    }
  }

  @Test
  func rejectsDeclaredSizeMismatchBeforeHashing() throws {
    let descriptor = try descriptor(
      .unpublished, artifactData: [.branchResponse: Data("abc".utf8)])
    #expect(throws: ManifestReplayArtifactBundleValidationError.artifactMismatch) {
      try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor,
        artifacts: [
          ManifestReplayArtifactData(kind: .branchResponse, data: Data("ab".utf8))
        ])
    }
  }

  @Test
  func sameBytesWithDifferentManifestReferenceRemainDistinctDescriptorClaims() throws {
    // This byte-only layer carries the claim; a future materializer must rederive it.
    let firstDescriptor = try descriptor(.full)
    let secondDescriptor = try descriptor(
      .full,
      manifestReferences: [.chunkManifest: String(repeating: "e", count: 64)]
    )
    let inputs = artifacts(for: firstDescriptor)
    let first = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: firstDescriptor, artifacts: inputs)
    let second = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: secondDescriptor, artifacts: inputs)
    let firstChunk = try #require(
      first.externalArtifacts.first { $0.kind == .chunkManifest })
    let secondChunk = try #require(
      second.externalArtifacts.first { $0.kind == .chunkManifest })

    #expect(firstChunk.data == secondChunk.data)
    #expect(firstChunk.sha256 == secondChunk.sha256)
    #expect(firstChunk.manifestReferenceSHA256 != secondChunk.manifestReferenceSHA256)
    #expect(
      firstDescriptor.fixtureDescriptorSHA256
        != secondDescriptor.fixtureDescriptorSHA256)
    #expect(first.byteEvidence.artifacts.dropLast() == second.byteEvidence.artifacts.dropLast())
    #expect(first.byteEvidence.artifacts.last != second.byteEvidence.artifacts.last)
  }

  @Test
  func crossChunkDigestMatchesCryptoKitOneShot() throws {
    let data = Data(repeating: 0xA5, count: 64 * 1_024 + 1)
    let descriptor = try descriptor(.unpublished, artifactData: [.branchResponse: data])
    let bundle = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor,
      artifacts: [ManifestReplayArtifactData(kind: .branchResponse, data: data)])
    let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

    #expect(bundle.externalArtifacts[0].data == data)
    #expect(bundle.externalArtifacts[0].sha256.lowercaseHex == expected)
    #expect(bundle.byteEvidence.artifacts[0].sha256.lowercaseHex == expected)
  }

  @Test
  func validatesRepresentativeExactKindShapes() throws {
    for shape in [DescriptorShape.unpublished, .full, .update, .directUnavailable] {
      let descriptor = try descriptor(shape)
      let bundle = try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor,
        artifacts: Array(artifacts(for: descriptor).reversed())
      )
      #expect(bundle.externalArtifacts.map(\.kind) == descriptor.expectedArtifactKinds)
      #expect(bundle.byteEvidence.artifacts.last?.kind == .fixtureDescriptor)
    }
  }

  @Test
  func replaysEmptySelectedLdiffAcrossDescriptorAndBundle() async throws {
    let fixture = try MaterializerTestFixture.make(.emptyUpdate, id: "bundle-empty-update")
    let descriptor = fixture.bundle.descriptor
    #expect(
      descriptor.expectedArtifactKinds == [
        .branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest,
      ])
    let materialized = try ManifestReplayMaterializer.materialize(
      fixture.bundle, using: fixture.decoder)
    let adapter = ManifestReplayAdapter(registry: try ManifestReplayRegistry([materialized]))
    let replayed = try await adapter.inspect(descriptor.expectedRequest)
    let summary = try #require(replayed.selectedLdiff?.categories[.game])
    #expect(summary.manifestFileRecordCount == 0)
    #expect(summary.selectedPatchFileCount == 0)
    #expect(summary.fileRecordsWithoutSelectedPatchCount == 0)
    #expect(summary.selectedDeletionCount == 0)
    #expect(summary.uniquePatchObjectCount == 0)
    #expect(summary.selectedPatchObjectBytes == 0)
  }

  @Test
  func honorsCancellationAndConcurrentValidation() async throws {
    let kinds: [ManifestEvidenceArtifactKind] = [
      .branchResponse, .buildResponse, .chunkManifest,
    ]
    let dataByKind = Dictionary(
      uniqueKeysWithValues: kinds.map {
        ($0, Data(repeating: 0x61, count: 128 * 1_024))
      })
    let descriptor = try descriptor(.full, artifactData: dataByKind)
    let inputs = artifacts(for: descriptor, artifactData: dataByKind)
    let cancelled = Task { () throws -> ValidatedReplayArtifactBundle in
      withUnsafeCurrentTask { $0?.cancel() }
      return try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor, artifacts: inputs)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let expected = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor, artifacts: inputs)
    let values = try await withThrowingTaskGroup(
      of: ValidatedReplayArtifactBundle.self,
      returning: [ValidatedReplayArtifactBundle].self
    ) { group in
      for _ in 0..<16 {
        group.addTask {
          try ManifestReplayArtifactBundleValidator.validate(
            descriptor: descriptor, artifacts: inputs)
        }
      }
      var values: [ValidatedReplayArtifactBundle] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(values.allSatisfy { $0 == expected })
  }

  @Test
  func bundleSurfaceRemainsByteOnlyAndNondecodable() throws {
    let descriptor = try descriptor(.unpublished)
    let bundle = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor, artifacts: artifacts(for: descriptor))
    let labels = Mirror(reflecting: bundle).children.compactMap(\.label)
      .map { $0.lowercased() }
    for forbidden in ["inspection", "registry", "materialize", "semantic"] {
      #expect(!labels.contains(where: { $0.contains(forbidden) }))
    }
    #expect(!isDecodable(ManifestReplayArtifactData.self))
    #expect(!isDecodable(ValidatedReplayArtifactData.self))
    #expect(!isDecodable(ValidatedReplayArtifactBundle.self))
  }

  @Test
  func descriptionsAndMirrorsRedactCallerAndSnapshotBytes() throws {
    let canary = "manifest-secret-canary"
    let input = ManifestReplayArtifactData(
      kind: .branchResponse, data: Data(canary.utf8))
    let descriptor = try descriptor(
      .unpublished, artifactData: [.branchResponse: Data(canary.utf8)])
    let bundle = try ManifestReplayArtifactBundleValidator.validate(
      descriptor: descriptor, artifacts: [input])
    let values: [Any] = [input, bundle.externalArtifacts[0], bundle]

    for value in values {
      var dumped = ""
      dump(value, to: &dumped)
      #expect(!dumped.contains(canary))
      #expect(!String(describing: value).contains(canary))
      #expect(!String(reflecting: value).contains(canary))
      #expect(Mirror(reflecting: value).children.first?.label == "redacted")
    }
  }

  private func descriptor(
    _ shape: DescriptorShape,
    artifactData: [ManifestEvidenceArtifactKind: Data] = [:],
    manifestReferences: [ManifestEvidenceArtifactKind: String] = [:]
  ) throws -> ValidatedReplayDescriptor {
    var value: BundleTestDescriptor
    switch shape {
    case .unpublished:
      value = descriptorValue(
        id: "unpublished", intent: .init(kind: "preDownload", sourceVersion: nil),
        availability: "preDownloadNotPublished", target: nil, selectedLdiff: nil)
    case .full:
      value = descriptorValue(
        id: "full", intent: .init(kind: "full", sourceVersion: nil),
        availability: "available", target: targetSummary(), selectedLdiff: nil)
    case .update:
      value = descriptorValue(
        id: "update", intent: .init(kind: "update", sourceVersion: "1.0.0"),
        availability: "available", target: targetSummary(),
        selectedLdiff: ldiffSummary())
    case .emptyUpdate:
      value = descriptorValue(
        id: "empty-update", intent: .init(kind: "update", sourceVersion: "1.0.0"),
        availability: "available", target: targetSummary(),
        selectedLdiff: ldiffSummary(empty: true))
    case .directUnavailable:
      value = descriptorValue(
        id: "direct", intent: .init(kind: "update", sourceVersion: "1.0.0"),
        availability: "directLdiffUnavailable", target: targetSummary(), selectedLdiff: nil)
    }
    let kinds = expectedKinds(
      availability: value.availability,
      target: value.target,
      selectedLdiff: value.selectedLdiff
    )
    value.externalArtifactBindings = kinds.map { kind in
      let data = artifactData[kind] ?? Data(kind.rawValue.utf8)
      return BundleTestArtifactBinding(
        kind: kind.rawValue,
        sha256: sha256(data),
        byteSize: UInt64(data.count),
        manifestReferenceSHA256: manifestReferences[kind] ?? defaultReference(for: kind)
      )
    }
    return try ManifestReplayDescriptorDecoder.decode(try canonicalData(value))
  }

  private func expectedKinds(
    availability: String,
    target: BundleTestTarget?,
    selectedLdiff: BundleTestSelectedLdiff?
  ) -> [ManifestEvidenceArtifactKind] {
    var kinds: [ManifestEvidenceArtifactKind] = [.branchResponse]
    guard target != nil else { return kinds }
    kinds.append(.buildResponse)
    if selectedLdiff != nil || availability == "directLdiffUnavailable" {
      kinds.append(.patchResponse)
    }
    kinds.append(.chunkManifest)
    if selectedLdiff != nil { kinds.append(.diffManifest) }
    return kinds
  }

  private func defaultReference(for kind: ManifestEvidenceArtifactKind) -> String? {
    switch kind {
    case .chunkManifest: String(repeating: "c", count: 64)
    case .diffManifest: String(repeating: "d", count: 64)
    default: nil
    }
  }

  private func descriptorValue(
    id: String,
    intent: BundleTestIntent,
    availability: String,
    target: BundleTestTarget?,
    selectedLdiff: BundleTestSelectedLdiff?
  ) -> BundleTestDescriptor {
    BundleTestDescriptor(
      schemaVersion: 3,
      scope: BundleTestScope(
        fixtureID: id, release: "genshinOfficialCN", intent: intent,
        categories: ["game"]),
      availability: availability,
      branches: BundleTestBranches(
        officialVersion: "2.0.0", preDownloadVersion: nil),
      target: target,
      selectedLdiff: selectedLdiff,
      externalArtifactBindings: [],
      evidenceMetadata: BundleTestEvidence(
        profileRevision: 1, observedAtUnixSeconds: 1,
        expiresAtUnixSeconds: 2, schemaBaseline: "schema-1"),
      observations: []
    )
  }

  private func targetSummary() -> BundleTestTarget {
    BundleTestTarget(
      game: BundleTestChunkSummary(
        fileCount: 2, directoryCount: 1, chunkReferenceCount: 3,
        uniqueChunkObjectCount: 2, targetInstalledBytes: 1_000,
        referencedChunkCompressedBytes: 800, uniqueChunkObjectBytes: 600))
  }

  private func ldiffSummary(empty: Bool = false) -> BundleTestSelectedLdiff {
    BundleTestSelectedLdiff(
      game: BundleTestLdiffSelectionSummary(
        manifestFileRecordCount: empty ? 0 : 2,
        selectedPatchFileCount: empty ? 0 : 1,
        fileRecordsWithoutSelectedPatchCount: empty ? 0 : 1,
        selectedDeletionCount: empty ? 0 : 1,
        uniquePatchObjectCount: empty ? 0 : 1,
        selectedPatchObjectBytes: empty ? 0 : 100))
  }

  private func artifacts(
    for descriptor: ValidatedReplayDescriptor,
    artifactData: [ManifestEvidenceArtifactKind: Data] = [:]
  ) -> [ManifestReplayArtifactData] {
    descriptor.expectedArtifactKinds.map {
      ManifestReplayArtifactData(
        kind: $0,
        data: artifactData[$0] ?? Data($0.rawValue.utf8)
      )
    }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func limits(
    branch: UInt64,
    total: UInt64
  ) -> ManifestReplayArtifactBundleLimits {
    let defaults = ManifestReplayArtifactBundleLimits.default
    return ManifestReplayArtifactBundleLimits(
      branchResponseBytes: branch,
      buildResponseBytes: defaults.buildResponseBytes,
      patchResponseBytes: defaults.patchResponseBytes,
      chunkManifestBytes: defaults.chunkManifestBytes,
      diffManifestBytes: defaults.diffManifestBytes,
      totalBytes: total
    )
  }

  private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  private func isDecodable<T>(_ type: T.Type) -> Bool {
    type is any Decodable.Type
  }
}

private enum DescriptorShape {
  case unpublished
  case full
  case update
  case emptyUpdate
  case directUnavailable
}

private struct BundleTestDescriptor: Encodable {
  let schemaVersion: UInt8
  let scope: BundleTestScope
  let availability: String
  let branches: BundleTestBranches
  let target: BundleTestTarget?
  let selectedLdiff: BundleTestSelectedLdiff?
  var externalArtifactBindings: [BundleTestArtifactBinding]
  let evidenceMetadata: BundleTestEvidence
  let observations: [BundleTestObservation]
}

private struct BundleTestArtifactBinding: Encodable {
  let kind: String
  let sha256: String
  let byteSize: UInt64
  let manifestReferenceSHA256: String?
}

private struct BundleTestScope: Encodable {
  let fixtureID: String
  let release: String
  let intent: BundleTestIntent
  let categories: [String]
}

private struct BundleTestIntent: Encodable {
  let kind: String
  let sourceVersion: String?
}

private struct BundleTestBranches: Encodable {
  let officialVersion: String
  let preDownloadVersion: String?
}

private struct BundleTestTarget: Encodable {
  let game: BundleTestChunkSummary
}

private struct BundleTestChunkSummary: Encodable {
  let fileCount: UInt64
  let directoryCount: UInt64
  let chunkReferenceCount: UInt64
  let uniqueChunkObjectCount: UInt64
  let targetInstalledBytes: UInt64
  let referencedChunkCompressedBytes: UInt64
  let uniqueChunkObjectBytes: UInt64
}

private struct BundleTestSelectedLdiff: Encodable {
  let game: BundleTestLdiffSelectionSummary
}

private struct BundleTestLdiffSelectionSummary: Encodable {
  let manifestFileRecordCount: UInt64
  let selectedPatchFileCount: UInt64
  let fileRecordsWithoutSelectedPatchCount: UInt64
  let selectedDeletionCount: UInt64
  let uniquePatchObjectCount: UInt64
  let selectedPatchObjectBytes: UInt64
}

private struct BundleTestEvidence: Encodable {
  let profileRevision: UInt64
  let observedAtUnixSeconds: Int64
  let expiresAtUnixSeconds: Int64?
  let schemaBaseline: String
}

private struct BundleTestObservation: Encodable {
  let code: String
  let severity: String
}
