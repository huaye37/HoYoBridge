import Foundation

struct SemanticSelectedPatchObject: Equatable, Sendable {
  let id: String
  let objectBytes: UInt64
  let remoteName: String

  init(id: String, objectBytes: UInt64, remoteName: String) throws {
    _ = try ManifestReferenceID(id)
    _ = try ManifestReferenceID(remoteName)
    guard objectBytes > 0 else {
      throw ManifestAdapterError.invalidManifest
    }
    self.id = id
    self.objectBytes = objectBytes
    self.remoteName = remoteName
  }
}

struct SemanticSelectedPatchSlice: Equatable, Sendable {
  let object: SemanticSelectedPatchObject
  let patchOffset: UInt64
  let patchLength: UInt64
  let originalBytes: UInt64
  let originalMD5: String
  let buildID: String
  let originalName: String

  init(
    object: SemanticSelectedPatchObject,
    patchOffset: UInt64,
    patchLength: UInt64,
    originalBytes: UInt64,
    originalMD5: String,
    buildID: String,
    originalName: String
  ) throws {
    guard patchLength > 0,
      let normalizedMD5 = ManifestSemanticValidation.normalizedMD5(originalMD5),
      ManifestSemanticValidation.isOpaque(buildID, maximumBytes: 256)
    else {
      throw ManifestAdapterError.invalidManifest
    }
    let normalizedOriginalName = try ManifestSemanticValidation.normalizeArchivePath(
      originalName,
      kind: .file
    )
    self.object = object
    self.patchOffset = patchOffset
    self.patchLength = patchLength
    self.originalBytes = originalBytes
    self.originalMD5 = normalizedMD5
    self.buildID = buildID
    self.originalName = normalizedOriginalName
  }
}

struct SemanticSelectedDiffFile: Equatable, Sendable {
  let path: String
  let targetBytes: UInt64
  let targetMD5: String
  let patch: SemanticSelectedPatchSlice
}

enum SemanticUnselectedDiffReason: Equatable, Sendable {
  case noPatchRecords
  case noPatchForRequestedSource
}

struct SemanticUnselectedDiffFile: Equatable, Sendable {
  let path: String
  let targetBytes: UInt64
  let targetMD5: String
  let reason: SemanticUnselectedDiffReason
}

struct SemanticSelectedDeletion: Equatable, Sendable {
  let path: String
  let originalBytes: UInt64
  let originalMD5: String?
}

struct SemanticSelectedDiffPlan: Equatable, Sendable {
  let sourceVersion: GameVersion
  let targetVersion: GameVersion
  let manifestFileRecordCount: Int
  let selectedFiles: [SemanticSelectedDiffFile]
  let unselectedFiles: [SemanticUnselectedDiffFile]
  let deletions: [SemanticSelectedDeletion]
}

struct ValidatedSelectedPatchSlice: Equatable, Sendable {
  let objectID: String
  let patchOffset: UInt64
  let patchLength: UInt64
  let originalBytes: UInt64
  let originalMD5: String
  let buildID: String
  let originalName: String
}

struct ValidatedSelectedDiffFile: Equatable, Sendable {
  let path: String
  let targetBytes: UInt64
  let targetMD5: String
  let patch: ValidatedSelectedPatchSlice
}

struct ValidatedUnselectedDiffFile: Equatable, Sendable {
  let path: String
  let targetBytes: UInt64
  let targetMD5: String
  let reason: SemanticUnselectedDiffReason
}

struct ValidatedSelectedDeletion: Equatable, Sendable {
  let path: String
  let originalBytes: UInt64
  let originalMD5: String?
}

struct ValidatedLdiffSelection: Equatable, Sendable {
  let selection: LdiffSelection
  let selectedFiles: [ValidatedSelectedDiffFile]
  let unselectedFiles: [ValidatedUnselectedDiffFile]
  let deletions: [ValidatedSelectedDeletion]
  let objects: [SemanticSelectedPatchObject]
}

enum LdiffSelectionValidator {
  private static let maximumEntryCount = 100_000

  static func validate(
    category: ResourceCategory,
    candidate: SemanticSelectedDiffPlan
  ) throws -> ValidatedLdiffSelection {
    let (computedManifestCount, manifestOverflow) = candidate.selectedFiles.count
      .addingReportingOverflow(candidate.unselectedFiles.count)
    let (totalEntryCount, totalOverflow) = candidate.manifestFileRecordCount
      .addingReportingOverflow(candidate.deletions.count)
    guard category == .game, candidate.sourceVersion != candidate.targetVersion,
      candidate.manifestFileRecordCount >= 0, !manifestOverflow,
      computedManifestCount == candidate.manifestFileRecordCount,
      !totalOverflow, totalEntryCount <= maximumEntryCount
    else {
      throw ManifestAdapterError.invalidManifest
    }

    var canonicalPaths = Set<String>()
    var objectsByID: [String: SemanticSelectedPatchObject] = [:]
    var selectedFiles: [ValidatedSelectedDiffFile] = []
    var unselectedFiles: [ValidatedUnselectedDiffFile] = []
    var deletions: [ValidatedSelectedDeletion] = []

    for file in candidate.selectedFiles {
      let path = try normalizedUniquePath(file.path, in: &canonicalPaths)
      guard let targetMD5 = ManifestSemanticValidation.normalizedMD5(file.targetMD5),
        ManifestSemanticValidation.normalizedMD5(file.patch.originalMD5)
          == file.patch.originalMD5
      else {
        throw ManifestAdapterError.invalidManifest
      }
      let end = try ManifestSemanticValidation.checkedAdd(
        file.patch.patchOffset, file.patch.patchLength)
      guard file.patch.patchLength > 0, end <= file.patch.object.objectBytes else {
        throw ManifestAdapterError.invalidManifest
      }
      if let existing = objectsByID[file.patch.object.id], existing != file.patch.object {
        throw ManifestAdapterError.invalidManifest
      }
      objectsByID[file.patch.object.id] = file.patch.object
      selectedFiles.append(
        ValidatedSelectedDiffFile(
          path: path,
          targetBytes: file.targetBytes,
          targetMD5: targetMD5,
          patch: ValidatedSelectedPatchSlice(
            objectID: file.patch.object.id,
            patchOffset: file.patch.patchOffset,
            patchLength: file.patch.patchLength,
            originalBytes: file.patch.originalBytes,
            originalMD5: file.patch.originalMD5,
            buildID: file.patch.buildID,
            originalName: file.patch.originalName
          )
        ))
    }

    for file in candidate.unselectedFiles {
      let path = try normalizedUniquePath(file.path, in: &canonicalPaths)
      guard let targetMD5 = ManifestSemanticValidation.normalizedMD5(file.targetMD5) else {
        throw ManifestAdapterError.invalidManifest
      }
      unselectedFiles.append(
        ValidatedUnselectedDiffFile(
          path: path,
          targetBytes: file.targetBytes,
          targetMD5: targetMD5,
          reason: file.reason
        ))
    }

    for deletion in candidate.deletions {
      let path = try normalizedUniquePath(deletion.path, in: &canonicalPaths)
      let originalMD5: String?
      if let value = deletion.originalMD5 {
        guard let normalized = ManifestSemanticValidation.normalizedMD5(value) else {
          throw ManifestAdapterError.invalidManifest
        }
        originalMD5 = normalized
      } else {
        originalMD5 = nil
      }
      deletions.append(
        ValidatedSelectedDeletion(
          path: path,
          originalBytes: deletion.originalBytes,
          originalMD5: originalMD5
        ))
    }
    try rejectFileAncestors(canonicalPaths)

    var selectedPatchObjectBytes: UInt64 = 0
    for object in objectsByID.values {
      selectedPatchObjectBytes = try ManifestSemanticValidation.checkedAdd(
        selectedPatchObjectBytes, object.objectBytes)
    }
    guard let manifestFileRecordCount = UInt64(exactly: candidate.manifestFileRecordCount),
      let selectedPatchFileCount = UInt64(exactly: selectedFiles.count),
      let unselectedFileCount = UInt64(exactly: unselectedFiles.count),
      let selectedDeletionCount = UInt64(exactly: deletions.count),
      let uniquePatchObjectCount = UInt64(exactly: objectsByID.count)
    else {
      throw ManifestAdapterError.invalidManifest
    }
    let summary = try ManifestInspectionFactory.makeLdiffSelectionSummary(
      manifestFileRecordCount: manifestFileRecordCount,
      selectedPatchFileCount: selectedPatchFileCount,
      fileRecordsWithoutSelectedPatchCount: unselectedFileCount,
      selectedDeletionCount: selectedDeletionCount,
      uniquePatchObjectCount: uniquePatchObjectCount,
      selectedPatchObjectBytes: selectedPatchObjectBytes
    )
    let selection = try ManifestInspectionFactory.makeLdiffSelection(
      sourceVersion: candidate.sourceVersion,
      targetVersion: candidate.targetVersion,
      categories: [.game: summary]
    )
    selectedFiles.sort { ManifestSemanticValidation.utf8Less($0.path, $1.path) }
    unselectedFiles.sort { ManifestSemanticValidation.utf8Less($0.path, $1.path) }
    deletions.sort { ManifestSemanticValidation.utf8Less($0.path, $1.path) }
    let objects = objectsByID.values.sorted {
      ManifestSemanticValidation.utf8Less($0.id, $1.id)
    }
    return ValidatedLdiffSelection(
      selection: selection,
      selectedFiles: selectedFiles,
      unselectedFiles: unselectedFiles,
      deletions: deletions,
      objects: objects
    )
  }

  private static func normalizedUniquePath(
    _ rawPath: String,
    in canonicalPaths: inout Set<String>
  ) throws -> String {
    let path = try ManifestSemanticValidation.normalizeArchivePath(rawPath, kind: .file)
    let canonical = ManifestSemanticValidation.canonicalPath(path)
    guard canonicalPaths.insert(canonical).inserted else {
      throw ManifestAdapterError.invalidManifest
    }
    return path
  }

  private static func rejectFileAncestors(_ paths: Set<String>) throws {
    for path in paths {
      let components = path.split(separator: "/", omittingEmptySubsequences: false)
      guard components.count > 1 else { continue }
      var ancestor = String(components[0])
      for component in components.dropFirst().dropLast() {
        if paths.contains(ancestor) { throw ManifestAdapterError.invalidManifest }
        ancestor += "/" + component
      }
      if paths.contains(ancestor) { throw ManifestAdapterError.invalidManifest }
    }
  }
}
