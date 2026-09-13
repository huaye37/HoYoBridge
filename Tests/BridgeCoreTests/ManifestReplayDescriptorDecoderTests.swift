import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct ManifestReplayDescriptorDecoderTests {
  @Test
  func decodesCanonicalSevenShapeMatrix() throws {
    let cases = descriptorCases()
    for item in cases {
      let data = try canonicalData(item.dto)
      let descriptor = try ManifestReplayDescriptorDecoder.decode(data)
      #expect(descriptor.fixtureID.value == item.dto.scope.fixtureID)
      #expect(descriptor.availability.rawValue == item.dto.availability)
      #expect(descriptor.expectedArtifactKinds == item.expectedKinds)
      #expect(descriptor.externalArtifactBindings.map(\.kind) == item.expectedKinds)
      #expect(!descriptor.expectedArtifactKinds.contains(.fixtureDescriptor))
      #expect(descriptor.fixtureDescriptorSHA256 == sha256(data))
      #expect(descriptor.fixtureDescriptorByteSize == UInt64(data.count))
      if case .fixtureOnly(let requestID) = descriptor.expectedRequest.cachePolicy {
        #expect(requestID == descriptor.fixtureID)
      } else {
        Issue.record("Descriptor request was not fixture-only")
      }
    }
  }

  @Test
  func matchesIndependentCanonicalKnownVector() throws {
    let data = Data(knownVectorJSON.utf8)
    let descriptor = try ManifestReplayDescriptorDecoder.decode(data)

    #expect(
      descriptor.fixtureDescriptorSHA256
        == "a4c2410ed80200544d0affd98026b0bd1d2012926a36ceb86407fccec74cdbfe")
    #expect(descriptor.fixtureDescriptorByteSize == 471)
    #expect(descriptor.fixtureID.value == "known")
    #expect(descriptor.availability == .preDownloadNotPublished)
    #expect(descriptor.expectedArtifactKinds == [.branchResponse])

    var versionTwo = descriptorCases()[0].dto
    versionTwo.schemaVersion = 2
    #expect(throws: ManifestReplayDescriptorDecodingError.invalidDescriptor) {
      try ManifestReplayDescriptorDecoder.decode(try canonicalData(versionTwo))
    }
    var legacyObject = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacyObject["schemaVersion"] = 2
    legacyObject.removeValue(forKey: "externalArtifactBindings")
    let legacyWithoutBindings = try JSONSerialization.data(
      withJSONObject: legacyObject, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(throws: ManifestReplayDescriptorDecodingError.malformed) {
      try ManifestReplayDescriptorDecoder.decode(legacyWithoutBindings)
    }
    let updateText = try #require(
      String(
        data: canonicalData(descriptorCases()[1].dto), encoding: .utf8))
    let legacyField = Data(
      updateText.replacingOccurrences(
        of: "\"selectedLdiff\":", with: "\"patch\":"
      ).utf8)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(legacyField)
    }
  }

  @Test
  func rejectsNoncanonicalUnknownDuplicateDeepAndOversizedJSON() throws {
    let canonical = try canonicalData(descriptorCases()[0].dto)
    var whitespace = Data([0x20])
    whitespace.append(canonical)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(whitespace)
    }
    var trailingNewline = canonical
    trailingNewline.append(0x0A)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(trailingNewline)
    }

    let text = try #require(String(data: canonical, encoding: .utf8))
    let unknown = Data(("{\"unknown\":0," + text.dropFirst()).utf8)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(unknown)
    }
    let duplicate = Data(("{\"schemaVersion\":3," + text.dropFirst()).utf8)
    #expect(throws: (any Error).self) {
      try ManifestReplayDescriptorDecoder.decode(duplicate)
    }
    let explicitNull = Data(
      knownVectorJSON.replacingOccurrences(
        of: #""intent":{"kind":"preDownload"}"#,
        with: #""intent":{"kind":"preDownload","sourceVersion":null}"#
      ).utf8)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(explicitNull)
    }
    let reorderedJSON =
      #"{"branches":{"officialVersion":"2.0.0"},"#
      + #""availability":"preDownloadNotPublished","#
      + #""evidenceMetadata":{"observedAtUnixSeconds":1,"profileRevision":1,"#
      + #""schemaBaseline":"schema-1"},"externalArtifactBindings":[{"byteSize":14,"kind":"branchResponse","sha256":"2408e59e8e5c77a93bdf4648a1dc9fdedb5d7df80500dd90d7fd079912d801d4"}],"observations":[],"schemaVersion":3,"#
      + #""scope":{"categories":["game"],"fixtureID":"known","#
      + #""intent":{"kind":"preDownload"},"release":"genshinOfficialCN"}}"#
    let reordered = Data(reorderedJSON.utf8)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(reordered)
    }
    let deep = Data(
      ("{\"unknown\":" + String(repeating: "[", count: 17) + "0"
        + String(repeating: "]", count: 17) + "," + text.dropFirst()).utf8)
    #expect(throws: ManifestReplayDescriptorDecodingError.malformed) {
      try ManifestReplayDescriptorDecoder.decode(deep)
    }
    #expect(throws: ManifestReplayDescriptorDecodingError.oversized) {
      try ManifestReplayDescriptorDecoder.decode(
        Data(repeating: 0x20, count: ManifestReplayDescriptorDecoder.maximumBytes + 1))
    }
    #expect(throws: ManifestReplayDescriptorDecodingError.malformed) {
      try ManifestReplayDescriptorDecoder.decode(Data())
    }
    #expect(ManifestReplayDescriptorDecoder.maximumBytes == 64 * 1_024)
    #expect(ManifestReplayDescriptorDecoder.maximumDepth == 16)
  }

  @Test
  func enforcesWithoutEscapingSlashesAndIgnoresBracketsInsideStrings() throws {
    var slash = descriptorCases()[0].dto
    slash.branches.officialVersion = "2/0"
    let canonical = try canonicalData(slash)
    let text = try #require(String(data: canonical, encoding: .utf8))
    #expect(text.contains("2/0"))
    let escaped = Data(text.replacingOccurrences(of: "/", with: "\\/").utf8)
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(escaped)
    }

    var bracketed = descriptorCases()[0].dto
    let version = "v" + String(repeating: "[", count: 32)
    bracketed.branches.officialVersion = version
    _ = try ManifestReplayDescriptorDecoder.decode(try canonicalData(bracketed))
  }

  @Test
  func rejectsSevenWrongRequestAndAvailabilityShapes() throws {
    var fullWithSource = descriptorCases()[0].dto
    fullWithSource.scope.intent.sourceVersion = "1.0.0"
    var updateWithoutSource = descriptorCases()[1].dto
    updateWithoutSource.scope.intent.sourceVersion = nil
    var updateWithoutLdiff = descriptorCases()[1].dto
    updateWithoutLdiff.selectedLdiff = nil
    var preloadWithoutSlot = descriptorCases()[2].dto
    preloadWithoutSlot.branches.preDownloadVersion = nil
    var preloadLdiffWithoutSelection = descriptorCases()[3].dto
    preloadLdiffWithoutSelection.selectedLdiff = nil
    var staleUpToDate = descriptorCases()[4].dto
    staleUpToDate.scope.intent.sourceVersion = "1.0.0"
    var publishedPreloadMarkedMissing = descriptorCases()[5].dto
    publishedPreloadMarkedMissing.branches.preDownloadVersion = "2.1.0-pre"
    publishedPreloadMarkedMissing.target = target()

    for invalid in [
      fullWithSource, updateWithoutSource, updateWithoutLdiff,
      preloadWithoutSlot, preloadLdiffWithoutSelection, staleUpToDate,
      publishedPreloadMarkedMissing,
    ] {
      #expect(throws: ManifestReplayDescriptorDecodingError.invalidDescriptor) {
        try ManifestReplayDescriptorDecoder.decode(try canonicalData(invalid))
      }
    }
  }

  @Test
  func rejectsInvalidSummaryEvidenceMetadataAndObservationOrder() throws {
    var invalidSummary = descriptorCases()[0].dto
    invalidSummary.target?.game.fileCount = 0
    var invalidRevision = descriptorCases()[0].dto
    invalidRevision.evidenceMetadata.profileRevision = 0
    var invalidExpiry = descriptorCases()[0].dto
    invalidExpiry.evidenceMetadata.expiresAtUnixSeconds =
      invalidExpiry.evidenceMetadata.observedAtUnixSeconds
    var invalidBaseline = descriptorCases()[0].dto
    invalidBaseline.evidenceMetadata.schemaBaseline = "unsafe value"
    var unsortedObservations = descriptorCases()[0].dto
    unsortedObservations.observations = [
      TestObservation(code: "b", severity: "info"),
      TestObservation(code: "a", severity: "warning"),
    ]
    var unsupportedCategory = descriptorCases()[0].dto
    unsupportedCategory.scope.categories = ["game", "voice"]
    var tooManyObservations = descriptorCases()[0].dto
    tooManyObservations.observations = (0...256).map {
      TestObservation(code: String(format: "obs-%03d", $0), severity: "info")
    }
    var outOfRangeTime = descriptorCases()[0].dto
    outOfRangeTime.evidenceMetadata.observedAtUnixSeconds = 253_402_300_800

    for invalid in [
      invalidSummary, invalidRevision, invalidExpiry,
      invalidBaseline, unsortedObservations, unsupportedCategory,
      tooManyObservations, outOfRangeTime,
    ] {
      #expect(throws: ManifestReplayDescriptorDecodingError.invalidDescriptor) {
        try ManifestReplayDescriptorDecoder.decode(try canonicalData(invalid))
      }
    }
  }

  @Test
  func rejectsBindingOrderKindHashReferenceAndCapViolations() throws {
    var swapped = descriptorCases()[1].dto
    swapped.externalArtifactBindings.swapAt(0, 1)
    var uppercaseHash = descriptorCases()[0].dto
    uppercaseHash.externalArtifactBindings[0].sha256 =
      uppercaseHash.externalArtifactBindings[0].sha256.uppercased()
    var malformedHash = descriptorCases()[0].dto
    malformedHash.externalArtifactBindings[0].sha256 = String(repeating: "g", count: 64)
    var responseReference = descriptorCases()[0].dto
    responseReference.externalArtifactBindings[0].manifestReferenceSHA256 =
      String(repeating: "a", count: 64)
    var missingChunkReference = descriptorCases()[0].dto
    let chunkIndex = try #require(
      missingChunkReference.externalArtifactBindings.firstIndex {
        $0.kind == ManifestEvidenceArtifactKind.chunkManifest.rawValue
      })
    missingChunkReference.externalArtifactBindings[chunkIndex].manifestReferenceSHA256 = nil
    var uppercaseReference = descriptorCases()[0].dto
    uppercaseReference.externalArtifactBindings[chunkIndex].manifestReferenceSHA256 =
      String(repeating: "A", count: 64)
    var zeroSize = descriptorCases()[0].dto
    zeroSize.externalArtifactBindings[0].byteSize = 0
    var overKindCap = descriptorCases()[5].dto
    overKindCap.externalArtifactBindings[0].byteSize =
      ManifestReplayArtifactBundleLimits.default.branchResponseBytes + 1
    var overTotalCap = descriptorCases()[1].dto
    let defaults = ManifestReplayArtifactBundleLimits.default
    for index in overTotalCap.externalArtifactBindings.indices {
      let kind = try #require(
        ManifestEvidenceArtifactKind(
          rawValue: overTotalCap.externalArtifactBindings[index].kind))
      overTotalCap.externalArtifactBindings[index].byteSize = try #require(
        defaults.maximumBytes(for: kind))
    }

    for invalid in [
      swapped, uppercaseHash, malformedHash, responseReference,
      missingChunkReference, uppercaseReference, zeroSize, overKindCap, overTotalCap,
    ] {
      #expect(throws: ManifestReplayDescriptorDecodingError.invalidDescriptor) {
        try ManifestReplayDescriptorDecoder.decode(try canonicalData(invalid))
      }
    }
  }

  @Test
  func bindingClaimsChangeDescriptorSelfHashAndExplicitNullIsNoncanonical() throws {
    var bytesB = descriptorCases()[0].dto
    bytesB.externalArtifactBindings[0].sha256 = String(repeating: "b", count: 64)
    var sizeB = descriptorCases()[0].dto
    sizeB.externalArtifactBindings[0].byteSize += 1
    var referenceB = descriptorCases()[0].dto
    let chunkIndex = try #require(
      referenceB.externalArtifactBindings.firstIndex {
        $0.kind == ManifestEvidenceArtifactKind.chunkManifest.rawValue
      })
    referenceB.externalArtifactBindings[chunkIndex].manifestReferenceSHA256 =
      String(repeating: "e", count: 64)
    let baseline = try ManifestReplayDescriptorDecoder.decode(
      try canonicalData(descriptorCases()[0].dto))
    for changed in [bytesB, sizeB, referenceB] {
      let descriptor = try ManifestReplayDescriptorDecoder.decode(try canonicalData(changed))
      #expect(descriptor.fixtureDescriptorSHA256 != baseline.fixtureDescriptorSHA256)
    }

    let text = knownVectorJSON.replacingOccurrences(
      of: #""kind":"branchResponse","sha256""#,
      with: #""kind":"branchResponse","manifestReferenceSHA256":null,"sha256""#
    )
    #expect(throws: ManifestReplayDescriptorDecodingError.nonCanonical) {
      try ManifestReplayDescriptorDecoder.decode(Data(text.utf8))
    }
  }

  @Test
  func descriptorBindsExternalBytesWithoutExposingManifestReferenceIDs() throws {
    let data = try canonicalData(descriptorCases()[6].dto)
    let text = try #require(String(data: data, encoding: .utf8)).lowercased()
    #expect(text.contains("externalartifactbindings"))
    #expect(text.contains("sha256"))
    #expect(!text.contains("http"))
    #expect(!text.contains("token"))

    let descriptor = try ManifestReplayDescriptorDecoder.decode(data)
    #expect(
      descriptor.expectedArtifactKinds == [
        .branchResponse, .buildResponse, .patchResponse, .chunkManifest,
      ])
    #expect(descriptor.fixtureDescriptorSHA256 == sha256(data))
    #expect(descriptor.fixtureDescriptorByteSize == UInt64(data.count))
    #expect(!isDecodable(ValidatedReplayDescriptor.self))
  }

  @Test
  func concurrentDecodingIsDeterministic() async throws {
    let data = try canonicalData(descriptorCases()[1].dto)
    let expected = try ManifestReplayDescriptorDecoder.decode(data)
    let values = try await withThrowingTaskGroup(
      of: ValidatedReplayDescriptor.self,
      returning: [ValidatedReplayDescriptor].self
    ) { group in
      for _ in 0..<16 {
        group.addTask { try ManifestReplayDescriptorDecoder.decode(data) }
      }
      var values: [ValidatedReplayDescriptor] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(values.allSatisfy { $0 == expected })
  }

  private func descriptorCases() -> [(
    dto: TestDescriptor, expectedKinds: [ManifestEvidenceArtifactKind]
  )] {
    let full = descriptor(
      id: "full", intent: TestIntent(kind: "full", sourceVersion: nil),
      availability: "available", official: "2.0.0", preload: nil,
      targetVersion: "2.0.0", ldiffSource: nil)
    let update = descriptor(
      id: "update", intent: TestIntent(kind: "update", sourceVersion: "1.0.0"),
      availability: "available", official: "2.0.0", preload: nil,
      targetVersion: "2.0.0", ldiffSource: "1.0.0")
    let preload = descriptor(
      id: "preload", intent: TestIntent(kind: "preDownload", sourceVersion: nil),
      availability: "available", official: "2.0.0", preload: "2.1.0-pre",
      targetVersion: "2.1.0-pre", ldiffSource: nil)
    let preloadLdiff = descriptor(
      id: "preload-ldiff",
      intent: TestIntent(kind: "preDownload", sourceVersion: "2.0.0"),
      availability: "available", official: "2.0.0", preload: "2.1.0-pre",
      targetVersion: "2.1.0-pre", ldiffSource: "2.0.0")
    let upToDate = descriptor(
      id: "up-to-date", intent: TestIntent(kind: "update", sourceVersion: "2.0.0"),
      availability: "upToDate", official: "2.0.0", preload: nil,
      targetVersion: "2.0.0", ldiffSource: nil)
    let unpublished = descriptor(
      id: "unpublished", intent: TestIntent(kind: "preDownload", sourceVersion: nil),
      availability: "preDownloadNotPublished", official: "2.0.0", preload: nil,
      targetVersion: nil, ldiffSource: nil)
    let unavailable = descriptor(
      id: "unavailable", intent: TestIntent(kind: "update", sourceVersion: "1.0.0"),
      availability: "directLdiffUnavailable", official: "2.0.0", preload: nil,
      targetVersion: "2.0.0", ldiffSource: nil)
    return [
      (full, [.branchResponse, .buildResponse, .chunkManifest]),
      (update, [.branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest]),
      (preload, [.branchResponse, .buildResponse, .chunkManifest]),
      (
        preloadLdiff,
        [.branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest]
      ),
      (upToDate, [.branchResponse, .buildResponse, .chunkManifest]),
      (unpublished, [.branchResponse]),
      (
        unavailable,
        [.branchResponse, .buildResponse, .patchResponse, .chunkManifest]
      ),
    ]
  }

  private func descriptor(
    id: String,
    intent: TestIntent,
    availability: String,
    official: String,
    preload: String?,
    targetVersion: String?,
    ldiffSource: String?
  ) -> TestDescriptor {
    let targetValue = targetVersion.map { _ in target() }
    let selectedLdiffValue = ldiffSource.map { _ in selectedLdiff() }
    let expectedKinds = expectedKinds(
      availability: availability,
      target: targetValue,
      selectedLdiff: selectedLdiffValue
    )
    return TestDescriptor(
      schemaVersion: 3,
      scope: TestScope(
        fixtureID: id, release: "genshinOfficialCN",
        intent: intent, categories: ["game"]),
      availability: availability,
      branches: TestBranches(
        officialVersion: official, preDownloadVersion: preload),
      target: targetValue,
      selectedLdiff: selectedLdiffValue,
      externalArtifactBindings: expectedKinds.map(binding),
      evidenceMetadata: TestEvidence(
        profileRevision: 1, observedAtUnixSeconds: 1,
        expiresAtUnixSeconds: 2, schemaBaseline: "schema-1"),
      observations: [TestObservation(code: "safe", severity: "info")]
    )
  }

  private func expectedKinds(
    availability: String,
    target: TestTarget?,
    selectedLdiff: TestSelectedLdiff?
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

  private func binding(_ kind: ManifestEvidenceArtifactKind) -> TestArtifactBinding {
    TestArtifactBinding(
      kind: kind.rawValue,
      sha256: sha256(Data(kind.rawValue.utf8)),
      byteSize: UInt64(kind.rawValue.utf8.count),
      manifestReferenceSHA256: manifestReference(for: kind)
    )
  }

  private func manifestReference(for kind: ManifestEvidenceArtifactKind) -> String? {
    switch kind {
    case .chunkManifest: String(repeating: "c", count: 64)
    case .diffManifest: String(repeating: "d", count: 64)
    default: nil
    }
  }

  private func target() -> TestTarget {
    TestTarget(
      game: TestChunkSummary(
        fileCount: 2, directoryCount: 1, chunkReferenceCount: 3,
        uniqueChunkObjectCount: 2, targetInstalledBytes: 1_000,
        referencedChunkCompressedBytes: 800, uniqueChunkObjectBytes: 600))
  }

  private func selectedLdiff() -> TestSelectedLdiff {
    TestSelectedLdiff(
      game: TestLdiffSelectionSummary(
        manifestFileRecordCount: 2, selectedPatchFileCount: 1,
        fileRecordsWithoutSelectedPatchCount: 1, selectedDeletionCount: 1,
        uniquePatchObjectCount: 1, selectedPatchObjectBytes: 100))
  }

  private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func isDecodable<T>(_ type: T.Type) -> Bool {
    type is any Decodable.Type
  }

  private var knownVectorJSON: String {
    #"{"availability":"preDownloadNotPublished","branches":{"officialVersion":"2.0.0"},"#
      + #""evidenceMetadata":{"observedAtUnixSeconds":1,"profileRevision":1,"#
      + #""schemaBaseline":"schema-1"},"externalArtifactBindings":[{"byteSize":14,"kind":"branchResponse","sha256":"2408e59e8e5c77a93bdf4648a1dc9fdedb5d7df80500dd90d7fd079912d801d4"}],"observations":[],"schemaVersion":3,"#
      + #""scope":{"categories":["game"],"fixtureID":"known","#
      + #""intent":{"kind":"preDownload"},"release":"genshinOfficialCN"}}"#
  }
}

private struct TestDescriptor: Codable {
  var schemaVersion: UInt8
  var scope: TestScope
  var availability: String
  var branches: TestBranches
  var target: TestTarget?
  var selectedLdiff: TestSelectedLdiff?
  var externalArtifactBindings: [TestArtifactBinding]
  var evidenceMetadata: TestEvidence
  var observations: [TestObservation]
}

private struct TestArtifactBinding: Codable {
  var kind: String
  var sha256: String
  var byteSize: UInt64
  var manifestReferenceSHA256: String?
}

private struct TestScope: Codable {
  var fixtureID: String
  var release: String
  var intent: TestIntent
  var categories: [String]
}

private struct TestIntent: Codable {
  var kind: String
  var sourceVersion: String?
}

private struct TestBranches: Codable {
  var officialVersion: String
  var preDownloadVersion: String?
}

private struct TestTarget: Codable {
  var game: TestChunkSummary
}

private struct TestChunkSummary: Codable {
  var fileCount: UInt64
  var directoryCount: UInt64
  var chunkReferenceCount: UInt64
  var uniqueChunkObjectCount: UInt64
  var targetInstalledBytes: UInt64
  var referencedChunkCompressedBytes: UInt64
  var uniqueChunkObjectBytes: UInt64
}

private struct TestSelectedLdiff: Codable {
  var game: TestLdiffSelectionSummary
}

private struct TestLdiffSelectionSummary: Codable {
  var manifestFileRecordCount: UInt64
  var selectedPatchFileCount: UInt64
  var fileRecordsWithoutSelectedPatchCount: UInt64
  var selectedDeletionCount: UInt64
  var uniquePatchObjectCount: UInt64
  var selectedPatchObjectBytes: UInt64
}

private struct TestEvidence: Codable {
  var profileRevision: UInt64
  var observedAtUnixSeconds: Int64
  var expiresAtUnixSeconds: Int64?
  var schemaBaseline: String
}

private struct TestObservation: Codable {
  var code: String
  var severity: String
}
