import Foundation

enum ManifestInspectionFactory {
  static func makeChunkSizeSummary(
    targetInstalledBytes: UInt64,
    referencedChunkCompressedBytes: UInt64,
    uniqueChunkObjectBytes: UInt64
  ) throws -> ChunkSizeSummary {
    guard referencedChunkCompressedBytes >= uniqueChunkObjectBytes else {
      throw ManifestAdapterError.invalidManifest
    }
    return ChunkSizeSummary(
      targetInstalledBytes: targetInstalledBytes,
      referencedChunkCompressedBytes: referencedChunkCompressedBytes,
      uniqueChunkObjectBytes: uniqueChunkObjectBytes
    )
  }

  static func makeChunkManifest(
    fileCount: UInt64,
    directoryCount: UInt64,
    chunkReferenceCount: UInt64,
    uniqueChunkObjectCount: UInt64,
    sizes: ChunkSizeSummary
  ) throws -> ChunkManifest {
    let coherentReferences =
      (chunkReferenceCount == 0 && uniqueChunkObjectCount == 0
        && sizes.referencedChunkCompressedBytes == 0 && sizes.uniqueChunkObjectBytes == 0)
      || (chunkReferenceCount > 0 && uniqueChunkObjectCount > 0
        && sizes.uniqueChunkObjectBytes > 0)
    guard fileCount > 0, sizes.targetInstalledBytes > 0,
      chunkReferenceCount >= uniqueChunkObjectCount, coherentReferences
    else { throw ManifestAdapterError.invalidManifest }
    return ChunkManifest(
      fileCount: fileCount,
      directoryCount: directoryCount,
      chunkReferenceCount: chunkReferenceCount,
      uniqueChunkObjectCount: uniqueChunkObjectCount,
      sizes: sizes
    )
  }

  static func makeLdiffSelectionSummary(
    manifestFileRecordCount: UInt64,
    selectedPatchFileCount: UInt64,
    fileRecordsWithoutSelectedPatchCount: UInt64,
    selectedDeletionCount: UInt64,
    uniquePatchObjectCount: UInt64,
    selectedPatchObjectBytes: UInt64
  ) throws -> LdiffSelectionSummary {
    let (computedManifestCount, overflow) = selectedPatchFileCount.addingReportingOverflow(
      fileRecordsWithoutSelectedPatchCount)
    let (totalRecordCount, totalOverflow) = manifestFileRecordCount.addingReportingOverflow(
      selectedDeletionCount)
    let coherentObjects =
      (selectedPatchFileCount == 0 && uniquePatchObjectCount == 0
        && selectedPatchObjectBytes == 0)
      || (selectedPatchFileCount > 0 && uniquePatchObjectCount > 0
        && uniquePatchObjectCount <= selectedPatchFileCount && selectedPatchObjectBytes > 0)
    guard !overflow, computedManifestCount == manifestFileRecordCount,
      !totalOverflow, totalRecordCount <= 100_000, coherentObjects
    else {
      throw ManifestAdapterError.invalidManifest
    }
    return LdiffSelectionSummary(
      manifestFileRecordCount: manifestFileRecordCount,
      selectedPatchFileCount: selectedPatchFileCount,
      fileRecordsWithoutSelectedPatchCount: fileRecordsWithoutSelectedPatchCount,
      selectedDeletionCount: selectedDeletionCount,
      uniquePatchObjectCount: uniquePatchObjectCount,
      selectedPatchObjectBytes: selectedPatchObjectBytes
    )
  }

  static func makeBuildManifest(
    targetVersion: GameVersion,
    categories: [ResourceCategory: ChunkManifest]
  ) throws -> BuildManifest {
    guard Set(categories.keys) == [.game] else {
      throw ManifestAdapterError.invalidManifest
    }
    return BuildManifest(
      targetVersion: targetVersion,
      categories: categories
    )
  }

  static func makeLdiffSelection(
    sourceVersion: GameVersion,
    targetVersion: GameVersion,
    categories: [ResourceCategory: LdiffSelectionSummary]
  ) throws -> LdiffSelection {
    guard sourceVersion != targetVersion, Set(categories.keys) == [.game] else {
      throw ManifestAdapterError.invalidManifest
    }
    return LdiffSelection(
      sourceVersion: sourceVersion,
      targetVersion: targetVersion,
      categories: categories
    )
  }

  static func makeBranchSummary(
    officialVersion: GameVersion,
    preDownloadVersion: GameVersion?
  ) -> BranchSummary {
    BranchSummary(
      officialVersion: officialVersion,
      preDownloadVersion: preDownloadVersion
    )
  }

  static func makeEvidenceArtifact(
    kind: ManifestEvidenceArtifactKind,
    sha256: String,
    byteSize: UInt64
  ) throws -> ManifestEvidenceArtifact {
    guard byteSize > 0 else { throw ManifestAdapterError.invalidManifest }
    return try ManifestEvidenceArtifact(
      kind: kind,
      sha256: ManifestSHA256(sha256),
      byteSize: byteSize
    )
  }

  static func makeEvidence(
    release: GameRelease,
    profileRevision: UInt64,
    observedAt: Date,
    expiresAt: Date?,
    schemaBaseline: String,
    artifacts: [ManifestEvidenceArtifact]
  ) throws -> ManifestEvidence {
    guard profileRevision > 0, !artifacts.isEmpty,
      Set(artifacts.map(\.kind)).count == artifacts.count,
      expiresAt.map({ $0 > observedAt }) != false
    else {
      throw ManifestAdapterError.invalidManifest
    }
    return try ManifestEvidence(
      release: release,
      profileRevision: profileRevision,
      observedAt: observedAt,
      expiresAt: expiresAt,
      schemaBaseline: ManifestSchemaBaseline(schemaBaseline),
      artifacts: artifacts
    )
  }

  static func makeObservation(
    code: String,
    severity: ManifestObservationSeverity
  ) throws -> ManifestObservation {
    guard isSafeASCII(code) else { throw ManifestAdapterError.invalidManifest }
    return ManifestObservation(code: code, severity: severity)
  }

  static func makeInspection(
    request: ManifestInspectionRequest,
    availability: ManifestAvailability,
    branches: BranchSummary,
    target: BuildManifest?,
    selectedLdiff: LdiffSelection?,
    origin: ManifestDataOrigin,
    evidence: ManifestEvidence,
    observations: [ManifestObservation]
  ) throws -> ManifestInspection {
    try validateInspectionShape(
      request: request,
      availability: availability,
      branches: branches,
      target: target,
      selectedLdiff: selectedLdiff,
      observations: observations
    )
    let includesFixtureDescriptor: Bool
    if case .fixture = origin {
      includesFixtureDescriptor = true
    } else {
      includesFixtureDescriptor = false
    }
    guard evidence.release == request.release,
      originMatches(request.cachePolicy, origin: origin, evidence: evidence),
      Set(evidence.artifacts.map(\.kind))
        == Set(
          expectedEvidenceArtifactKinds(
            availability: availability,
            target: target,
            selectedLdiff: selectedLdiff,
            includesFixtureDescriptor: includesFixtureDescriptor
          ))
    else { throw ManifestAdapterError.invalidManifest }
    return ManifestInspection(
      release: request.release,
      intent: request.intent,
      availability: availability,
      branches: branches,
      target: target,
      selectedLdiff: selectedLdiff,
      origin: origin,
      evidence: evidence,
      observations: observations
    )
  }

  static func validateInspectionShape(
    request: ManifestInspectionRequest,
    availability: ManifestAvailability,
    branches: BranchSummary,
    target: BuildManifest?,
    selectedLdiff: LdiffSelection?,
    observations: [ManifestObservation]
  ) throws {
    let codes = observations.map(\.code)
    guard codes == codes.sorted(), Set(codes).count == codes.count,
      target.map({ Set($0.categories.keys) == request.categories }) != false,
      selectedLdiff.map({ Set($0.categories.keys) == request.categories }) != false
    else { throw ManifestAdapterError.invalidManifest }
    switch availability {
    case .available:
      guard let target, matchesSlot(request.intent, target: target, branches: branches),
        ldiffMatches(request.intent, target: target, selectedLdiff: selectedLdiff)
      else { throw ManifestAdapterError.invalidManifest }
    case .upToDate:
      guard let target, selectedLdiff == nil,
        sourceVersion(request.intent) == target.targetVersion,
        matchesSlot(request.intent, target: target, branches: branches)
      else { throw ManifestAdapterError.invalidManifest }
    case .preDownloadNotPublished:
      guard case .preDownload = request.intent, branches.preDownloadVersion == nil,
        target == nil, selectedLdiff == nil
      else { throw ManifestAdapterError.invalidManifest }
    case .directLdiffUnavailable:
      guard let target, let source = sourceVersion(request.intent),
        source != target.targetVersion, selectedLdiff == nil,
        matchesSlot(request.intent, target: target, branches: branches)
      else { throw ManifestAdapterError.invalidManifest }
    }
  }

  static func expectedEvidenceArtifactKinds(
    availability: ManifestAvailability,
    target: BuildManifest?,
    selectedLdiff: LdiffSelection?,
    includesFixtureDescriptor: Bool
  ) -> [ManifestEvidenceArtifactKind] {
    let hasPatchResponse = selectedLdiff != nil || availability == .directLdiffUnavailable
    let hasDiffManifest = selectedLdiff != nil
    var kinds: [ManifestEvidenceArtifactKind] = [.branchResponse]
    if target != nil { kinds.append(.buildResponse) }
    if hasPatchResponse { kinds.append(.patchResponse) }
    if target != nil { kinds.append(.chunkManifest) }
    if hasDiffManifest { kinds.append(.diffManifest) }
    if includesFixtureDescriptor { kinds.append(.fixtureDescriptor) }
    return kinds
  }

  static func isSafeASCII(_ value: String) -> Bool {
    value != "." && value != ".." && !value.isEmpty && value.utf8.count <= 128
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 46 || $0 == 95
      }
  }

  private static func originMatches(
    _ policy: ManifestCachePolicy,
    origin: ManifestDataOrigin,
    evidence: ManifestEvidence
  ) -> Bool {
    switch (policy, origin) {
    case (.fixtureOnly(let expected), .fixture(let actual)):
      return expected == actual && evidence.artifacts.contains { $0.kind == .fixtureDescriptor }
    case (.freshCache(let maximum), .freshCache(let age)):
      guard age <= maximum, age <= 9_007_199_254_740_992,
        !evidence.artifacts.contains(where: { $0.kind == .fixtureDescriptor })
      else { return false }
      let resolvedTime = evidence.observedAt.timeIntervalSinceReferenceDate + TimeInterval(age)
      return resolvedTime.isFinite
        && evidence.expiresAt.map({ resolvedTime < $0.timeIntervalSinceReferenceDate }) != false
    case (.reloadIgnoringCache, .live):
      return !evidence.artifacts.contains { $0.kind == .fixtureDescriptor }
    default:
      return false
    }
  }

  private static func sourceVersion(_ intent: ManifestIntent) -> GameVersion? {
    switch intent {
    case .full: nil
    case .update(let from): from
    case .preDownload(let from): from
    }
  }

  private static func matchesSlot(
    _ intent: ManifestIntent,
    target: BuildManifest,
    branches: BranchSummary
  ) -> Bool {
    switch intent {
    case .full, .update:
      branches.officialVersion == target.targetVersion
    case .preDownload:
      branches.preDownloadVersion == target.targetVersion
    }
  }

  private static func ldiffMatches(
    _ intent: ManifestIntent,
    target: BuildManifest,
    selectedLdiff: LdiffSelection?
  ) -> Bool {
    switch intent {
    case .full, .preDownload(from: nil): selectedLdiff == nil
    case .update(let from), .preDownload(from: .some(let from)):
      selectedLdiff?.sourceVersion == from
        && selectedLdiff?.targetVersion == target.targetVersion
    }
  }
}
