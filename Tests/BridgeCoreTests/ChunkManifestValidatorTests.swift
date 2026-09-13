import Foundation
import Testing

@testable import BridgeCore

struct ChunkManifestValidatorTests {
  @Test
  func validatesDeduplicatedSummaryAndStablePermutation() throws {
    let shared = try object(id: "object-a", compressed: 100, uncompressed: 5)
    let tail = try object(id: "object-b", compressed: 50, uncompressed: 3)
    let first = file(
      "Data/a.bin", bytes: 8,
      references: [reference(tail, at: 5), reference(shared, at: 0)])
    let second = file("Data/b.bin", bytes: 5, references: [reference(shared, at: 0)])
    let directory = SemanticChunkFile(
      path: "Data/", kind: .directory, installedBytes: 0,
      wholeMD5: nil, references: [])

    let validated = try validate([second, directory, first])
    let permuted = try validate([first, second, directory])

    #expect(validated == permuted)
    #expect(validated.files.map(\.path) == ["Data", "Data/a.bin", "Data/b.bin"])
    #expect(validated.objects.map(\.id) == ["object-a", "object-b"])
    #expect(validated.files[1].references.map(\.fileOffset) == [0, 5])
    #expect(validated.summary.fileCount == 2)
    #expect(validated.summary.directoryCount == 1)
    #expect(validated.summary.chunkReferenceCount == 3)
    #expect(validated.summary.uniqueChunkObjectCount == 2)
    #expect(validated.summary.sizes.targetInstalledBytes == 13)
    #expect(validated.summary.sizes.referencedChunkCompressedBytes == 250)
    #expect(validated.summary.sizes.uniqueChunkObjectBytes == 150)
  }

  @Test
  func rejectsUnsafePathsCollisionsAndFileAncestors() throws {
    for path in [
      "/absolute", "../escape", "a/../b", "a//b", "~user", "a\\b", "a:b",
      " leading", "trailing ", "trailing.",
      String(repeating: "a", count: 256),
      Array(repeating: "a", count: 33).joined(separator: "/"),
    ] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try validate([try coveredFile(path)])
      }
    }

    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([try coveredFile("Data/A.bin"), try coveredFile("data/a.BIN")])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([try coveredFile("\u{00e9}/a"), try coveredFile("e\u{301}/a")])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([try coveredFile("a/b"), try coveredFile("a")])
    }

    let implicitDirectory = try validate([try coveredFile("a/b")])
    #expect(implicitDirectory.files.map(\.path) == ["a/b"])
    let normalized = try validate([try coveredFile("e\u{301}/file")])
    #expect(normalized.files.map(\.path) == ["\u{00e9}/file"])
  }

  @Test
  func rejectsConflictingDefinitionsForTheSameObjectID() throws {
    let original = try object(id: "shared", compressed: 4, uncompressed: 4)
    let conflict = try object(id: "shared", compressed: 5, uncompressed: 4)
    let xxhashConflict = try object(
      id: "shared", compressed: 4, uncompressed: 4, xxhash: .max)
    let field7Conflict = try object(
      id: "shared",
      compressed: 4,
      uncompressed: 4,
      field7: String(repeating: "c", count: 32)
    )
    for candidate in [conflict, xxhashConflict, field7Conflict] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try validate([
          file("a", bytes: 4, references: [reference(original, at: 0)]),
          file("b", bytes: 4, references: [reference(candidate, at: 0)]),
        ])
      }
    }
  }

  @Test
  func rejectsOverflowOutOfRangeOverlapAndSparseRanges() throws {
    let two = try object(id: "two", compressed: 2, uncompressed: 2)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([
        file(
          "overflow", bytes: .max,
          references: [reference(two, at: .max)])
      ])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([file("short", bytes: 1, references: [reference(two, at: 0)])])
    }

    let five = try object(id: "five", compressed: 5, uncompressed: 5)
    let four = try object(id: "four", compressed: 4, uncompressed: 4)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([
        file(
          "overlap", bytes: 8,
          references: [reference(five, at: 0), reference(four, at: 4)])
      ])
    }

    for sparse in [
      file("leading-gap", bytes: 3, references: [reference(two, at: 1)]),
      file("trailing-gap", bytes: 3, references: [reference(two, at: 0)]),
      file(
        "middle-gap", bytes: 5,
        references: [reference(two, at: 0), reference(two, at: 3)]),
    ] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try validate([sparse])
      }
    }
  }

  @Test
  func enforcesDirectoryAndFileSemantics() throws {
    let object = try object(id: "content", compressed: 4, uncompressed: 4)
    let valid = file("valid", bytes: 4, references: [reference(object, at: 0)])
    let invalidDirectories = [
      SemanticChunkFile(
        path: "dir-a", kind: .directory, installedBytes: 1,
        wholeMD5: nil, references: []),
      SemanticChunkFile(
        path: "dir-b", kind: .directory, installedBytes: 0,
        wholeMD5: md5, references: []),
      SemanticChunkFile(
        path: "dir-c", kind: .directory, installedBytes: 0,
        wholeMD5: nil, references: [reference(object, at: 0)]),
    ]
    for directory in invalidDirectories {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try validate([valid, directory])
      }
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([file("missing-refs", bytes: 1, references: [])])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([
        SemanticChunkFile(
          path: "bad-hash", kind: .file, installedBytes: 0,
          wholeMD5: "not-an-md5", references: [])
      ])
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([file("file/", bytes: 4, references: [reference(object, at: 0)])])
    }

    let empty = file("empty", bytes: 0, references: [])
    let result = try validate([valid, empty])
    #expect(result.files.first(where: { $0.path == "empty" })?.installedBytes == 0)
  }

  @Test
  func rejectsAggregateOverflowAndOversizedEntrySet() throws {
    let huge = try object(id: "huge", compressed: 1, uncompressed: .max)
    let one = try object(id: "one", compressed: 1, uncompressed: 1)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([
        file("huge", bytes: .max, references: [reference(huge, at: 0)]),
        file("one", bytes: 1, references: [reference(one, at: 0)]),
      ])
    }

    let hugeCompressed = try object(id: "compressed-huge", compressed: .max, uncompressed: 1)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate([
        file("a", bytes: 1, references: [reference(hugeCompressed, at: 0)]),
        file("b", bytes: 1, references: [reference(one, at: 0)]),
      ])
    }

    let directory = SemanticChunkFile(
      path: "dir", kind: .directory, installedBytes: 0,
      wholeMD5: nil, references: [])
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try validate(Array(repeating: directory, count: 100_001))
    }
  }

  @Test
  func validatesOpaqueIDsXXHashAndMD5Normalization() throws {
    let uppercase = try SemanticChunkObject(
      id: "object", compressedBytes: 1, uncompressedBytes: 1,
      uncompressedMD5: String(repeating: "A", count: 32), compressedXXHash: 0)
    #expect(uppercase.uncompressedMD5 == md5)
    #expect(uppercase.compressedXXHash == 0)
    let observed = try SemanticChunkObject(
      id: "observed",
      compressedBytes: 1,
      uncompressedBytes: 1,
      uncompressedMD5: md5,
      compressedXXHash: 0,
      wireField7OpaqueHash: String(repeating: "c", count: 32)
    )
    #expect(observed.wireField7OpaqueHash == String(repeating: "c", count: 32))
    for invalidField7 in ["bad", String(repeating: "C", count: 32)] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try SemanticChunkObject(
          id: "observed",
          compressedBytes: 1,
          uncompressedBytes: 1,
          uncompressedMD5: md5,
          compressedXXHash: 0,
          wireField7OpaqueHash: invalidField7
        )
      }
    }

    for id in [
      "", " leading", "trailing ", "e\u{301}", "line\n",
      String(repeating: "a", count: 257), ".", "..", "a/b", "a?b", "a:b", "a=b",
      "https://example.invalid/token=x",
    ] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try SemanticChunkObject(
          id: id, compressedBytes: 1, uncompressedBytes: 1,
          uncompressedMD5: md5, compressedXXHash: 0)
      }
    }
    for invalidMD5 in ["bad", String(repeating: "g", count: 32)] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try SemanticChunkObject(
          id: "object", compressedBytes: 1, uncompressedBytes: 1,
          uncompressedMD5: invalidMD5, compressedXXHash: 0)
      }
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try SemanticChunkObject(
        id: "object", compressedBytes: 0, uncompressedBytes: 1,
        uncompressedMD5: md5, compressedXXHash: 0)
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try SemanticChunkObject(
        id: "object", compressedBytes: 1, uncompressedBytes: 0,
        uncompressedMD5: md5, compressedXXHash: 0)
    }

    let result = try validate([
      file(
        "file", bytes: 1, references: [reference(uppercase, at: 0)],
        wholeMD5: String(repeating: "B", count: 32))
    ])
    #expect(result.files[0].wholeMD5 == String(repeating: "b", count: 32))
  }

  @Test
  func publicSummaryContainsNoLeafIdentifiersOrPaths() throws {
    let validated = try validate([try coveredFile("Data/file.bin")])
    let values: [Any] = [validated.summary, validated.summary.sizes]
    let labels = values.flatMap { Mirror(reflecting: $0).children.compactMap(\.label) }
      .map { $0.lowercased() }
    for forbidden in ["path", "objectid", "id", "md5", "checksum"] {
      #expect(!labels.contains(where: { $0.contains(forbidden) }))
    }
  }

  private var md5: String { String(repeating: "a", count: 32) }

  private func object(
    id: String,
    compressed: UInt64,
    uncompressed: UInt64,
    xxhash: UInt64? = nil,
    field7: String? = nil
  ) throws -> SemanticChunkObject {
    try SemanticChunkObject(
      id: id, compressedBytes: compressed, uncompressedBytes: uncompressed,
      uncompressedMD5: md5,
      compressedXXHash: xxhash ?? UInt64(id.utf8.count),
      wireField7OpaqueHash: field7
    )
  }

  private func reference(
    _ object: SemanticChunkObject,
    at offset: UInt64
  ) -> SemanticChunkReference {
    SemanticChunkReference(object: object, fileOffset: offset)
  }

  private func file(
    _ path: String,
    bytes: UInt64,
    references: [SemanticChunkReference],
    wholeMD5: String? = nil
  ) -> SemanticChunkFile {
    SemanticChunkFile(
      path: path, kind: .file, installedBytes: bytes,
      wholeMD5: wholeMD5 ?? md5, references: references)
  }

  private func coveredFile(_ path: String) throws -> SemanticChunkFile {
    let object = try object(id: "object-\(path.utf8.count)", compressed: 4, uncompressed: 4)
    return file(path, bytes: 4, references: [reference(object, at: 0)])
  }

  private func validate(_ files: [SemanticChunkFile]) throws -> ValidatedChunkManifest {
    try ChunkManifestValidator.validate(
      category: .game,
      candidate: SemanticChunkManifest(files: files)
    )
  }
}
