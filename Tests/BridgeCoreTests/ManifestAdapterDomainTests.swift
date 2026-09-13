import Foundation
import Testing

@testable import BridgeCore

struct ManifestAdapterDomainTests {
  @Test
  func validatesOpaqueGameVersions() throws {
    #expect(try GameVersion(".").value == ".")
    #expect(try GameVersion("v1-cn_hotfix").value == "v1-cn_hotfix")
    for invalid in ["", " v1", "v1 ", "e\u{301}", "v1\n", String(repeating: "a", count: 129)] {
      #expect(throws: ManifestAdapterError.invalidRequest) { try GameVersion(invalid) }
    }
  }

  @Test
  func validatesFixtureCacheAndRequestBoundaries() throws {
    let fixture = try ManifestFixtureID("fixture-cn_01.json")
    #expect(fixture.value == "fixture-cn_01.json")
    for invalid in ["", ".", "..", "a/b", "a:b", "中文", String(repeating: "a", count: 129)] {
      #expect(throws: ManifestAdapterError.invalidRequest) { try ManifestFixtureID(invalid) }
    }
    #expect(throws: ManifestAdapterError.invalidRequest) {
      try ManifestInspectionRequest(
        release: .genshinOfficialCN, intent: .full, categories: [],
        cachePolicy: .reloadIgnoringCache)
    }
    #expect(throws: ManifestAdapterError.invalidRequest) {
      try ManifestInspectionRequest(
        release: .genshinOfficialCN, intent: .full, categories: [.game],
        cachePolicy: .freshCache(maxAgeSeconds: 0))
    }
    _ = try request(.full, policy: .fixtureOnly(id: fixture))
    _ = try request(.full, policy: .freshCache(maxAgeSeconds: 1))
    _ = try request(.preDownload(from: nil), policy: .reloadIgnoringCache)
  }

  @Test
  func validatesHashEvidenceAndSummaryCoherence() throws {
    let artifact = try ManifestInspectionFactory.makeEvidenceArtifact(
      kind: .branchResponse,
      sha256: String(repeating: "A", count: 64),
      byteSize: 10
    )
    #expect(artifact.sha256.lowercaseHex == String(repeating: "a", count: 64))
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeEvidenceArtifact(
        kind: .buildResponse, sha256: "bad", byteSize: 1)
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeEvidenceArtifact(
        kind: .buildResponse, sha256: String(repeating: "b", count: 64), byteSize: 0)
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeEvidence(
        release: .genshinOfficialCN, profileRevision: 1,
        observedAt: Date(timeIntervalSince1970: 1), expiresAt: nil,
        schemaBaseline: "schema-1", artifacts: [artifact, artifact])
    }

    let chunkSizes = try ManifestInspectionFactory.makeChunkSizeSummary(
      targetInstalledBytes: 1_000,
      referencedChunkCompressedBytes: 800,
      uniqueChunkObjectBytes: 600
    )
    _ = try ManifestInspectionFactory.makeChunkManifest(
      fileCount: 2, directoryCount: 1, chunkReferenceCount: 3,
      uniqueChunkObjectCount: 2, sizes: chunkSizes)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeChunkManifest(
        fileCount: 2, directoryCount: 0, chunkReferenceCount: 0,
        uniqueChunkObjectCount: 1, sizes: chunkSizes)
    }
    let incoherentZeroReferences = try ManifestInspectionFactory.makeChunkSizeSummary(
      targetInstalledBytes: 1_000,
      referencedChunkCompressedBytes: 10,
      uniqueChunkObjectBytes: 10
    )
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeChunkManifest(
        fileCount: 1, directoryCount: 0, chunkReferenceCount: 0,
        uniqueChunkObjectCount: 0, sizes: incoherentZeroReferences)
    }
    _ = try ManifestInspectionFactory.makeLdiffSelectionSummary(
      manifestFileRecordCount: 0, selectedPatchFileCount: 0,
      fileRecordsWithoutSelectedPatchCount: 0, selectedDeletionCount: 2,
      uniquePatchObjectCount: 0, selectedPatchObjectBytes: 0)
    _ = try ManifestInspectionFactory.makeLdiffSelectionSummary(
      manifestFileRecordCount: 99_999, selectedPatchFileCount: 0,
      fileRecordsWithoutSelectedPatchCount: 99_999, selectedDeletionCount: 1,
      uniquePatchObjectCount: 0, selectedPatchObjectBytes: 0)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeLdiffSelectionSummary(
        manifestFileRecordCount: 1, selectedPatchFileCount: 0,
        fileRecordsWithoutSelectedPatchCount: 0, selectedDeletionCount: 0,
        uniquePatchObjectCount: 0, selectedPatchObjectBytes: 0)
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeLdiffSelectionSummary(
        manifestFileRecordCount: 100_000, selectedPatchFileCount: 0,
        fileRecordsWithoutSelectedPatchCount: 100_000, selectedDeletionCount: 1,
        uniquePatchObjectCount: 0, selectedPatchObjectBytes: 0)
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeLdiffSelectionSummary(
        manifestFileRecordCount: .max, selectedPatchFileCount: 0,
        fileRecordsWithoutSelectedPatchCount: .max, selectedDeletionCount: 1,
        uniquePatchObjectCount: 0, selectedPatchObjectBytes: 0)
    }
  }

  @Test
  func factoryBuildsAvailableFullAndUpdateInspections() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let branch = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: target,
      preDownloadVersion: nil
    )
    let build = try makeBuild(target)
    let full = try ManifestInspectionFactory.makeInspection(
      request: request(.full), availability: .available, branches: branch,
      target: build, selectedLdiff: nil, origin: .live,
      evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
      observations: try observations(["a-info", "b-warning"])
    )
    #expect(full.target?.targetVersion == target)
    #expect(full.availability == .available)
    let unsortedFull = try ManifestInspectionFactory.makeInspection(
      request: request(.full), availability: .available, branches: branch,
      target: build, selectedLdiff: nil, origin: .live,
      evidence: try evidence([.chunkManifest, .branchResponse, .buildResponse]),
      observations: [])
    #expect(unsortedFull.availability == .available)

    let selectedLdiff = try makeLdiff(source: source, target: target)
    let update = try ManifestInspectionFactory.makeInspection(
      request: request(.update(from: source)), availability: .available,
      branches: branch, target: build, selectedLdiff: selectedLdiff, origin: .live,
      evidence: try evidence([
        .branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest,
      ]),
      observations: []
    )
    #expect(update.selectedLdiff?.sourceVersion == source)
  }

  @Test
  func factoryEnforcesAvailabilityOriginEvidenceAndObservationCombinations() throws {
    let source = try GameVersion("1.0.0")
    let targetVersion = try GameVersion("2.0.0")
    let target = try makeBuild(targetVersion)
    let branch = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: targetVersion, preDownloadVersion: nil)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: request(.update(from: targetVersion)),
        availability: .directLdiffUnavailable, branches: branch,
        target: target, selectedLdiff: nil, origin: .live,
        evidence: try evidence([
          .branchResponse, .buildResponse, .patchResponse, .chunkManifest,
        ]), observations: [])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: request(.update(from: source)), availability: .available,
        branches: branch, target: target,
        selectedLdiff: try makeLdiff(source: source, target: targetVersion), origin: .live,
        evidence: try evidence([
          .branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest,
          .fixtureDescriptor,
        ]), observations: [])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: request(.full), availability: .available, branches: branch,
        target: target, selectedLdiff: nil, origin: .live,
        evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
        observations: try observations(["b", "a"])
      )
    }

    let fixtureID = try ManifestFixtureID("fixture-a")
    let fixtureRequest = try request(.full, policy: .fixtureOnly(id: fixtureID))
    let fixtureInspection = try ManifestInspectionFactory.makeInspection(
      request: fixtureRequest, availability: .available, branches: branch,
      target: target, selectedLdiff: nil, origin: .fixture(fixtureID),
      evidence: try evidence([
        .branchResponse, .buildResponse, .chunkManifest, .fixtureDescriptor,
      ]), observations: [])
    #expect(fixtureInspection.origin == .fixture(fixtureID))
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: try request(.full, policy: .freshCache(maxAgeSeconds: 10)),
        availability: .available, branches: branch, target: target, selectedLdiff: nil,
        origin: .freshCache(ageSeconds: 11),
        evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
        observations: [])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: try request(.full, policy: .freshCache(maxAgeSeconds: 60)),
        availability: .available, branches: branch, target: target, selectedLdiff: nil,
        origin: .freshCache(ageSeconds: 10),
        evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
        observations: [])
    }
  }

  @Test
  func availabilityStatesRemainExplicit() throws {
    let official = try GameVersion("2.0.0")
    let source = try GameVersion("1.0.0")
    let build = try makeBuild(official)
    let branch = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: official, preDownloadVersion: nil)
    let upToDate = try ManifestInspectionFactory.makeInspection(
      request: request(.update(from: official)), availability: .upToDate,
      branches: branch, target: build, selectedLdiff: nil, origin: .live,
      evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
      observations: [])
    #expect(upToDate.availability == .upToDate)
    let unavailable = try ManifestInspectionFactory.makeInspection(
      request: request(.preDownload(from: nil)),
      availability: .preDownloadNotPublished, branches: branch,
      target: nil, selectedLdiff: nil, origin: .live,
      evidence: try evidence([.branchResponse]), observations: [])
    #expect(unavailable.availability == .preDownloadNotPublished)
    let direct = try ManifestInspectionFactory.makeInspection(
      request: request(.update(from: source)), availability: .directLdiffUnavailable,
      branches: branch, target: build, selectedLdiff: nil, origin: .live,
      evidence: try evidence([
        .branchResponse, .buildResponse, .patchResponse, .chunkManifest,
      ]), observations: [])
    #expect(direct.availability == .directLdiffUnavailable)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: request(.update(from: source)), availability: .directLdiffUnavailable,
        branches: branch, target: build, selectedLdiff: nil, origin: .live,
        evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
        observations: [])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestInspectionFactory.makeInspection(
        request: request(.update(from: source)), availability: .directLdiffUnavailable,
        branches: branch, target: build, selectedLdiff: nil, origin: .live,
        evidence: try evidence([
          .branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest,
        ]), observations: [])
    }
  }

  @Test
  func publicOutputsExposeNoSecretBearingFieldNames() throws {
    let target = try GameVersion("2.0.0")
    let build = try makeBuild(target)
    let branch = ManifestInspectionFactory.makeBranchSummary(
      officialVersion: target, preDownloadVersion: nil)
    let inspection = try ManifestInspectionFactory.makeInspection(
      request: request(.full), availability: .available, branches: branch,
      target: build, selectedLdiff: nil, origin: .live,
      evidence: try evidence([.branchResponse, .buildResponse, .chunkManifest]),
      observations: try observations(["safe-code"])
    )
    let ldiff = try makeLdiff(source: GameVersion("1.0.0"), target: target)
    let values: [Any] = [
      inspection, inspection.branches, try #require(inspection.target),
      try #require(inspection.target?.categories[.game]), inspection.evidence,
      inspection.evidence.artifacts[0], inspection.observations[0], ldiff,
      try #require(ldiff.categories[.game]),
    ]
    let labels = values.flatMap { Mirror(reflecting: $0).children.compactMap(\.label) }
      .map { $0.lowercased() }
    for forbidden in [
      "url", "password", "package", "header", "path", "token", "cookie", "message", "md5",
      "objectid", "branchid",
    ] {
      #expect(!labels.contains(where: { $0.contains(forbidden) }))
    }
  }

  @Test
  func evidenceGatedAdapterFailsClosedWithoutDependencies() async throws {
    let adapter = EvidenceGatedManifestAdapter()
    #expect(Mirror(reflecting: adapter).children.isEmpty)
    let fixture = try ManifestFixtureID("fixture-a")
    await #expect(throws: ManifestAdapterError.fixtureUnavailable(fixture)) {
      try await adapter.inspect(try request(.full, policy: .fixtureOnly(id: fixture)))
    }
    await #expect(throws: ManifestAdapterError.missingEndpointEvidence) {
      try await adapter.inspect(try request(.full, policy: .freshCache(maxAgeSeconds: 60)))
    }
    await #expect(throws: ManifestAdapterError.missingEndpointEvidence) {
      try await adapter.inspect(try request(.full, policy: .reloadIgnoringCache))
    }
  }

  private func request(
    _ intent: ManifestIntent,
    policy: ManifestCachePolicy = .reloadIgnoringCache
  ) throws -> ManifestInspectionRequest {
    try ManifestInspectionRequest(
      release: .genshinOfficialCN,
      intent: intent,
      categories: [.game],
      cachePolicy: policy
    )
  }

  private func makeBuild(_ target: GameVersion) throws -> BuildManifest {
    let sizes = try ManifestInspectionFactory.makeChunkSizeSummary(
      targetInstalledBytes: 1_000,
      referencedChunkCompressedBytes: 800,
      uniqueChunkObjectBytes: 600
    )
    let game = try ManifestInspectionFactory.makeChunkManifest(
      fileCount: 2, directoryCount: 1, chunkReferenceCount: 3,
      uniqueChunkObjectCount: 2, sizes: sizes)
    return try ManifestInspectionFactory.makeBuildManifest(
      targetVersion: target,
      categories: [.game: game]
    )
  }

  private func makeLdiff(source: GameVersion, target: GameVersion) throws -> LdiffSelection {
    let game = try ManifestInspectionFactory.makeLdiffSelectionSummary(
      manifestFileRecordCount: 2, selectedPatchFileCount: 1,
      fileRecordsWithoutSelectedPatchCount: 1, selectedDeletionCount: 1,
      uniquePatchObjectCount: 1, selectedPatchObjectBytes: 100)
    return try ManifestInspectionFactory.makeLdiffSelection(
      sourceVersion: source,
      targetVersion: target,
      categories: [.game: game]
    )
  }

  private func evidence(
    _ kinds: [ManifestEvidenceArtifactKind]
  ) throws -> ManifestEvidence {
    let artifacts = try kinds.enumerated().map { index, kind in
      try ManifestInspectionFactory.makeEvidenceArtifact(
        kind: kind,
        sha256: String(repeating: String(format: "%x", index % 16), count: 64),
        byteSize: UInt64(index + 1)
      )
    }
    return try ManifestInspectionFactory.makeEvidence(
      release: .genshinOfficialCN,
      profileRevision: 1,
      observedAt: Date(timeIntervalSince1970: 1),
      expiresAt: Date(timeIntervalSince1970: 2),
      schemaBaseline: "schema-1",
      artifacts: artifacts
    )
  }

  private func observations(_ codes: [String]) throws -> [ManifestObservation] {
    try codes.map {
      try ManifestInspectionFactory.makeObservation(code: $0, severity: .info)
    }
  }
}
