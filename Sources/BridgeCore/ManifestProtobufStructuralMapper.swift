import Foundation
import SwiftProtobuf

struct ManifestProtobufStructuralChunkCapability: Equatable, Sendable {
  let receipt: ManifestProtobufWireBudgetSummary
  let candidate: SemanticChunkManifest
  let validated: ValidatedChunkManifest

  fileprivate init(
    receipt: ManifestProtobufWireBudgetSummary,
    candidate: SemanticChunkManifest,
    validated: ValidatedChunkManifest
  ) {
    self.receipt = receipt
    self.candidate = candidate
    self.validated = validated
  }
}

struct ManifestProtobufStructuralLdiffCapability: Equatable, Sendable {
  let receipt: ManifestProtobufWireBudgetSummary
  let candidate: SemanticSelectedDiffPlan
  let validated: ValidatedLdiffSelection

  fileprivate init(
    receipt: ManifestProtobufWireBudgetSummary,
    candidate: SemanticSelectedDiffPlan,
    validated: ValidatedLdiffSelection
  ) {
    self.receipt = receipt
    self.candidate = candidate
    self.validated = validated
  }
}

extension ManifestProtobufStructuralChunkCapability: ManifestReplayRedactedValue {}
extension ManifestProtobufStructuralLdiffCapability: ManifestReplayRedactedValue {}

enum ManifestProtobufStructuralMapper {
  static let requiredSchemaBaseline = "yaagl-ca78abc-sophon-protobuf-structural-v1"
  static let observedCNChunkSchemaBaseline =
    "mgb-observed-cn-sophon-protobuf-structural-v2"

  static func mapChunk(
    _ capability: ManifestZstdDecompressedCapability,
    expectedManifestReference: ManifestReferenceDigest,
    schemaBaseline: ManifestSchemaBaseline
  ) throws -> ManifestProtobufStructuralChunkCapability {
    try requireEnvelope(
      capability,
      kind: .chunkManifest,
      expectedManifestReference: expectedManifestReference,
      schemaBaseline: schemaBaseline
    )
    let receipt = try scan(capability)
    let requiresField7 = schemaBaseline.value == observedCNChunkSchemaBaseline
    return try normalizeErrors {
      let manifest: Manifest = try decode(capability.data)
      try requireNoUnknownFields(manifest)
      var counts = ManifestProtobufStructuralCounts()
      var files: [SemanticChunkFile] = []
      files.reserveCapacity(manifest.files.count)
      for (fileIndex, file) in manifest.files.enumerated() {
        try cancellationCheckpoint(fileIndex)
        try counts.addFile()
        try counts.addString(file.filename)
        try counts.addString(file.md5)
        guard let installedBytes = UInt64(exactly: file.size) else {
          throw ManifestAdapterError.invalidManifest
        }
        let kind: ChunkEntryKind
        switch file.flags {
        case 0: kind = .file
        case 64: kind = .directory
        default: throw ManifestAdapterError.schemaDrift
        }
        var references: [SemanticChunkReference] = []
        references.reserveCapacity(file.chunks.count)
        for (chunkIndex, chunk) in file.chunks.enumerated() {
          try cancellationCheckpoint(chunkIndex)
          try counts.addChunk()
          try counts.addString(chunk.chunkID)
          try counts.addString(chunk.md5)
          try counts.addString(chunk.opaqueHash)
          let wireField7OpaqueHash: String?
          if requiresField7 {
            guard !chunk.opaqueHash.isEmpty else {
              throw ManifestAdapterError.schemaDrift
            }
            wireField7OpaqueHash = chunk.opaqueHash
          } else {
            guard chunk.opaqueHash.isEmpty else {
              throw ManifestAdapterError.schemaDrift
            }
            wireField7OpaqueHash = nil
          }
          let object = try SemanticChunkObject(
            id: chunk.chunkID,
            compressedBytes: UInt64(chunk.compressedSize),
            uncompressedBytes: UInt64(chunk.uncompressedSize),
            uncompressedMD5: chunk.md5,
            compressedXXHash: chunk.xxhash,
            wireField7OpaqueHash: wireField7OpaqueHash
          )
          references.append(
            SemanticChunkReference(object: object, fileOffset: chunk.offset))
        }
        files.append(
          SemanticChunkFile(
            path: file.filename,
            kind: kind,
            installedBytes: installedBytes,
            wholeMD5: file.md5.isEmpty ? nil : file.md5,
            references: references
          ))
      }
      try counts.requireExact(receipt, capability: capability)
      let candidate = SemanticChunkManifest(files: files)
      let validated = try ChunkManifestValidator.validate(category: .game, candidate: candidate)
      try Task.checkCancellation()
      return ManifestProtobufStructuralChunkCapability(
        receipt: receipt,
        candidate: candidate,
        validated: validated
      )
    }
  }

  static func mapLdiff(
    _ capability: ManifestZstdDecompressedCapability,
    expectedManifestReference: ManifestReferenceDigest,
    schemaBaseline: ManifestSchemaBaseline,
    sourceVersion: GameVersion,
    targetVersion: GameVersion
  ) throws -> ManifestProtobufStructuralLdiffCapability {
    try requireEnvelope(
      capability,
      kind: .diffManifest,
      expectedManifestReference: expectedManifestReference,
      schemaBaseline: schemaBaseline
    )
    guard sourceVersion != targetVersion else {
      throw ManifestAdapterError.invalidManifest
    }
    let receipt = try scan(capability)
    return try normalizeErrors {
      let manifest: DiffManifest = try decode(capability.data)
      try requireNoUnknownFields(manifest)
      var counts = ManifestProtobufStructuralCounts()
      var allObjectsByID: [String: SemanticSelectedPatchObject] = [:]
      var selectedFiles: [SemanticSelectedDiffFile] = []
      var unselectedFiles: [SemanticUnselectedDiffFile] = []
      selectedFiles.reserveCapacity(manifest.files.count)
      unselectedFiles.reserveCapacity(manifest.files.count)

      for (fileIndex, file) in manifest.files.enumerated() {
        try cancellationCheckpoint(fileIndex)
        try counts.addFile()
        try counts.addString(file.filename)
        try counts.addString(file.hash)
        guard let targetBytes = UInt64(exactly: file.size) else {
          throw ManifestAdapterError.invalidManifest
        }
        var seenSources = Set<GameVersion>()
        var selectedPatch: SemanticSelectedPatchSlice?
        for (patchIndex, patch) in file.patches.enumerated() {
          try cancellationCheckpoint(patchIndex)
          try counts.addPatch(hasInfo: patch.hasInfo)
          try counts.addString(patch.key)
          guard patch.hasInfo, let patchSource = try? GameVersion(patch.key),
            patchSource != targetVersion, seenSources.insert(patchSource).inserted
          else {
            throw ManifestAdapterError.invalidManifest
          }
          let info = patch.info
          try counts.addPatchInfoStrings(info)
          guard info.tag == patch.key,
            let objectBytes = UInt64(exactly: info.patchSize),
            let patchOffset = UInt64(exactly: info.patchOffset),
            let patchLength = UInt64(exactly: info.patchLength),
            let originalBytes = UInt64(exactly: info.originalSize)
          else {
            throw ManifestAdapterError.invalidManifest
          }
          let object = try SemanticSelectedPatchObject(
            id: info.patchID,
            objectBytes: objectBytes,
            remoteName: info.patchName
          )
          if let existing = allObjectsByID[object.id], existing != object {
            throw ManifestAdapterError.invalidManifest
          }
          allObjectsByID[object.id] = object
          let slice = try SemanticSelectedPatchSlice(
            object: object,
            patchOffset: patchOffset,
            patchLength: patchLength,
            originalBytes: originalBytes,
            originalMD5: info.originalHash,
            buildID: info.buildID,
            originalName: info.originalName
          )
          let patchEnd = try ManifestSemanticValidation.checkedAdd(patchOffset, patchLength)
          guard patchEnd <= objectBytes else {
            throw ManifestAdapterError.invalidManifest
          }
          if patchSource == sourceVersion {
            guard selectedPatch == nil else {
              throw ManifestAdapterError.invalidManifest
            }
            selectedPatch = slice
          }
        }
        if let selectedPatch {
          selectedFiles.append(
            SemanticSelectedDiffFile(
              path: file.filename,
              targetBytes: targetBytes,
              targetMD5: file.hash,
              patch: selectedPatch
            ))
        } else {
          unselectedFiles.append(
            SemanticUnselectedDiffFile(
              path: file.filename,
              targetBytes: targetBytes,
              targetMD5: file.hash,
              reason: file.patches.isEmpty ? .noPatchRecords : .noPatchForRequestedSource
            ))
        }
      }

      var seenDeletionSources = Set<GameVersion>()
      var deletions: [SemanticSelectedDeletion] = []
      for (groupIndex, group) in manifest.filesDelete.enumerated() {
        try cancellationCheckpoint(groupIndex)
        try counts.addDeleteGroup(hasInfo: group.hasInfo)
        try counts.addString(group.key)
        guard group.hasInfo, let groupSource = try? GameVersion(group.key),
          groupSource != targetVersion, seenDeletionSources.insert(groupSource).inserted
        else {
          throw ManifestAdapterError.invalidManifest
        }
        var groupPaths = Set<String>()
        for (entryIndex, entry) in group.info.list.enumerated() {
          try cancellationCheckpoint(entryIndex)
          try counts.addDeleteEntry()
          try counts.addString(entry.filename)
          try counts.addString(entry.hash)
          guard let originalBytes = UInt64(exactly: entry.size) else {
            throw ManifestAdapterError.invalidManifest
          }
          let normalizedPath = try ManifestSemanticValidation.normalizeArchivePath(
            entry.filename,
            kind: .file
          )
          let canonicalPath = ManifestSemanticValidation.canonicalPath(normalizedPath)
          guard groupPaths.insert(canonicalPath).inserted else {
            throw ManifestAdapterError.invalidManifest
          }
          let normalizedMD5: String?
          if entry.hash.isEmpty {
            normalizedMD5 = nil
          } else {
            guard let value = ManifestSemanticValidation.normalizedMD5(entry.hash) else {
              throw ManifestAdapterError.invalidManifest
            }
            normalizedMD5 = value
          }
          if groupSource == sourceVersion {
            deletions.append(
              SemanticSelectedDeletion(
                path: normalizedPath,
                originalBytes: originalBytes,
                originalMD5: normalizedMD5
              ))
          }
        }
        try rejectFileAncestors(groupPaths)
      }

      try counts.requireExact(receipt, capability: capability)
      let candidate = SemanticSelectedDiffPlan(
        sourceVersion: sourceVersion,
        targetVersion: targetVersion,
        manifestFileRecordCount: manifest.files.count,
        selectedFiles: selectedFiles,
        unselectedFiles: unselectedFiles,
        deletions: deletions
      )
      let validated = try LdiffSelectionValidator.validate(category: .game, candidate: candidate)
      try Task.checkCancellation()
      return ManifestProtobufStructuralLdiffCapability(
        receipt: receipt,
        candidate: candidate,
        validated: validated
      )
    }
  }

  private static func requireEnvelope(
    _ capability: ManifestZstdDecompressedCapability,
    kind: ManifestEvidenceArtifactKind,
    expectedManifestReference: ManifestReferenceDigest,
    schemaBaseline: ManifestSchemaBaseline
  ) throws {
    try Task.checkCancellation()
    let acceptsBaseline: Bool
    switch kind {
    case .chunkManifest:
      acceptsBaseline =
        schemaBaseline.value == requiredSchemaBaseline
        || schemaBaseline.value == observedCNChunkSchemaBaseline
    case .diffManifest:
      acceptsBaseline = schemaBaseline.value == requiredSchemaBaseline
    default:
      acceptsBaseline = false
    }
    guard acceptsBaseline else {
      throw ManifestAdapterError.schemaDrift
    }
    guard capability.compressedArtifactIdentity.kind == kind,
      capability.compressedArtifactIdentity.manifestReferenceSHA256 == expectedManifestReference,
      UInt64(exactly: capability.data.count) == capability.byteSize
    else {
      throw ManifestAdapterError.invalidManifest
    }
  }

  private static func scan(
    _ capability: ManifestZstdDecompressedCapability
  ) throws -> ManifestProtobufWireBudgetSummary {
    do {
      return try ManifestProtobufWireBudgetScanner.scan(capability)
    } catch let error as CancellationError {
      throw error
    } catch ManifestProtobufWireScanningError.schemaDrift {
      throw ManifestAdapterError.schemaDrift
    } catch is ManifestProtobufWireScanningError {
      throw ManifestAdapterError.invalidManifest
    }
  }

  private static func decode<MessageType: SwiftProtobuf.Message>(
    _ data: Data
  ) throws -> MessageType {
    try Task.checkCancellation()
    var options = BinaryDecodingOptions()
    options.messageDepthLimit = 4
    options.discardUnknownFields = false
    let message = try MessageType(serializedBytes: data, options: options)
    try Task.checkCancellation()
    return message
  }

  private static func normalizeErrors<T>(_ operation: () throws -> T) throws -> T {
    do {
      return try operation()
    } catch let error as CancellationError {
      throw error
    } catch let error as ManifestAdapterError where error == .schemaDrift {
      throw error
    } catch {
      throw ManifestAdapterError.invalidManifest
    }
  }

  private static func requireNoUnknownFields(_ manifest: Manifest) throws {
    guard manifest.unknownFields.data.isEmpty else {
      throw ManifestAdapterError.schemaDrift
    }
    for file in manifest.files {
      guard file.unknownFields.data.isEmpty,
        file.chunks.allSatisfy({ $0.unknownFields.data.isEmpty })
      else {
        throw ManifestAdapterError.schemaDrift
      }
    }
  }

  private static func requireNoUnknownFields(_ manifest: DiffManifest) throws {
    guard manifest.unknownFields.data.isEmpty else {
      throw ManifestAdapterError.schemaDrift
    }
    for file in manifest.files {
      guard file.unknownFields.data.isEmpty else {
        throw ManifestAdapterError.schemaDrift
      }
      for patch in file.patches {
        guard patch.unknownFields.data.isEmpty,
          !patch.hasInfo || patch.info.unknownFields.data.isEmpty
        else {
          throw ManifestAdapterError.schemaDrift
        }
      }
    }
    for group in manifest.filesDelete {
      guard group.unknownFields.data.isEmpty,
        !group.hasInfo || group.info.unknownFields.data.isEmpty
      else {
        throw ManifestAdapterError.schemaDrift
      }
      if group.hasInfo,
        !group.info.list.allSatisfy({ $0.unknownFields.data.isEmpty })
      {
        throw ManifestAdapterError.schemaDrift
      }
    }
  }

  private static func cancellationCheckpoint(_ index: Int) throws {
    if index & 0x3FF == 0 { try Task.checkCancellation() }
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

private struct ManifestProtobufStructuralCounts {
  var fileCount: UInt64 = 0
  var chunkCount: UInt64 = 0
  var patchCount: UInt64 = 0
  var deleteGroupCount: UInt64 = 0
  var deleteEntryCount: UInt64 = 0
  var nodeCount: UInt64 = 1
  var totalStringBytes: UInt64 = 0

  mutating func addFile() throws {
    fileCount = try ManifestSemanticValidation.checkedAdd(fileCount, 1)
    nodeCount = try ManifestSemanticValidation.checkedAdd(nodeCount, 1)
  }

  mutating func addChunk() throws {
    chunkCount = try ManifestSemanticValidation.checkedAdd(chunkCount, 1)
    nodeCount = try ManifestSemanticValidation.checkedAdd(nodeCount, 1)
  }

  mutating func addPatch(hasInfo: Bool) throws {
    patchCount = try ManifestSemanticValidation.checkedAdd(patchCount, 1)
    nodeCount = try ManifestSemanticValidation.checkedAdd(nodeCount, hasInfo ? 2 : 1)
  }

  mutating func addDeleteGroup(hasInfo: Bool) throws {
    deleteGroupCount = try ManifestSemanticValidation.checkedAdd(deleteGroupCount, 1)
    nodeCount = try ManifestSemanticValidation.checkedAdd(nodeCount, hasInfo ? 2 : 1)
  }

  mutating func addDeleteEntry() throws {
    deleteEntryCount = try ManifestSemanticValidation.checkedAdd(deleteEntryCount, 1)
    nodeCount = try ManifestSemanticValidation.checkedAdd(nodeCount, 1)
  }

  mutating func addPatchInfoStrings(_ info: PatchInfo) throws {
    try addString(info.patchID)
    try addString(info.tag)
    try addString(info.buildID)
    try addString(info.patchName)
    try addString(info.originalName)
    try addString(info.originalHash)
  }

  mutating func addString(_ value: String) throws {
    guard let byteCount = UInt64(exactly: value.utf8.count) else {
      throw ManifestAdapterError.invalidManifest
    }
    totalStringBytes = try ManifestSemanticValidation.checkedAdd(totalStringBytes, byteCount)
  }

  func requireExact(
    _ receipt: ManifestProtobufWireBudgetSummary,
    capability: ManifestZstdDecompressedCapability
  ) throws {
    guard receipt.policyVersion == ManifestProtobufWireBudgetSummary.currentPolicyVersion,
      receipt.compressedArtifactIdentity == capability.compressedArtifactIdentity,
      receipt.decompressedSHA256 == capability.sha256,
      receipt.decompressedByteSize == capability.byteSize,
      receipt.fileCount == fileCount,
      receipt.chunkCount == chunkCount,
      receipt.patchCount == patchCount,
      receipt.deleteGroupCount == deleteGroupCount,
      receipt.deleteEntryCount == deleteEntryCount,
      receipt.nodeCount == nodeCount,
      receipt.totalStringBytes == totalStringBytes
    else {
      throw ManifestAdapterError.invalidManifest
    }
  }
}
