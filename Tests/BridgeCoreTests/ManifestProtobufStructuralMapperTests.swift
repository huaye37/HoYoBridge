import CZstdTestSupport
import Foundation
import SwiftProtobuf
import Testing

@testable import BridgeCore

struct ManifestProtobufStructuralMapperTests {
  @Test
  func mapsChunkXXHashBoundsAndExactReceipt() throws {
    var manifest = chunkManifest(xxhashes: [0, .max])
    var directory = FileInfo()
    directory.filename = "Data/"
    directory.flags = 64
    manifest.files.append(directory)
    let artifact = try chunkArtifact(manifest, id: "mapper-chunk-bounds")
    let mapped = try mapChunk(artifact)

    #expect(mapped.receipt.fileCount == 3)
    #expect(mapped.receipt.chunkCount == 2)
    #expect(mapped.receipt.nodeCount == 6)
    #expect(
      mapped.candidate.files.filter { $0.kind == .file }
        .map { $0.references[0].object.compressedXXHash } == [0, .max])
    #expect(mapped.validated.objects.map(\.compressedXXHash) == [0, .max])
    #expect(mapped.validated.files.first(where: { $0.kind == .directory })?.path == "Data")
    #expect(
      mapped.receipt.compressedArtifactIdentity == artifact.capability.compressedArtifactIdentity)
    #expect(mapped.receipt.decompressedSHA256 == artifact.capability.sha256)
    #expect(mapped.receipt.decompressedByteSize == artifact.capability.byteSize)
  }

  @Test
  func bindsObservedCNField7WithoutInventingHashSemantics() throws {
    var observed = chunkManifest(xxhashes: [42])
    observed.files[0].chunks[0].opaqueHash = String(repeating: "c", count: 32)
    let observedArtifact = try chunkArtifact(observed, id: "mapper-cn-field7")
    let mapped = try mapChunk(
      observedArtifact,
      schemaBaseline: ManifestProtobufStructuralMapper.observedCNChunkSchemaBaseline
    )
    #expect(
      mapped.candidate.files[0].references[0].object.wireField7OpaqueHash
        == String(repeating: "c", count: 32))
    #expect(mapped.validated.objects[0].wireField7OpaqueHash == String(repeating: "c", count: 32))

    #expect(throws: ManifestAdapterError.schemaDrift) {
      try mapChunk(observedArtifact)
    }
    let legacy = try chunkArtifact(chunkManifest(xxhashes: [42]), id: "mapper-v1-no-field7")
    #expect(throws: ManifestAdapterError.schemaDrift) {
      try mapChunk(
        legacy,
        schemaBaseline: ManifestProtobufStructuralMapper.observedCNChunkSchemaBaseline
      )
    }
  }

  @Test
  func selectsExactAAndBSourcesAndDeletionGroups() throws {
    let manifest = try ldiffManifest()
    let artifact = try ldiffArtifact(manifest, id: "mapper-ldiff-selection")
    let sourceA = try GameVersion("1.0.0")
    let sourceB = try GameVersion("1.1.0")
    let target = try GameVersion("2.0.0")

    let mappedA = try mapLdiff(artifact, source: sourceA, target: target)
    #expect(mappedA.receipt.fileCount == 3)
    #expect(mappedA.receipt.patchCount == 3)
    #expect(mappedA.receipt.deleteGroupCount == 2)
    #expect(mappedA.receipt.deleteEntryCount == 3)
    #expect(mappedA.receipt.nodeCount == 17)
    #expect(mappedA.candidate.selectedFiles.map(\.path) == ["selected.bin"])
    #expect(
      mappedA.candidate.unselectedFiles.map(\.reason)
        == [.noPatchRecords, .noPatchForRequestedSource])
    #expect(mappedA.candidate.deletions.count == 2)
    #expect(mappedA.candidate.deletions[0].originalMD5 == nil)
    #expect(mappedA.candidate.selectedFiles[0].patch.object.remoteName == "remote-a")
    #expect(mappedA.candidate.selectedFiles[0].patch.originalName == "origin-a.bin")
    #expect(mappedA.validated.selectedFiles[0].patch.originalName == "origin-a.bin")

    let mappedB = try mapLdiff(artifact, source: sourceB, target: target)
    #expect(mappedB.candidate.selectedFiles.map(\.path) == ["selected.bin", "source-b.bin"])
    #expect(mappedB.candidate.unselectedFiles.map(\.reason) == [.noPatchRecords])
    #expect(mappedB.candidate.deletions.map(\.path) == ["old-c.bin"])
  }

  @Test
  func acceptsEmptyLdiffWithoutInventingUnavailability() throws {
    let artifact = try ldiffArtifact(DiffManifest(), id: "mapper-ldiff-empty")
    let mapped = try mapLdiff(
      artifact,
      source: try GameVersion("1.0.0"),
      target: try GameVersion("2.0.0")
    )
    #expect(mapped.receipt.nodeCount == 1)
    #expect(mapped.candidate.manifestFileRecordCount == 0)
    #expect(mapped.validated.selection.categories[.game]?.manifestFileRecordCount == 0)
  }

  @Test
  func rejectsMalformedNonselectedPatchRecords() throws {
    let base = try ldiffManifest()
    var variants: [DiffManifest] = []

    var missingInfo = base
    missingInfo.files[0].patches[1].clearInfo()
    variants.append(missingInfo)

    var duplicateSource = base
    duplicateSource.files[0].patches.append(duplicateSource.files[0].patches[1])
    variants.append(duplicateSource)

    variants.append(mutatingPatchInfo(base, file: 0, patch: 1) { $0.tag = "wrong" })
    variants.append(mutatingPatchInfo(base, file: 0, patch: 1) { $0.patchSize = -1 })
    variants.append(
      mutatingPatchInfo(base, file: 0, patch: 1) {
        $0.patchOffset = 4
        $0.patchLength = 2
      })
    variants.append(mutatingPatchInfo(base, file: 0, patch: 1) { $0.patchID = "a/b" })
    variants.append(mutatingPatchInfo(base, file: 0, patch: 1) { $0.patchName = "token=x" })
    variants.append(mutatingPatchInfo(base, file: 0, patch: 1) { $0.originalName = "../x" })
    variants.append(mutatingPatchInfo(base, file: 0, patch: 1) { $0.originalHash = "bad" })
    variants.append(
      mutatingPatchInfo(base, file: 2, patch: 0) {
        $0.patchID = "object-b"
        $0.patchName = "other-remote"
      })
    var badUnselectedTarget = base
    badUnselectedTarget.files[1].hash = "bad"
    variants.append(badUnselectedTarget)

    for (index, manifest) in variants.enumerated() {
      let artifact = try ldiffArtifact(manifest, id: "mapper-bad-patch-\(index)")
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try mapLdiff(
          artifact,
          source: GameVersion("1.0.0"),
          target: GameVersion("2.0.0")
        )
      }
    }
  }

  @Test
  func rejectsMalformedAndCollidingNonselectedDeletionGroups() throws {
    let base = try ldiffManifest()
    var variants: [DiffManifest] = []

    var missingInfo = base
    missingInfo.filesDelete[1].clearInfo()
    variants.append(missingInfo)

    var duplicateSource = base
    duplicateSource.filesDelete.append(duplicateSource.filesDelete[1])
    variants.append(duplicateSource)

    variants.append(mutatingDeleteEntry(base, group: 1, entry: 0) { $0.filename = "../x" })
    variants.append(mutatingDeleteEntry(base, group: 1, entry: 0) { $0.size = -1 })
    variants.append(mutatingDeleteEntry(base, group: 1, entry: 0) { $0.hash = "bad" })

    var casefold = base
    var casefoldList = casefold.filesDelete[1].info
    casefoldList.list[0].filename = "Same.bin"
    var duplicate = casefoldList.list[0]
    duplicate.filename = "same.bin"
    casefoldList.list.append(duplicate)
    casefold.filesDelete[1].info = casefoldList
    variants.append(casefold)

    var ancestor = base
    var ancestorList = ancestor.filesDelete[1].info
    ancestorList.list[0].filename = "dir"
    var descendant = ancestorList.list[0]
    descendant.filename = "dir/file.bin"
    ancestorList.list.append(descendant)
    ancestor.filesDelete[1].info = ancestorList
    variants.append(ancestor)

    for (index, manifest) in variants.enumerated() {
      let artifact = try ldiffArtifact(manifest, id: "mapper-bad-delete-\(index)")
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try mapLdiff(
          artifact,
          source: GameVersion("1.0.0"),
          target: GameVersion("2.0.0")
        )
      }
    }
  }

  @Test
  func rejectsUnknownInvalidWireWrongKindReferenceAndBaseline() throws {
    var unknown = try chunkManifest(xxhashes: [0]).serializedData()
    unknown.append(contentsOf: [0x98, 0x06, 0x01])
    let unknownArtifact = try decompressed(
      bytes: unknown, kind: .chunkManifest, shape: .full, id: "mapper-unknown")
    #expect(throws: ManifestAdapterError.schemaDrift) {
      try mapChunk(unknownArtifact)
    }

    let invalidWire = try decompressed(
      bytes: Data([0x0A, 0x05, 0x01]),
      kind: .chunkManifest,
      shape: .full,
      id: "mapper-invalid-wire"
    )
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try mapChunk(invalidWire)
    }

    var unsupportedFlags = chunkManifest(xxhashes: [0])
    unsupportedFlags.files[0].flags = 1
    let unsupportedFlagsArtifact = try chunkArtifact(
      unsupportedFlags,
      id: "mapper-unsupported-flags"
    )
    #expect(throws: ManifestAdapterError.schemaDrift) {
      try mapChunk(unsupportedFlagsArtifact)
    }

    let valid = try chunkArtifact(xxhashes: [0], id: "mapper-envelope")
    let wrongReference = try reference(id: "wrong-reference", kind: .chunk)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestProtobufStructuralMapper.mapChunk(
        valid.capability,
        expectedManifestReference: wrongReference,
        schemaBaseline: baseline()
      )
    }
    #expect(throws: ManifestAdapterError.schemaDrift) {
      try ManifestProtobufStructuralMapper.mapChunk(
        valid.capability,
        expectedManifestReference: valid.reference,
        schemaBaseline: ManifestSchemaBaseline("other-baseline")
      )
    }
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestProtobufStructuralMapper.mapLdiff(
        valid.capability,
        expectedManifestReference: valid.reference,
        schemaBaseline: baseline(),
        sourceVersion: GameVersion("1.0.0"),
        targetVersion: GameVersion("2.0.0")
      )
    }
  }

  @Test
  func rejectsSameTargetAndTargetTaggedSourceRecords() throws {
    let artifact = try ldiffArtifact(try ldiffManifest(), id: "mapper-target-source")
    let target = try GameVersion("2.0.0")
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try mapLdiff(artifact, source: target, target: target)
    }

    var manifest = try ldiffManifest()
    var targetPatch = manifest.files[0].patches[1]
    targetPatch.key = target.value
    var info = targetPatch.info
    info.tag = target.value
    targetPatch.info = info
    manifest.files[0].patches[1] = targetPatch
    let targetTagged = try ldiffArtifact(manifest, id: "mapper-target-tagged")
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try mapLdiff(
        targetTagged,
        source: GameVersion("1.0.0"),
        target: target
      )
    }
  }

  @Test
  func capabilitiesAreRedactedNondecodableCancelableAndConcurrent() async throws {
    let artifact = try chunkArtifact(xxhashes: [0, .max], id: "mapper-redacted")
    let mapped = try mapChunk(artifact)
    var dumped = ""
    dump(mapped, to: &dumped)
    #expect(Mirror(reflecting: mapped).children.first?.label == "redacted")
    #expect(!dumped.contains("file-0.bin"))
    #expect(!dumped.contains("chunk-0"))
    #expect(!isDecodable(ManifestProtobufStructuralChunkCapability.self))
    #expect(!isDecodable(ManifestProtobufStructuralLdiffCapability.self))

    let cancelled = Task { () throws -> ManifestProtobufStructuralChunkCapability in
      withUnsafeCurrentTask { $0?.cancel() }
      return try mapChunk(artifact)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let values = try await withThrowingTaskGroup(
      of: ManifestProtobufStructuralChunkCapability.self,
      returning: [ManifestProtobufStructuralChunkCapability].self
    ) { group in
      for _ in 0..<16 { group.addTask { try mapChunk(artifact) } }
      var values: [ManifestProtobufStructuralChunkCapability] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(values.allSatisfy { $0 == mapped })
  }

  private typealias DecompressedArtifact = (
    capability: ManifestZstdDecompressedCapability,
    reference: ManifestReferenceDigest
  )

  private func mapChunk(
    _ artifact: DecompressedArtifact,
    schemaBaseline: String = ManifestProtobufStructuralMapper.requiredSchemaBaseline
  ) throws -> ManifestProtobufStructuralChunkCapability {
    try ManifestProtobufStructuralMapper.mapChunk(
      artifact.capability,
      expectedManifestReference: artifact.reference,
      schemaBaseline: baseline(schemaBaseline)
    )
  }

  private func mapLdiff(
    _ artifact: DecompressedArtifact,
    source: GameVersion,
    target: GameVersion
  ) throws -> ManifestProtobufStructuralLdiffCapability {
    try ManifestProtobufStructuralMapper.mapLdiff(
      artifact.capability,
      expectedManifestReference: artifact.reference,
      schemaBaseline: baseline(),
      sourceVersion: source,
      targetVersion: target
    )
  }

  private func chunkArtifact(
    xxhashes: [UInt64],
    id: String
  ) throws -> DecompressedArtifact {
    try chunkArtifact(chunkManifest(xxhashes: xxhashes), id: id)
  }

  private func chunkArtifact(
    _ manifest: Manifest,
    id: String
  ) throws -> DecompressedArtifact {
    try decompressed(
      bytes: manifest.serializedData(),
      kind: .chunkManifest,
      shape: .full,
      id: id
    )
  }

  private func ldiffArtifact(
    _ manifest: DiffManifest,
    id: String
  ) throws -> DecompressedArtifact {
    try decompressed(
      bytes: manifest.serializedData(),
      kind: .diffManifest,
      shape: .update,
      id: id
    )
  }

  private func decompressed(
    bytes: Data,
    kind: ManifestEvidenceArtifactKind,
    shape: MaterializerTestShape,
    id: String
  ) throws -> DecompressedArtifact {
    let compressed = try compress(bytes)
    let fixture = try MaterializerTestFixture.make(
      shape,
      id: id,
      artifactDataOverrides: [kind: compressed]
    )
    let artifact = try #require(
      fixture.bundle.externalArtifacts.first { $0.kind == kind })
    let reference = try #require(artifact.manifestReferenceSHA256)
    let capability = try ManifestZstdDecompressor.decompress(
      artifact,
      manifestReference: reference
    )
    return (capability, reference)
  }

  private func chunkManifest(xxhashes: [UInt64]) -> Manifest {
    var manifest = Manifest()
    manifest.files = xxhashes.enumerated().map { index, xxhash in
      var chunk = ChunkInfo()
      chunk.chunkID = "chunk-\(index)"
      chunk.md5 = md5("a")
      chunk.offset = 0
      chunk.compressedSize = 1
      chunk.uncompressedSize = 1
      chunk.xxhash = xxhash
      var file = FileInfo()
      file.filename = "file-\(index).bin"
      file.chunks = [chunk]
      file.flags = 0
      file.size = 1
      file.md5 = md5("b")
      return file
    }
    return manifest
  }

  private func ldiffManifest() throws -> DiffManifest {
    let sourceA = "1.0.0"
    let sourceB = "1.1.0"
    var selected = DiffFileInfo()
    selected.filename = "selected.bin"
    selected.size = 4
    selected.hash = md5("d")
    selected.patches = [
      patch(source: sourceA, suffix: "a", originalName: "origin-a.bin"),
      patch(source: sourceB, suffix: "b", originalName: "origin-b.bin"),
    ]

    var noRecords = DiffFileInfo()
    noRecords.filename = "no-records.bin"
    noRecords.size = 4
    noRecords.hash = md5("d")

    var sourceBOnly = DiffFileInfo()
    sourceBOnly.filename = "source-b.bin"
    sourceBOnly.size = 4
    sourceBOnly.hash = md5("d")
    sourceBOnly.patches = [
      patch(source: sourceB, suffix: "c", originalName: "origin-c.bin")
    ]

    var manifest = DiffManifest()
    manifest.files = [selected, noRecords, sourceBOnly]
    manifest.filesDelete = [
      deletionGroup(
        source: sourceA,
        entries: [
          deletion("old-a.bin", bytes: 1, hash: ""),
          deletion("old-b.bin", bytes: 2, hash: md5("e")),
        ]),
      deletionGroup(
        source: sourceB,
        entries: [deletion("old-c.bin", bytes: 3, hash: md5("f"))]),
    ]
    return manifest
  }

  private func patch(source: String, suffix: String, originalName: String) -> Patch {
    var info = PatchInfo()
    info.patchID = "object-\(suffix)"
    info.tag = source
    info.buildID = "build-\(suffix)"
    info.patchSize = 5
    info.patchName = "remote-\(suffix)"
    info.patchOffset = 0
    info.patchLength = 5
    info.originalName = originalName
    info.originalSize = 4
    info.originalHash = md5("c")
    var patch = Patch()
    patch.key = source
    patch.info = info
    return patch
  }

  private func deletionGroup(source: String, entries: [DeleteFileInfo]) -> DeleteFile {
    var info = DeleteFiles()
    info.list = entries
    var group = DeleteFile()
    group.key = source
    group.info = info
    return group
  }

  private func deletion(_ path: String, bytes: Int64, hash: String) -> DeleteFileInfo {
    var entry = DeleteFileInfo()
    entry.filename = path
    entry.size = bytes
    entry.hash = hash
    return entry
  }

  private func mutatingPatchInfo(
    _ manifest: DiffManifest,
    file: Int,
    patch: Int,
    _ mutation: (inout PatchInfo) -> Void
  ) -> DiffManifest {
    var result = manifest
    var record = result.files[file].patches[patch]
    var info = record.info
    mutation(&info)
    record.info = info
    result.files[file].patches[patch] = record
    return result
  }

  private func mutatingDeleteEntry(
    _ manifest: DiffManifest,
    group: Int,
    entry: Int,
    _ mutation: (inout DeleteFileInfo) -> Void
  ) -> DiffManifest {
    var result = manifest
    var info = result.filesDelete[group].info
    mutation(&info.list[entry])
    result.filesDelete[group].info = info
    return result
  }

  private func compress(_ data: Data) throws -> Data {
    var output = MGBZstdTestBuffer()
    let status = data.withUnsafeBytes { bytes in
      mgb_zstd_test_compress(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        0,
        0,
        &output
      )
    }
    guard status == 0, let bytes = output.bytes else {
      throw ManifestAdapterError.invalidManifest
    }
    defer { mgb_zstd_test_buffer_destroy(&output) }
    return Data(bytes: bytes, count: output.size)
  }

  private func reference(
    id: String,
    kind: ManifestReferenceKind
  ) throws -> ManifestReferenceDigest {
    try ManifestReferenceDigest.make(
      release: .genshinOfficialCN,
      category: .game,
      manifestID: ManifestReferenceID(id),
      profileRevision: 1,
      kind: kind
    )
  }

  private func baseline(
    _ value: String = ManifestProtobufStructuralMapper.requiredSchemaBaseline
  ) throws -> ManifestSchemaBaseline {
    try ManifestSchemaBaseline(value)
  }

  private func md5(_ character: Character) -> String {
    String(repeating: character, count: 32)
  }

  private func isDecodable<T>(_ type: T.Type) -> Bool {
    type is any Decodable.Type
  }
}
