import Foundation

enum ChunkEntryKind: Equatable, Sendable {
  case file
  case directory
}

struct SemanticChunkObject: Equatable, Sendable {
  let id: String
  let compressedBytes: UInt64
  let uncompressedBytes: UInt64
  let uncompressedMD5: String
  let compressedXXHash: UInt64
  let wireField7OpaqueHash: String?

  init(
    id: String,
    compressedBytes: UInt64,
    uncompressedBytes: UInt64,
    uncompressedMD5: String,
    compressedXXHash: UInt64,
    wireField7OpaqueHash: String? = nil
  ) throws {
    _ = try ManifestReferenceID(id)
    guard compressedBytes > 0, uncompressedBytes > 0,
      let md5 = ManifestSemanticValidation.normalizedMD5(uncompressedMD5)
    else {
      throw ManifestAdapterError.invalidManifest
    }
    if let wireField7OpaqueHash {
      guard wireField7OpaqueHash.utf8.count == 32,
        wireField7OpaqueHash.utf8.allSatisfy({
          (48...57).contains($0) || (97...102).contains($0)
        })
      else {
        throw ManifestAdapterError.invalidManifest
      }
    }
    self.id = id
    self.compressedBytes = compressedBytes
    self.uncompressedBytes = uncompressedBytes
    self.uncompressedMD5 = md5
    self.compressedXXHash = compressedXXHash
    self.wireField7OpaqueHash = wireField7OpaqueHash
  }
}

struct SemanticChunkReference: Equatable, Sendable {
  let object: SemanticChunkObject
  let fileOffset: UInt64
}

struct SemanticChunkFile: Equatable, Sendable {
  let path: String
  let kind: ChunkEntryKind
  let installedBytes: UInt64
  let wholeMD5: String?
  let references: [SemanticChunkReference]
}

struct SemanticChunkManifest: Equatable, Sendable {
  let files: [SemanticChunkFile]
}

struct ValidatedChunkReference: Equatable, Sendable {
  let objectID: String
  let fileOffset: UInt64
}

struct ValidatedChunkFile: Equatable, Sendable {
  let path: String
  let kind: ChunkEntryKind
  let installedBytes: UInt64
  let wholeMD5: String?
  let references: [ValidatedChunkReference]
}

struct ValidatedChunkManifest: Equatable, Sendable {
  let summary: ChunkManifest
  let files: [ValidatedChunkFile]
  let objects: [SemanticChunkObject]
}

enum ChunkManifestValidator {
  private static let maximumFileCount = 100_000
  private static let maximumReferenceCount = 1_000_000

  static func validate(
    category: ResourceCategory,
    candidate: SemanticChunkManifest
  ) throws -> ValidatedChunkManifest {
    guard category == .game, !candidate.files.isEmpty,
      candidate.files.count <= maximumFileCount
    else {
      throw ManifestAdapterError.invalidManifest
    }
    var inputReferenceCount = 0
    for file in candidate.files {
      let (nextCount, overflow) = inputReferenceCount.addingReportingOverflow(
        file.references.count)
      guard !overflow, nextCount <= maximumReferenceCount else {
        throw ManifestAdapterError.invalidManifest
      }
      inputReferenceCount = nextCount
    }
    var canonicalPaths: [String: ChunkEntryKind] = [:]
    var normalizedFiles: [ValidatedChunkFile] = []
    var objectsByID: [String: SemanticChunkObject] = [:]
    var fileCount: UInt64 = 0
    var directoryCount: UInt64 = 0
    var referenceCount: UInt64 = 0
    var targetInstalledBytes: UInt64 = 0
    var referencedCompressedBytes: UInt64 = 0

    for file in candidate.files {
      let path = try ManifestSemanticValidation.normalizeArchivePath(
        file.path,
        kind: file.kind == .file ? .file : .directory
      )
      let canonical = ManifestSemanticValidation.canonicalPath(path)
      guard canonicalPaths[canonical] == nil else {
        throw ManifestAdapterError.invalidManifest
      }
      canonicalPaths[canonical] = file.kind
      switch file.kind {
      case .directory:
        guard file.installedBytes == 0, file.wholeMD5 == nil, file.references.isEmpty else {
          throw ManifestAdapterError.invalidManifest
        }
        directoryCount = try ManifestSemanticValidation.checkedAdd(directoryCount, 1)
        normalizedFiles.append(
          ValidatedChunkFile(
            path: path, kind: .directory, installedBytes: 0,
            wholeMD5: nil, references: []))
      case .file:
        guard let wholeMD5 = file.wholeMD5.flatMap(ManifestSemanticValidation.normalizedMD5),
          file.installedBytes == 0 || !file.references.isEmpty
        else {
          throw ManifestAdapterError.invalidManifest
        }
        var validatedReferences: [ValidatedChunkReference] = []
        var ranges: [(start: UInt64, end: UInt64)] = []
        for reference in file.references {
          let object = reference.object
          if let existing = objectsByID[object.id], existing != object {
            throw ManifestAdapterError.invalidManifest
          }
          objectsByID[object.id] = object
          let (end, overflow) = reference.fileOffset.addingReportingOverflow(
            object.uncompressedBytes)
          guard !overflow, end <= file.installedBytes else {
            throw ManifestAdapterError.invalidManifest
          }
          ranges.append((reference.fileOffset, end))
          validatedReferences.append(
            ValidatedChunkReference(
              objectID: object.id,
              fileOffset: reference.fileOffset
            ))
          referenceCount = try ManifestSemanticValidation.checkedAdd(referenceCount, 1)
          referencedCompressedBytes = try ManifestSemanticValidation.checkedAdd(
            referencedCompressedBytes,
            object.compressedBytes
          )
        }
        ranges.sort { $0.start < $1.start }
        if file.installedBytes == 0 {
          guard ranges.isEmpty else { throw ManifestAdapterError.invalidManifest }
        } else {
          guard ranges.first?.start == 0, ranges.last?.end == file.installedBytes else {
            throw ManifestAdapterError.invalidManifest
          }
          if ranges.count > 1 {
            for index in 1..<ranges.count where ranges[index].start != ranges[index - 1].end {
              throw ManifestAdapterError.invalidManifest
            }
          }
        }
        validatedReferences.sort { $0.fileOffset < $1.fileOffset }
        fileCount = try ManifestSemanticValidation.checkedAdd(fileCount, 1)
        targetInstalledBytes = try ManifestSemanticValidation.checkedAdd(
          targetInstalledBytes, file.installedBytes)
        normalizedFiles.append(
          ValidatedChunkFile(
            path: path, kind: .file, installedBytes: file.installedBytes,
            wholeMD5: wholeMD5, references: validatedReferences))
      }
    }

    for path in canonicalPaths.keys {
      let components = path.split(separator: "/", omittingEmptySubsequences: false)
      guard components.count > 1 else { continue }
      var ancestor = String(components[0])
      for component in components.dropFirst().dropLast() {
        if canonicalPaths[ancestor] == .file {
          throw ManifestAdapterError.invalidManifest
        }
        ancestor += "/" + component
      }
      if canonicalPaths[ancestor] == .file {
        throw ManifestAdapterError.invalidManifest
      }
    }
    var uniqueCompressedBytes: UInt64 = 0
    for object in objectsByID.values {
      uniqueCompressedBytes = try ManifestSemanticValidation.checkedAdd(
        uniqueCompressedBytes, object.compressedBytes)
    }
    guard let uniqueCount = UInt64(exactly: objectsByID.count) else {
      throw ManifestAdapterError.invalidManifest
    }
    let sizes = try ManifestInspectionFactory.makeChunkSizeSummary(
      targetInstalledBytes: targetInstalledBytes,
      referencedChunkCompressedBytes: referencedCompressedBytes,
      uniqueChunkObjectBytes: uniqueCompressedBytes
    )
    let summary = try ManifestInspectionFactory.makeChunkManifest(
      fileCount: fileCount,
      directoryCount: directoryCount,
      chunkReferenceCount: referenceCount,
      uniqueChunkObjectCount: uniqueCount,
      sizes: sizes
    )
    normalizedFiles.sort { ManifestSemanticValidation.utf8Less($0.path, $1.path) }
    let objects = objectsByID.values.sorted {
      ManifestSemanticValidation.utf8Less($0.id, $1.id)
    }
    return ValidatedChunkManifest(summary: summary, files: normalizedFiles, objects: objects)
  }
}
