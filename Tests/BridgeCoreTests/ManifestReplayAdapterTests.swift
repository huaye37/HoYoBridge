import Foundation
import Testing

@testable import BridgeCore

struct ManifestReplayAdapterTests {
  @Test
  func replaysOnlyExactMaterializedFixtureScope() async throws {
    let fixture = try MaterializerTestFixture.make(.full, id: "adapter-scope")
    let materialized = try ManifestReplayMaterializer.materialize(
      fixture.bundle, using: fixture.decoder)
    let adapter = ManifestReplayAdapter(
      registry: try ManifestReplayRegistry([materialized]))

    #expect(
      try await adapter.inspect(materialized.expectedRequest)
        == materialized.inspection)

    let canary = "request-secret-canary"
    let mismatched = try ManifestInspectionRequest(
      release: .genshinOfficialCN,
      intent: .update(from: GameVersion(canary)),
      categories: [.game],
      cachePolicy: .fixtureOnly(id: materialized.fixtureID)
    )
    do {
      _ = try await adapter.inspect(mismatched)
      Issue.record("Expected exact request mismatch to fail")
    } catch {
      #expect(error as? ManifestAdapterError == .fixtureUnavailable(materialized.fixtureID))
      #expect(!String(reflecting: error).contains(canary))
    }

    let unknownID = try ManifestFixtureID("adapter-unknown")
    let unknown = try ManifestInspectionRequest(
      release: .genshinOfficialCN,
      intent: .full,
      categories: [.game],
      cachePolicy: .fixtureOnly(id: unknownID)
    )
    await #expect(throws: ManifestAdapterError.fixtureUnavailable(unknownID)) {
      try await adapter.inspect(unknown)
    }
    for policy in [
      ManifestCachePolicy.freshCache(maxAgeSeconds: 60),
      .reloadIgnoringCache,
    ] {
      let request = try ManifestInspectionRequest(
        release: .genshinOfficialCN,
        intent: .full,
        categories: [.game],
        cachePolicy: policy
      )
      await #expect(throws: ManifestAdapterError.missingEndpointEvidence) {
        try await adapter.inspect(request)
      }
    }
  }

  @Test
  func registryRejectsDuplicateMaterializedCapability() throws {
    let fixture = try MaterializerTestFixture.make(.full, id: "adapter-duplicate")
    let materialized = try ManifestReplayMaterializer.materialize(
      fixture.bundle, using: fixture.decoder)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayRegistry([materialized, materialized])
    }
  }

  @Test
  func adapterHonorsCancellationAndConcurrentReads() async throws {
    let fixture = try MaterializerTestFixture.make(.full, id: "adapter-concurrent")
    let materialized = try ManifestReplayMaterializer.materialize(
      fixture.bundle, using: fixture.decoder)
    let adapter = ManifestReplayAdapter(
      registry: try ManifestReplayRegistry([materialized]))
    let cancelled = Task { () throws -> ManifestInspection in
      withUnsafeCurrentTask { $0?.cancel() }
      return try await adapter.inspect(materialized.expectedRequest)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let results = try await withThrowingTaskGroup(
      of: ManifestInspection.self,
      returning: [ManifestInspection].self
    ) { group in
      for _ in 0..<16 {
        group.addTask { try await adapter.inspect(materialized.expectedRequest) }
      }
      var values: [ManifestInspection] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(results.count == 16)
    #expect(results.allSatisfy { $0 == materialized.inspection })
  }

  @Test
  func rawCandidateStillRebuildsDeeplyButCannotEnterRegistry() throws {
    let fixture = try MaterializerTestFixture.make(.full, id: "candidate-deep")
    let materialized = try ManifestReplayMaterializer.materialize(
      fixture.bundle, using: fixture.decoder)
    let candidate = try ManifestReplayCandidate.make(
      fixtureID: materialized.fixtureID,
      expectedRequest: materialized.expectedRequest,
      candidate: materialized.inspection
    )
    #expect(candidate.inspection == materialized.inspection)

    let validTarget = try #require(materialized.inspection.target)
    let validSummary = try #require(validTarget.categories[.game])
    let forgedSummary = ChunkManifest(
      fileCount: 0,
      directoryCount: validSummary.directoryCount,
      chunkReferenceCount: validSummary.chunkReferenceCount,
      uniqueChunkObjectCount: validSummary.uniqueChunkObjectCount,
      sizes: validSummary.sizes
    )
    let forged = ManifestInspection(
      release: materialized.inspection.release,
      intent: materialized.inspection.intent,
      availability: materialized.inspection.availability,
      branches: materialized.inspection.branches,
      target: BuildManifest(
        targetVersion: validTarget.targetVersion,
        categories: [.game: forgedSummary]),
      selectedLdiff: materialized.inspection.selectedLdiff,
      origin: materialized.inspection.origin,
      evidence: materialized.inspection.evidence,
      observations: materialized.inspection.observations
    )
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayCandidate.make(
        fixtureID: materialized.fixtureID,
        expectedRequest: materialized.expectedRequest,
        candidate: forged
      )
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReplayCandidate.make(
        fixtureID: ManifestFixtureID("candidate-wrong-id"),
        expectedRequest: materialized.expectedRequest,
        candidate: materialized.inspection
      )
    }

    let registry = try ManifestReplayRegistry([materialized])
    let adapter = ManifestReplayAdapter(registry: registry)
    for value in [candidate as Any, materialized as Any, registry as Any, adapter as Any] {
      let labels = Mirror(reflecting: value).children.compactMap(\.label)
        .map { $0.lowercased() }
      for forbidden in [
        "url", "path", "token", "password", "package", "header", "cookie", "transport",
      ] {
        #expect(!labels.contains(where: { $0.contains(forbidden) }))
      }
    }
    #expect(!isDecodable(ManifestReplayCandidate.self))
    #expect(!isDecodable(MaterializedManifestReplayFixture.self))
    #expect(!isDecodable(ManifestReplayRegistry.self))
  }

  private func isDecodable<T>(_ type: T.Type) -> Bool {
    type is any Decodable.Type
  }
}
