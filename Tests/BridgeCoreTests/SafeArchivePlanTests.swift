import Foundation
import Testing

@testable import BridgeCore

struct SafeArchivePlanTests {
  @Test
  func createsStablePlanWithNormalizedPathsModesAndSizes() throws {
    let entries = [
      entry("data/config.json", size: 12, permissions: 0o644),
      entry("Bin/Tool", size: 20, permissions: 0o755),
      entry("Bin/", kind: .directory, permissions: 0o755),
    ]

    let plan = try SafeArchivePlanner.plan(entries: entries, archiveByteSize: 10)

    #expect(plan.policyVersion == 1)
    #expect(plan.totalRegularFileBytes == 32)
    #expect(plan.entries.map(\.relativePath) == ["Bin", "Bin/Tool", "data/config.json"])
    #expect(plan.entries.map(\.normalizedPermissions) == [0o700, 0o700, 0o600])
    #expect(plan.entries.allSatisfy { $0.sourcePathSHA256.count == 64 })
  }

  @Test
  func rejectsEveryNonFileAndNonDirectoryKind() {
    for kind in ArchiveEntryKind.allCases where kind != .regularFile && kind != .directory {
      #expect(throws: SafeArchivePlanError.unsupportedEntryKind(kind)) {
        try SafeArchivePlanner.plan(
          entries: [entry("unsafe", kind: kind)],
          archiveByteSize: 1
        )
      }
    }
  }

  @Test
  func rejectsTraversalPlatformAndAmbiguousPathSyntax() {
    let invalidPaths = [
      "", "/absolute", "~/home", "C:/drive", "a\\b", "a:b", "a\u{0000}b",
      "a//b", "./a", "a/../b", " a", "a ", "a./child", "file/",
    ]
    for path in invalidPaths {
      #expect(throws: (any Error).self) {
        try SafeArchivePlanner.plan(entries: [entry(path)], archiveByteSize: 1)
      }
    }
  }

  @Test
  func directoryMayHaveOneTrailingSlashButNotTwo() throws {
    let accepted = try SafeArchivePlanner.plan(
      entries: [entry("folder/", kind: .directory)],
      archiveByteSize: 1
    )
    #expect(accepted.entries.single?.relativePath == "folder")

    #expect(throws: SafeArchivePlanError.invalidPath(.emptyComponent)) {
      try SafeArchivePlanner.plan(
        entries: [entry("folder//", kind: .directory)],
        archiveByteSize: 1
      )
    }
  }

  @Test
  func rejectsUnicodeAndCaseFoldCollisions() {
    let collisions = [
      ("Folder/File", "folder/file"),
      ("café.txt", "cafe\u{301}.txt"),
      ("Straße.txt", "STRASSE.txt"),
      ("I.txt", "i.txt"),
      ("İ.txt", "i\u{307}.txt"),
    ]
    for pair in collisions {
      #expect(throws: SafeArchivePlanError.canonicalPathCollision) {
        try SafeArchivePlanner.plan(
          entries: [entry(pair.0), entry(pair.1)],
          archiveByteSize: 1
        )
      }
    }
  }

  @Test
  func rejectsFileAncestorRegardlessOfArchiveOrder() {
    let parent = entry("runtime", size: 1)
    let child = entry("runtime/bin/tool", size: 1)
    for entries in [[parent, child], [child, parent]] {
      #expect(throws: SafeArchivePlanError.fileAncestorConflict) {
        try SafeArchivePlanner.plan(entries: entries, archiveByteSize: 1)
      }
    }
  }

  @Test
  func rejectsDuplicateAndFileDirectoryCollision() {
    #expect(throws: SafeArchivePlanError.canonicalPathCollision) {
      try SafeArchivePlanner.plan(
        entries: [entry("same"), entry("same")],
        archiveByteSize: 1
      )
    }
    #expect(throws: SafeArchivePlanError.canonicalPathCollision) {
      try SafeArchivePlanner.plan(
        entries: [entry("same"), entry("same", kind: .directory)],
        archiveByteSize: 1
      )
    }
  }

  @Test
  func rejectsLinksPayloadDirectoriesAndSpecialPermissions() {
    #expect(throws: SafeArchivePlanError.unexpectedLinkTarget) {
      try SafeArchivePlanner.plan(
        entries: [entry("file", linkTarget: "target")],
        archiveByteSize: 1
      )
    }
    #expect(throws: SafeArchivePlanError.directoryHasPayload(1)) {
      try SafeArchivePlanner.plan(
        entries: [entry("dir", kind: .directory, size: 1)],
        archiveByteSize: 1
      )
    }
    for permissions: UInt32 in [0o4755, 0o2755, 0o1755, 0o100644] {
      #expect(throws: SafeArchivePlanError.unsafePermissions) {
        try SafeArchivePlanner.plan(
          entries: [entry("file", permissions: permissions)],
          archiveByteSize: 1
        )
      }
    }
  }

  @Test
  func enforcesPathComponentDepthAndEntryLimitsIncludingZero() {
    let limits = SafeExtractionLimits(
      maximumEntryCount: 0,
      maximumFileBytes: 1,
      maximumTotalBytes: 1,
      maximumPathBytes: 1,
      maximumComponentBytes: 1,
      maximumPathDepth: 1,
      maximumExpansionRatio: 1
    )
    #expect(throws: SafeArchivePlanError.entryLimitExceeded(limit: 0, actual: 1)) {
      try SafeArchivePlanner.plan(entries: [entry("a")], archiveByteSize: 1, limits: limits)
    }

    let pathLimits = SafeExtractionLimits(
      maximumEntryCount: 10,
      maximumFileBytes: 1,
      maximumTotalBytes: 1,
      maximumPathBytes: 10,
      maximumComponentBytes: 1,
      maximumPathDepth: 1,
      maximumExpansionRatio: 1
    )
    #expect(throws: SafeArchivePlanError.componentByteLimitExceeded(limit: 1, actual: 2)) {
      try SafeArchivePlanner.plan(entries: [entry("ab")], archiveByteSize: 1, limits: pathLimits)
    }
    #expect(throws: SafeArchivePlanError.pathDepthLimitExceeded(limit: 1, actual: 2)) {
      try SafeArchivePlanner.plan(entries: [entry("a/b")], archiveByteSize: 1, limits: pathLimits)
    }
  }

  @Test
  func enforcesFileTotalAndExpansionLimits() {
    let fileLimits = limitsWith(fileBytes: 1, totalBytes: 10, ratio: 10)
    #expect(throws: SafeArchivePlanError.fileSizeLimitExceeded(limit: 1, actual: 2)) {
      try SafeArchivePlanner.plan(
        entries: [entry("file", size: 2)],
        archiveByteSize: 1,
        limits: fileLimits
      )
    }

    let totalLimits = limitsWith(fileBytes: 10, totalBytes: 3, ratio: 10)
    #expect(throws: SafeArchivePlanError.totalSizeLimitExceeded(limit: 3, actual: 4)) {
      try SafeArchivePlanner.plan(
        entries: [entry("a", size: 2), entry("b", size: 2)],
        archiveByteSize: 1,
        limits: totalLimits
      )
    }

    let ratioLimits = limitsWith(fileBytes: 10, totalBytes: 10, ratio: 2)
    #expect(
      throws: SafeArchivePlanError.expansionRatioExceeded(
        limit: 2,
        archiveBytes: 1,
        expandedBytes: 3
      )
    ) {
      try SafeArchivePlanner.plan(
        entries: [entry("file", size: 3)],
        archiveByteSize: 1,
        limits: ratioLimits
      )
    }
  }

  @Test
  func rejectsZeroArchiveSizeAndCheckedArithmeticOverflow() {
    #expect(throws: SafeArchivePlanError.invalidArchiveByteSize) {
      try SafeArchivePlanner.plan(entries: [], archiveByteSize: 0)
    }

    let limits = limitsWith(
      fileBytes: UInt64.max,
      totalBytes: UInt64.max,
      ratio: 2
    )
    #expect(throws: SafeArchivePlanError.arithmeticOverflow) {
      try SafeArchivePlanner.plan(entries: [], archiveByteSize: UInt64.max, limits: limits)
    }
    #expect(throws: SafeArchivePlanError.arithmeticOverflow) {
      try SafeArchivePlanner.plan(
        entries: [entry("a", size: UInt64.max), entry("b", size: 1)],
        archiveByteSize: 1,
        limits: limits
      )
    }
  }

  @Test
  func planIsStableAcrossInputPermutations() throws {
    let first = entry("z/file", size: 2, permissions: 0o755)
    let second = entry("a/file", size: 3, permissions: 0o644)
    let forward = try SafeArchivePlanner.plan(
      entries: [first, second],
      archiveByteSize: 5
    )
    let reverse = try SafeArchivePlanner.plan(
      entries: [second, first],
      archiveByteSize: 5
    )
    #expect(forward == reverse)
  }

  @Test
  func validationErrorIsStableForEqualPathAndKindSortKeys() {
    let validShape = entry("same", size: 1)
    let unexpectedLink = entry("same", size: 1, linkTarget: "target")
    let forward = capturedError([validShape, unexpectedLink])
    let reverse = capturedError([unexpectedLink, validShape])
    #expect(forward == .unexpectedLinkTarget)
    #expect(reverse == forward)

    let unsafeMode = entry("same", size: 1, permissions: 0o4755)
    let oversized = entry("same", size: 2)
    let limits = limitsWith(fileBytes: 1)
    #expect(capturedError([unsafeMode, oversized], limits: limits) == .unsafePermissions)
    #expect(capturedError([oversized, unsafeMode], limits: limits) == .unsafePermissions)
  }

  @Test
  func everyZeroLimitDeniesItsCorrespondingResource() {
    #expect(
      capturedError(
        [entry("a", size: 1)],
        limits: limitsWith(fileBytes: 0)
      ) == .fileSizeLimitExceeded(limit: 0, actual: 1)
    )
    #expect(
      capturedError(
        [entry("a", size: 1)],
        limits: limitsWith(totalBytes: 0)
      ) == .totalSizeLimitExceeded(limit: 0, actual: 1)
    )

    let zeroPath = SafeExtractionLimits(
      maximumEntryCount: 1,
      maximumFileBytes: 1,
      maximumTotalBytes: 1,
      maximumPathBytes: 0,
      maximumComponentBytes: 1,
      maximumPathDepth: 1,
      maximumExpansionRatio: 1
    )
    #expect(
      capturedError([entry("a")], limits: zeroPath)
        == .pathByteLimitExceeded(limit: 0, actual: 1)
    )

    let zeroComponent = SafeExtractionLimits(
      maximumEntryCount: 1,
      maximumFileBytes: 1,
      maximumTotalBytes: 1,
      maximumPathBytes: 1,
      maximumComponentBytes: 0,
      maximumPathDepth: 1,
      maximumExpansionRatio: 1
    )
    #expect(
      capturedError([entry("a")], limits: zeroComponent)
        == .componentByteLimitExceeded(limit: 0, actual: 1)
    )

    let zeroDepth = SafeExtractionLimits(
      maximumEntryCount: 1,
      maximumFileBytes: 1,
      maximumTotalBytes: 1,
      maximumPathBytes: 1,
      maximumComponentBytes: 1,
      maximumPathDepth: 0,
      maximumExpansionRatio: 1
    )
    #expect(
      capturedError([entry("a")], limits: zeroDepth)
        == .pathDepthLimitExceeded(limit: 0, actual: 1)
    )
    #expect(
      capturedError(
        [entry("a", size: 1)],
        limits: limitsWith(ratio: 0)
      ) == .expansionRatioExceeded(limit: 0, archiveBytes: 1, expandedBytes: 1)
    )
  }

  @Test
  func sourcePathDigestBindsRawPathBeforeNormalization() throws {
    let plan = try SafeArchivePlanner.plan(
      entries: [
        entry("folder/", kind: .directory),
        entry("cafe\u{301}.txt"),
      ],
      archiveByteSize: 1
    )
    let byPath = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.relativePath, $0) })
    #expect(
      byPath["folder"]?.sourcePathSHA256
        == "868cb515dd345cf15efd8fe9fc49c3361b13b086d8b532b0948b707556e7e1ec"
    )
    #expect(
      byPath["café.txt"]?.sourcePathSHA256
        == "da33d471fceb496fca38f333c2169a3ebc666a5fb12f044cb617c87eac1f54ff"
    )
  }

  private func entry(
    _ path: String,
    kind: ArchiveEntryKind = .regularFile,
    size: UInt64 = 0,
    permissions: UInt32 = 0o644,
    linkTarget: String? = nil
  ) -> ArchiveEntryDescriptor {
    ArchiveEntryDescriptor(
      path: path,
      kind: kind,
      declaredSize: size,
      permissions: permissions,
      linkTarget: linkTarget
    )
  }

  private func limitsWith(
    entryCount: Int = 10,
    fileBytes: UInt64 = 10,
    totalBytes: UInt64 = 10,
    ratio: UInt64 = 10
  ) -> SafeExtractionLimits {
    SafeExtractionLimits(
      maximumEntryCount: entryCount,
      maximumFileBytes: fileBytes,
      maximumTotalBytes: totalBytes,
      maximumPathBytes: 100,
      maximumComponentBytes: 100,
      maximumPathDepth: 10,
      maximumExpansionRatio: ratio
    )
  }

  private func capturedError(
    _ entries: [ArchiveEntryDescriptor],
    limits: SafeExtractionLimits = .default
  ) -> SafeArchivePlanError? {
    do {
      _ = try SafeArchivePlanner.plan(
        entries: entries,
        archiveByteSize: 1,
        limits: limits
      )
      return nil
    } catch let error as SafeArchivePlanError {
      return error
    } catch {
      Issue.record("Unexpected error: \(error)")
      return nil
    }
  }
}

extension Collection {
  fileprivate var single: Element? { count == 1 ? first : nil }
}
