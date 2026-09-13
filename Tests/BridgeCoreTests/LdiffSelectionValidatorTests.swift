import Foundation
import Testing

@testable import BridgeCore

struct LdiffSelectionValidatorTests {
  @Test
  func validatesSelectedUnselectedDeletionSummaryAndPermutation() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let shared = try object("shared", bytes: 100)
    let selectedA = try selected("Data/a", object: shared, targetMD5: uppercaseMD5)
    let selectedB = try selected("Data/b", object: shared)
    let noRecords = unselected("Data/new", reason: .noPatchRecords)
    let otherSource = unselected(
      "Data/unchanged", reason: .noPatchForRequestedSource)
    let deletion = SemanticSelectedDeletion(
      path: "old/file", originalBytes: 4, originalMD5: uppercaseMD5)
    let first = SemanticSelectedDiffPlan(
      sourceVersion: source, targetVersion: target, manifestFileRecordCount: 4,
      selectedFiles: [selectedB, selectedA],
      unselectedFiles: [otherSource, noRecords], deletions: [deletion])
    let second = SemanticSelectedDiffPlan(
      sourceVersion: source, targetVersion: target, manifestFileRecordCount: 4,
      selectedFiles: [selectedA, selectedB],
      unselectedFiles: [noRecords, otherSource], deletions: [deletion])

    let validated = try validate(first)
    let permuted = try validate(second)
    #expect(validated == permuted)
    #expect(validated.selectedFiles.map(\.path) == ["Data/a", "Data/b"])
    #expect(validated.unselectedFiles.map(\.path) == ["Data/new", "Data/unchanged"])
    #expect(
      validated.unselectedFiles.map(\.reason) == [
        .noPatchRecords, .noPatchForRequestedSource,
      ])
    #expect(validated.deletions[0].originalMD5 == md5)
    #expect(validated.objects.map(\.id) == ["shared"])
    let summary = try #require(validated.selection.categories[.game])
    #expect(summary.manifestFileRecordCount == 4)
    #expect(summary.selectedPatchFileCount == 2)
    #expect(summary.fileRecordsWithoutSelectedPatchCount == 2)
    #expect(summary.selectedDeletionCount == 1)
    #expect(summary.uniquePatchObjectCount == 1)
    #expect(summary.selectedPatchObjectBytes == 100)
  }

  @Test
  func allowsEmptyAndUnselectedOnlySelections() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let empty = try validate(
      SemanticSelectedDiffPlan(
        sourceVersion: source, targetVersion: target, manifestFileRecordCount: 0,
        selectedFiles: [], unselectedFiles: [], deletions: []))
    let emptySummary = try #require(empty.selection.categories[.game])
    #expect(
      emptySummary
        == LdiffSelectionSummary(
          manifestFileRecordCount: 0, selectedPatchFileCount: 0,
          fileRecordsWithoutSelectedPatchCount: 0, selectedDeletionCount: 0,
          uniquePatchObjectCount: 0, selectedPatchObjectBytes: 0))

    let onlyUnselected = try validate(
      SemanticSelectedDiffPlan(
        sourceVersion: source, targetVersion: target, manifestFileRecordCount: 2,
        selectedFiles: [],
        unselectedFiles: [
          unselected("a", reason: .noPatchRecords),
          unselected("b", reason: .noPatchForRequestedSource),
        ], deletions: []))
    let summary = try #require(onlyUnselected.selection.categories[.game])
    #expect(summary.manifestFileRecordCount == 2)
    #expect(summary.selectedPatchFileCount == 0)
    #expect(summary.fileRecordsWithoutSelectedPatchCount == 2)
    #expect(summary.selectedPatchObjectBytes == 0)
  }

  @Test
  func validatesDeletionOnlyWithOptionalHash() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let result = try validate(
      SemanticSelectedDiffPlan(
        sourceVersion: source, targetVersion: target, manifestFileRecordCount: 0,
        selectedFiles: [], unselectedFiles: [],
        deletions: [
          SemanticSelectedDeletion(
            path: "old", originalBytes: 0, originalMD5: nil)
        ]))
    #expect(result.deletions[0].originalMD5 == nil)
    #expect(result.selection.categories[.game]?.selectedDeletionCount == 1)
  }

  @Test
  func rejectsCountMismatchSameVersionAndEntryCap() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        SemanticSelectedDiffPlan(
          sourceVersion: source, targetVersion: target, manifestFileRecordCount: 1,
          selectedFiles: [], unselectedFiles: [], deletions: []))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        SemanticSelectedDiffPlan(
          sourceVersion: source, targetVersion: source, manifestFileRecordCount: 0,
          selectedFiles: [], unselectedFiles: [], deletions: []))
    }
    let repeated = Array(
      repeating: unselected("same", reason: .noPatchRecords), count: 100_001)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        SemanticSelectedDiffPlan(
          sourceVersion: source, targetVersion: target,
          manifestFileRecordCount: repeated.count,
          selectedFiles: [], unselectedFiles: repeated, deletions: []))
    }
  }

  @Test
  func rejectsUnsafeCollisionAndAncestorAcrossFullUnion() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let object = try object("object", bytes: 4)
    let candidates = try [
      plan(
        source, target, selected: [selected("Data/A", object: object)],
        unselected: [unselected("data/a", reason: .noPatchRecords)]),
      plan(
        source, target, selected: [selected("a/b", object: object)],
        deletions: [
          SemanticSelectedDeletion(
            path: "a", originalBytes: 1, originalMD5: md5)
        ]),
      plan(
        source, target, selected: [selected("a", object: object)],
        unselected: [unselected("a/b", reason: .noPatchForRequestedSource)]),
    ]
    for candidate in candidates {
      #expect(throws: ManifestAdapterError.invalidManifest) { try validate(candidate) }
    }
    for path in ["/a", "../a", "a\\b", "a:b", "~a", "trailing."] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try validate(
          try plan(
            source, target, selected: [selected(path, object: object)]))
      }
    }
  }

  @Test
  func rejectsInvalidHashesRangesAndObjectConflicts() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let bounded = try object("same", bytes: 4)
    let conflict = try object("same", bytes: 5)
    let remoteNameConflict = try object("same", bytes: 4, remoteName: "other-remote")
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        try plan(
          source, target,
          selected: [
            selected("bad", object: bounded, targetMD5: "bad")
          ]))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        try plan(
          source, target,
          selected: [
            selected("a", object: bounded, offset: 3, length: 2)
          ]))
    }
    for candidate in [conflict, remoteNameConflict] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try validate(
          try plan(
            source, target,
            selected: [
              selected("a", object: bounded), selected("b", object: candidate),
            ]))
      }
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        SemanticSelectedDiffPlan(
          sourceVersion: source, targetVersion: target, manifestFileRecordCount: 0,
          selectedFiles: [], unselectedFiles: [],
          deletions: [
            SemanticSelectedDeletion(
              path: "old", originalBytes: 1, originalMD5: "bad")
          ]))
    }
  }

  @Test
  func rejectsSelectedObjectByteOverflowAndInvalidObjectValues() throws {
    let source = try GameVersion("1.0.0")
    let target = try GameVersion("2.0.0")
    let huge = try object("huge", bytes: .max)
    let one = try object("one", bytes: 1)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(
        try plan(
          source, target,
          selected: [
            selected("a", object: huge, length: 1),
            selected("b", object: one, length: 1),
          ]))
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try SemanticSelectedPatchObject(id: "", objectBytes: 1, remoteName: "remote")
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try SemanticSelectedPatchObject(id: "id", objectBytes: 0, remoteName: "remote")
    }
    for unsafe in [".", "..", "a/b", "a?b", "a:b", "a=b", "https://invalid/token=x"] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try SemanticSelectedPatchObject(id: unsafe, objectBytes: 1, remoteName: "remote")
      }
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try SemanticSelectedPatchObject(id: "id", objectBytes: 1, remoteName: unsafe)
      }
    }
    #expect(
      Mirror(reflecting: one).children.compactMap(\.label)
        == ["id", "objectBytes", "remoteName"])
  }

  @Test
  func normalizesAndRejectsUnsafeOriginalNames() throws {
    let object = try object("object", bytes: 1)
    let normalized = try SemanticSelectedPatchSlice(
      object: object,
      patchOffset: 0,
      patchLength: 1,
      originalBytes: 1,
      originalMD5: md5,
      buildID: "build",
      originalName: "e\u{301}.bin"
    )
    #expect(normalized.originalName == "\u{00e9}.bin")
    for unsafe in ["../x", "/x", "a\\b", "a:b", "trailing."] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try SemanticSelectedPatchSlice(
          object: object,
          patchOffset: 0,
          patchLength: 1,
          originalBytes: 1,
          originalMD5: md5,
          buildID: "build",
          originalName: unsafe
        )
      }
    }
  }

  private var md5: String { String(repeating: "a", count: 32) }
  private var uppercaseMD5: String { String(repeating: "A", count: 32) }

  private func object(
    _ id: String,
    bytes: UInt64,
    remoteName: String? = nil
  ) throws -> SemanticSelectedPatchObject {
    try SemanticSelectedPatchObject(
      id: id, objectBytes: bytes, remoteName: remoteName ?? "remote-\(id)")
  }

  private func selected(
    _ path: String,
    object: SemanticSelectedPatchObject,
    targetMD5: String? = nil,
    offset: UInt64 = 0,
    length: UInt64? = nil
  ) throws -> SemanticSelectedDiffFile {
    SemanticSelectedDiffFile(
      path: path, targetBytes: 4, targetMD5: targetMD5 ?? md5,
      patch: try SemanticSelectedPatchSlice(
        object: object, patchOffset: offset, patchLength: length ?? object.objectBytes,
        originalBytes: 4, originalMD5: md5, buildID: "build",
        originalName: "original.bin"))
  }

  private func unselected(
    _ path: String,
    reason: SemanticUnselectedDiffReason
  ) -> SemanticUnselectedDiffFile {
    SemanticUnselectedDiffFile(
      path: path, targetBytes: 4, targetMD5: md5, reason: reason)
  }

  private func plan(
    _ source: GameVersion,
    _ target: GameVersion,
    selected: [SemanticSelectedDiffFile] = [],
    unselected: [SemanticUnselectedDiffFile] = [],
    deletions: [SemanticSelectedDeletion] = []
  ) throws -> SemanticSelectedDiffPlan {
    SemanticSelectedDiffPlan(
      sourceVersion: source, targetVersion: target,
      manifestFileRecordCount: selected.count + unselected.count,
      selectedFiles: selected, unselectedFiles: unselected, deletions: deletions)
  }

  private func validate(
    _ plan: SemanticSelectedDiffPlan
  ) throws -> ValidatedLdiffSelection {
    try LdiffSelectionValidator.validate(category: .game, candidate: plan)
  }
}
