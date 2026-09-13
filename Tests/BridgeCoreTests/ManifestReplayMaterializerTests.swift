import Foundation
import Testing

@testable import BridgeCore

struct ManifestReplayMaterializerTests {
  @Test
  func materializesSevenControlFlowShapesAndEmptyLdiffInActualOrder() async throws {
    let shapes: [MaterializerTestShape] = [
      .full, .update, .preDownloadFull, .preDownloadUpdate,
      .upToDate, .unpublished, .unavailable, .emptyUpdate,
    ]
    for (index, shape) in shapes.enumerated() {
      let fixture = try MaterializerTestFixture.make(shape, id: "shape-\(index)")
      let materialized = try ManifestReplayMaterializer.materialize(
        fixture.bundle,
        using: fixture.decoder
      )
      #expect(fixture.decoder.calls == fixture.expectedCalls)
      #expect(materialized.fixtureID == fixture.bundle.descriptor.fixtureID)
      #expect(materialized.expectedRequest == fixture.bundle.descriptor.expectedRequest)
      #expect(materialized.inspection.availability == fixture.bundle.descriptor.availability)
      #expect(materialized.inspection.branches == fixture.bundle.descriptor.branches)
      #expect(materialized.inspection.target == fixture.bundle.descriptor.target)
      #expect(materialized.inspection.selectedLdiff == fixture.bundle.descriptor.selectedLdiff)
      #expect(materialized.inspection.evidence == fixture.bundle.byteEvidence)

      let registry = try ManifestReplayRegistry([materialized])
      let adapter = ManifestReplayAdapter(registry: registry)
      #expect(
        try await adapter.inspect(materialized.expectedRequest)
          == materialized.inspection)
    }
  }

  @Test
  func rejectsIdentityReferenceOutcomeAndSummaryMismatches() throws {
    let identityFixture = try MaterializerTestFixture.make(.update, id: "identity")
    let branch = try artifact(.branchResponse, in: identityFixture.bundle)
    let build = try artifact(.buildResponse, in: identityFixture.bundle)
    try identityFixture.decoder.update(.branchResponse) { payload in
      guard case .branch(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .branch(
        DecodedManifestBranch(
          artifactIdentity: ManifestReplayArtifactIdentity(build),
          officialVersion: value.officialVersion,
          preDownloadVersion: value.preDownloadVersion,
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        identityFixture.bundle, using: identityFixture.decoder)
    }
    #expect(identityFixture.decoder.calls == [.branchResponse])
    #expect(ManifestReplayArtifactIdentity(branch) != ManifestReplayArtifactIdentity(build))

    let branchControl = try MaterializerTestFixture.make(.update, id: "branch-control")
    guard case .update(let requestedSource) = branchControl.bundle.descriptor.expectedRequest.intent
    else {
      throw ManifestAdapterError.invalidManifest
    }
    try branchControl.decoder.update(.branchResponse) { payload in
      guard case .branch(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .branch(
        DecodedManifestBranch(
          artifactIdentity: value.artifactIdentity,
          officialVersion: requestedSource,
          preDownloadVersion: value.preDownloadVersion,
          observations: value.observations
        ))
    }
    try branchControl.decoder.update(.buildResponse) { payload in
      guard case .build(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .build(
        DecodedManifestBuildResponse(
          artifactIdentity: value.artifactIdentity,
          targetVersion: requestedSource,
          chunkManifestReference: value.chunkManifestReference,
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        branchControl.bundle, using: branchControl.decoder)
    }
    #expect(
      branchControl.decoder.calls == [.branchResponse, .buildResponse, .chunkManifest])

    let buildReference = try MaterializerTestFixture.make(.full, id: "build-ref")
    try buildReference.decoder.update(.buildResponse) { payload in
      guard case .build(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .build(
        DecodedManifestBuildResponse(
          artifactIdentity: value.artifactIdentity,
          targetVersion: value.targetVersion,
          chunkManifestReference: try ManifestReferenceDigest.parseLowercaseHex(
            String(repeating: "f", count: 64)),
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        buildReference.bundle, using: buildReference.decoder)
    }
    #expect(buildReference.decoder.calls == [.branchResponse, .buildResponse])

    let patchOutcome = try MaterializerTestFixture.make(.update, id: "patch-outcome")
    try patchOutcome.decoder.update(.patchResponse) { payload in
      guard case .patch(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .patch(
        DecodedManifestPatchResponse(
          artifactIdentity: value.artifactIdentity,
          sourceVersion: value.sourceVersion,
          targetVersion: value.targetVersion,
          outcome: .directLdiffUnavailable,
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        patchOutcome.bundle, using: patchOutcome.decoder)
    }
    #expect(
      patchOutcome.decoder.calls
        == [.branchResponse, .buildResponse, .chunkManifest, .patchResponse])

    let patchSource = try MaterializerTestFixture.make(.update, id: "patch-source")
    try patchSource.decoder.update(.patchResponse) { payload in
      guard case .patch(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .patch(
        DecodedManifestPatchResponse(
          artifactIdentity: value.artifactIdentity,
          sourceVersion: value.targetVersion,
          targetVersion: value.targetVersion,
          outcome: value.outcome,
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        patchSource.bundle, using: patchSource.decoder)
    }
    #expect(
      patchSource.decoder.calls
        == [.branchResponse, .buildResponse, .chunkManifest, .patchResponse])

    let summary = try MaterializerTestFixture.make(.full, id: "summary")
    try summary.decoder.update(.chunkManifest) { payload in
      guard case .chunk(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      let object = try SemanticChunkObject(
        id: "other-object", compressedBytes: 2, uncompressedBytes: 4,
        uncompressedMD5: String(repeating: "a", count: 32),
        compressedXXHash: 42)
      let changed = SemanticChunkManifest(files: [
        SemanticChunkFile(
          path: "game.bin", kind: .file, installedBytes: 4,
          wholeMD5: String(repeating: "b", count: 32),
          references: [SemanticChunkReference(object: object, fileOffset: 0)])
      ])
      return .chunk(
        DecodedSemanticChunkManifest(
          artifactIdentity: value.artifactIdentity,
          candidate: changed,
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(summary.bundle, using: summary.decoder)
    }

    let ldiffSummary = try MaterializerTestFixture.make(.update, id: "ldiff-summary")
    try ldiffSummary.decoder.update(.diffManifest) { payload in
      guard case .ldiff(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      let empty = SemanticSelectedDiffPlan(
        sourceVersion: value.candidate.sourceVersion,
        targetVersion: value.candidate.targetVersion,
        manifestFileRecordCount: 0,
        selectedFiles: [],
        unselectedFiles: [],
        deletions: []
      )
      return .ldiff(
        DecodedSemanticLdiffPlan(
          artifactIdentity: value.artifactIdentity,
          candidate: empty,
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        ldiffSummary.bundle, using: ldiffSummary.decoder)
    }
  }

  @Test
  func rejectsLdiffReferenceAndObservationMismatchOrDuplication() throws {
    let reference = try MaterializerTestFixture.make(.update, id: "ldiff-ref")
    try reference.decoder.update(.patchResponse) { payload in
      guard case .patch(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .patch(
        DecodedManifestPatchResponse(
          artifactIdentity: value.artifactIdentity,
          sourceVersion: value.sourceVersion,
          targetVersion: value.targetVersion,
          outcome: .ldiff(
            manifestReference: try ManifestReferenceDigest.parseLowercaseHex(
              String(repeating: "e", count: 64))),
          observations: value.observations
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(reference.bundle, using: reference.decoder)
    }
    #expect(
      reference.decoder.calls
        == [.branchResponse, .buildResponse, .chunkManifest, .patchResponse])

    let missing = try MaterializerTestFixture.make(.full, id: "observation-missing")
    try missing.decoder.update(.chunkManifest) { payload in
      guard case .chunk(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .chunk(
        DecodedSemanticChunkManifest(
          artifactIdentity: value.artifactIdentity,
          candidate: value.candidate,
          observations: []
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(missing.bundle, using: missing.decoder)
    }

    let duplicate = try MaterializerTestFixture.make(.full, id: "observation-duplicate")
    let duplicateObservation = try ManifestInspectionFactory.makeObservation(
      code: ManifestEvidenceArtifactKind.branchResponse.rawValue,
      severity: .info)
    try duplicate.decoder.update(.buildResponse) { payload in
      guard case .build(let value) = payload else {
        throw ManifestAdapterError.invalidManifest
      }
      return .build(
        DecodedManifestBuildResponse(
          artifactIdentity: value.artifactIdentity,
          targetVersion: value.targetVersion,
          chunkManifestReference: value.chunkManifestReference,
          observations: [duplicateObservation]
        ))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(duplicate.bundle, using: duplicate.decoder)
    }
    #expect(duplicate.decoder.calls == [.branchResponse, .buildResponse])
  }

  @Test
  func sameSizeCrossBundleDecoderFailsAtFirstSHAKey() throws {
    let first = try MaterializerTestFixture.make(.full, id: "same-aa")
    let second = try MaterializerTestFixture.make(.full, id: "same-bb")
    let firstBranch = try artifact(.branchResponse, in: first.bundle)
    let secondBranch = try artifact(.branchResponse, in: second.bundle)
    #expect(firstBranch.byteSize == secondBranch.byteSize)
    #expect(firstBranch.sha256 != secondBranch.sha256)

    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(second.bundle, using: first.decoder)
    }
    #expect(first.decoder.calls == [.branchResponse])
  }

  @Test
  func failsFastAtEveryStageWithoutIssuingCapability() throws {
    let stages: [ManifestEvidenceArtifactKind] = [
      .branchResponse, .buildResponse, .chunkManifest, .patchResponse, .diffManifest,
    ]
    for (index, stage) in stages.enumerated() {
      let fixture = try MaterializerTestFixture.make(.update, id: "fail-\(index)")
      fixture.decoder.fail(at: stage)
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try ManifestReplayMaterializer.materialize(fixture.bundle, using: fixture.decoder)
      }
      let expectedPrefix = Array(fixture.expectedCalls.prefix(index + 1))
      #expect(fixture.decoder.calls == expectedPrefix)
    }
  }

  @Test
  func preservesSchemaDriftAndNormalizesUnknownDecoderErrors() throws {
    let schemaDrift = try MaterializerTestFixture.make(.full, id: "schema-drift")
    schemaDrift.decoder.throwSchemaDrift(at: .buildResponse)
    #expect(throws: ManifestAdapterError.schemaDrift) {
      try ManifestReplayMaterializer.materialize(
        schemaDrift.bundle, using: schemaDrift.decoder)
    }
    #expect(schemaDrift.decoder.calls == [.branchResponse, .buildResponse])

    let unknown = try MaterializerTestFixture.make(.full, id: "unknown-error")
    unknown.decoder.throwUnknownError(at: .buildResponse)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayMaterializer.materialize(
        unknown.bundle, using: unknown.decoder)
    }
    #expect(unknown.decoder.calls == [.branchResponse, .buildResponse])
  }

  @Test
  func honorsPreCancelledAndMidStageCancellation() async throws {
    let preCancelled = try MaterializerTestFixture.make(.full, id: "cancel-before")
    let task = Task { () throws -> MaterializedManifestReplayFixture in
      withUnsafeCurrentTask { $0?.cancel() }
      return try ManifestReplayMaterializer.materialize(
        preCancelled.bundle, using: preCancelled.decoder)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(preCancelled.decoder.calls.isEmpty)

    let midStage = try MaterializerTestFixture.make(.update, id: "cancel-middle")
    midStage.decoder.cancel(at: .chunkManifest)
    let middleTask = Task { () throws -> MaterializedManifestReplayFixture in
      try ManifestReplayMaterializer.materialize(midStage.bundle, using: midStage.decoder)
    }
    await #expect(throws: CancellationError.self) { try await middleTask.value }
    #expect(
      midStage.decoder.calls == [.branchResponse, .buildResponse, .chunkManifest])
  }

  @Test
  func supportsConcurrentMaterializationAndRedactsSemanticCanaries() async throws {
    let fixture = try MaterializerTestFixture.make(.update, id: "concurrent-materialize")
    let values = try await withThrowingTaskGroup(
      of: MaterializedManifestReplayFixture.self,
      returning: [MaterializedManifestReplayFixture].self
    ) { group in
      for _ in 0..<16 {
        group.addTask {
          try ManifestReplayMaterializer.materialize(
            fixture.bundle, using: fixture.decoder)
        }
      }
      var values: [MaterializedManifestReplayFixture] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(values.allSatisfy { $0 == values[0] })
    #expect(fixture.decoder.calls.count == fixture.expectedCalls.count * 16)

    let canary = "semantic-secret-canary"
    let branchArtifact = try artifact(.branchResponse, in: fixture.bundle)
    let observation = try ManifestInspectionFactory.makeObservation(
      code: "safe-code", severity: .info)
    let branch = DecodedManifestBranch(
      artifactIdentity: ManifestReplayArtifactIdentity(branchArtifact),
      officialVersion: try GameVersion(canary),
      preDownloadVersion: nil,
      observations: [observation]
    )
    let candidate = try ManifestReplayCandidate.make(
      fixtureID: values[0].fixtureID,
      expectedRequest: values[0].expectedRequest,
      candidate: values[0].inspection
    )
    let valuesToInspect: [Any] =
      [
        ManifestReplayArtifactIdentity(branchArtifact), branch,
        DecodedManifestPatchOutcome.directLdiffUnavailable,
        values[0], candidate,
      ]
      + fixture.expectedCalls.compactMap { kind -> Any? in
        guard let payload = fixture.decoder.storedPayload(for: kind) else { return nil }
        switch payload {
        case .branch(let value): return value
        case .build(let value): return value
        case .chunk(let value): return value
        case .patch(let value): return value
        case .ldiff(let value): return value
        }
      }
    for value in valuesToInspect {
      var dumped = ""
      dump(value, to: &dumped)
      #expect(!dumped.contains(canary))
      #expect(!String(describing: value).contains(canary))
      #expect(!String(reflecting: value).contains(canary))
      #expect(Mirror(reflecting: value).children.first?.label == "redacted")
    }
  }

  private func artifact(
    _ kind: ManifestEvidenceArtifactKind,
    in bundle: ValidatedReplayArtifactBundle
  ) throws -> ValidatedReplayArtifactData {
    guard let artifact = bundle.externalArtifacts.first(where: { $0.kind == kind }) else {
      throw ManifestAdapterError.invalidManifest
    }
    return artifact
  }
}
