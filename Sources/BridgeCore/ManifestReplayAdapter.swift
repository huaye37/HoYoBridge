struct ManifestReplayCandidate: Equatable, Sendable {
  let fixtureID: ManifestFixtureID
  let expectedRequest: ManifestInspectionRequest
  let inspection: ManifestInspection

  private init(
    fixtureID: ManifestFixtureID,
    expectedRequest: ManifestInspectionRequest,
    inspection: ManifestInspection
  ) {
    self.fixtureID = fixtureID
    self.expectedRequest = expectedRequest
    self.inspection = inspection
  }

  static func make(
    fixtureID: ManifestFixtureID,
    expectedRequest: ManifestInspectionRequest,
    candidate: ManifestInspection
  ) throws -> ManifestReplayCandidate {
    guard case .fixtureOnly(let requestFixtureID) = expectedRequest.cachePolicy,
      requestFixtureID == fixtureID
    else {
      throw ManifestAdapterError.invalidManifest
    }
    let rebuilt = try ManifestReplayInspectionRebuilder.rebuild(
      candidate,
      for: expectedRequest
    )
    guard rebuilt == candidate else {
      throw ManifestAdapterError.invalidManifest
    }
    return ManifestReplayCandidate(
      fixtureID: fixtureID,
      expectedRequest: expectedRequest,
      inspection: rebuilt
    )
  }
}

extension ManifestReplayCandidate: ManifestReplayRedactedValue {}

struct ManifestReplayRegistry: Sendable {
  private let fixtures: [ManifestFixtureID: MaterializedManifestReplayFixture]

  init(_ fixtures: [MaterializedManifestReplayFixture]) throws {
    var indexed: [ManifestFixtureID: MaterializedManifestReplayFixture] = [:]
    indexed.reserveCapacity(fixtures.count)
    for fixture in fixtures {
      guard indexed[fixture.fixtureID] == nil else {
        throw ManifestAdapterError.invalidManifest
      }
      indexed[fixture.fixtureID] = fixture
    }
    self.fixtures = indexed
  }

  func inspection(for request: ManifestInspectionRequest) throws -> ManifestInspection {
    guard case .fixtureOnly(let fixtureID) = request.cachePolicy else {
      throw ManifestAdapterError.missingEndpointEvidence
    }
    guard let fixture = fixtures[fixtureID], fixture.expectedRequest == request else {
      throw ManifestAdapterError.fixtureUnavailable(fixtureID)
    }
    return fixture.inspection
  }
}

struct ManifestReplayAdapter: ManifestAdapter, Sendable {
  private let registry: ManifestReplayRegistry

  init(registry: ManifestReplayRegistry) {
    self.registry = registry
  }

  func inspect(_ request: ManifestInspectionRequest) async throws -> ManifestInspection {
    try Task.checkCancellation()
    let inspection = try registry.inspection(for: request)
    try Task.checkCancellation()
    return inspection
  }
}

private enum ManifestReplayInspectionRebuilder {
  static func rebuild(
    _ candidate: ManifestInspection,
    for request: ManifestInspectionRequest
  ) throws -> ManifestInspection {
    let branches = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: candidate.branches.officialVersion,
      preDownloadVersion: candidate.branches.preDownloadVersion
    )
    let target = try candidate.target.map(rebuildTarget)
    let selectedLdiff = try candidate.selectedLdiff.map(rebuildLdiff)
    var artifactsByKind: [ManifestEvidenceArtifactKind: ManifestEvidenceArtifact] = [:]
    for artifact in candidate.evidence.artifacts {
      guard artifactsByKind[artifact.kind] == nil else {
        throw ManifestAdapterError.invalidManifest
      }
      artifactsByKind[artifact.kind] = artifact
    }
    let expectedKinds = ManifestInspectionFactory.expectedEvidenceArtifactKinds(
      availability: candidate.availability,
      target: target,
      selectedLdiff: selectedLdiff,
      includesFixtureDescriptor: true
    )
    guard artifactsByKind.count == expectedKinds.count else {
      throw ManifestAdapterError.invalidManifest
    }
    let artifacts = try expectedKinds.map { kind in
      guard let artifact = artifactsByKind[kind] else {
        throw ManifestAdapterError.invalidManifest
      }
      return try ManifestInspectionFactory.makeEvidenceArtifact(
        kind: artifact.kind,
        sha256: artifact.sha256.lowercaseHex,
        byteSize: artifact.byteSize
      )
    }
    let evidence = try ManifestInspectionFactory.makeEvidence(
      release: candidate.evidence.release,
      profileRevision: candidate.evidence.profileRevision,
      observedAt: candidate.evidence.observedAt,
      expiresAt: candidate.evidence.expiresAt,
      schemaBaseline: candidate.evidence.schemaBaseline.value,
      artifacts: artifacts
    )
    let observations = try candidate.observations.map {
      try ManifestInspectionFactory.makeObservation(
        code: $0.code,
        severity: $0.severity
      )
    }
    return try ManifestInspectionFactory.makeInspection(
      request: request,
      availability: candidate.availability,
      branches: branches,
      target: target,
      selectedLdiff: selectedLdiff,
      origin: candidate.origin,
      evidence: evidence,
      observations: observations
    )
  }

  private static func rebuildTarget(_ candidate: BuildManifest) throws -> BuildManifest {
    var categories: [ResourceCategory: ChunkManifest] = [:]
    for (category, summary) in candidate.categories {
      let sizes = try ManifestInspectionFactory.makeChunkSizeSummary(
        targetInstalledBytes: summary.sizes.targetInstalledBytes,
        referencedChunkCompressedBytes: summary.sizes.referencedChunkCompressedBytes,
        uniqueChunkObjectBytes: summary.sizes.uniqueChunkObjectBytes
      )
      categories[category] = try ManifestInspectionFactory.makeChunkManifest(
        fileCount: summary.fileCount,
        directoryCount: summary.directoryCount,
        chunkReferenceCount: summary.chunkReferenceCount,
        uniqueChunkObjectCount: summary.uniqueChunkObjectCount,
        sizes: sizes
      )
    }
    return try ManifestInspectionFactory.makeBuildManifest(
      targetVersion: candidate.targetVersion,
      categories: categories
    )
  }

  private static func rebuildLdiff(_ candidate: LdiffSelection) throws -> LdiffSelection {
    var categories: [ResourceCategory: LdiffSelectionSummary] = [:]
    for (category, summary) in candidate.categories {
      categories[category] = try ManifestInspectionFactory.makeLdiffSelectionSummary(
        manifestFileRecordCount: summary.manifestFileRecordCount,
        selectedPatchFileCount: summary.selectedPatchFileCount,
        fileRecordsWithoutSelectedPatchCount: summary.fileRecordsWithoutSelectedPatchCount,
        selectedDeletionCount: summary.selectedDeletionCount,
        uniquePatchObjectCount: summary.uniquePatchObjectCount,
        selectedPatchObjectBytes: summary.selectedPatchObjectBytes
      )
    }
    return try ManifestInspectionFactory.makeLdiffSelection(
      sourceVersion: candidate.sourceVersion,
      targetVersion: candidate.targetVersion,
      categories: categories
    )
  }

}
