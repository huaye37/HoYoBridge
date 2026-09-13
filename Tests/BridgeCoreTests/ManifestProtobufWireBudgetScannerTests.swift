import CZstdTestSupport
import Foundation
import SwiftProtobuf
import Testing

@testable import BridgeCore

struct ManifestProtobufWireBudgetScannerTests {
  @Test
  func scansGeneratedChunkAndLdiffCapabilities() throws {
    let chunkCapability = try capability(
      bytes: try generatedChunkData(), kind: .chunkManifest, id: "wire-generated-chunk")
    let chunk = try ManifestProtobufWireBudgetScanner.scan(chunkCapability)
    #expect(chunk.policyVersion == 1)
    #expect(chunk.fileCount == 1)
    #expect(chunk.chunkCount == 1)
    #expect(chunk.patchCount == 0)
    #expect(chunk.nodeCount == 3)
    #expect(chunk.decompressedSHA256 == chunkCapability.sha256)
    #expect(chunk.decompressedByteSize == chunkCapability.byteSize)
    #expect(chunk.compressedArtifactIdentity == chunkCapability.compressedArtifactIdentity)

    let ldiffCapability = try capability(
      bytes: try generatedLdiffData(), kind: .diffManifest, id: "wire-generated-ldiff")
    let ldiff = try ManifestProtobufWireBudgetScanner.scan(ldiffCapability)
    #expect(ldiff.fileCount == 1)
    #expect(ldiff.patchCount == 1)
    #expect(ldiff.deleteGroupCount == 1)
    #expect(ldiff.deleteEntryCount == 1)
    #expect(ldiff.nodeCount == 7)
    #expect(ldiff.totalStringBytes > 0)
    #expect(!isDecodable(ManifestProtobufWireBudgetSummary.self))
    var dumped = ""
    dump(ldiff, to: &dumped)
    #expect(Mirror(reflecting: ldiff).children.first?.label == "redacted")
    #expect(!dumped.contains("game.bin"))
  }

  @Test
  func acceptsBoundedChunkInfoField7ButStillRejectsWrongWireAndDuplicates() throws {
    let valid = try capability(
      bytes: chunkInfoMessage(stringField(7, String(repeating: "c", count: 32))),
      kind: .chunkManifest,
      id: "wire-field7-valid"
    )
    #expect(try ManifestProtobufWireBudgetScanner.scan(valid).chunkCount == 1)

    let wrongWire = try capability(
      bytes: chunkInfoMessage(varintField(7, 1)),
      kind: .chunkManifest,
      id: "wire-field7-wrong-wire"
    )
    #expect(throws: ManifestProtobufWireScanningError.schemaDrift) {
      try ManifestProtobufWireBudgetScanner.scan(wrongWire)
    }

    var duplicate = stringField(7, String(repeating: "c", count: 32))
    duplicate.append(stringField(7, String(repeating: "d", count: 32)))
    let duplicateInput = try capability(
      bytes: chunkInfoMessage(duplicate),
      kind: .chunkManifest,
      id: "wire-field7-duplicate"
    )
    #expect(throws: ManifestProtobufWireScanningError.schemaDrift) {
      try ManifestProtobufWireBudgetScanner.scan(duplicateInput)
    }

    let oversized = try capability(
      bytes: chunkInfoMessage(stringField(7, String(repeating: "e", count: 33))),
      kind: .chunkManifest,
      id: "wire-field7-oversized"
    )
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(oversized)
    }
  }

  @Test
  func rejectsRootAndNestedUnknownWrongWireAndDuplicateSingular() throws {
    var rootUnknown = messageField(1, Data())
    rootUnknown.append(varintField(99, 0))
    let nestedUnknown = messageField(1, varintField(99, 0))
    let wrongWire = varintField(1, 0)
    var duplicateFilename = stringField(1, "a")
    duplicateFilename.append(stringField(1, "b"))
    let duplicateSingular = messageField(1, duplicateFilename)

    for (index, bytes) in [rootUnknown, nestedUnknown, wrongWire, duplicateSingular].enumerated() {
      let input = try capability(
        bytes: bytes, kind: .chunkManifest, id: "wire-schema-\(index)")
      #expect(throws: ManifestProtobufWireScanningError.schemaDrift) {
        try ManifestProtobufWireBudgetScanner.scan(input)
      }
    }
  }

  @Test
  func rejectsUnknownAndDuplicateSingularAtEveryDeepestMessage() throws {
    var duplicateChunkID = stringField(1, "a")
    duplicateChunkID.append(stringField(1, "b"))
    var duplicatePatchID = stringField(1, "a")
    duplicatePatchID.append(stringField(1, "b"))
    var duplicateDeleteFilename = stringField(1, "a")
    duplicateDeleteFilename.append(stringField(1, "b"))

    let cases: [(ManifestEvidenceArtifactKind, Data)] = [
      (.chunkManifest, chunkInfoMessage(varintField(99, 0))),
      (.chunkManifest, chunkInfoMessage(duplicateChunkID)),
      (.diffManifest, patchInfoMessage(varintField(99, 0))),
      (.diffManifest, patchInfoMessage(duplicatePatchID)),
      (.diffManifest, deleteFileInfoMessage(varintField(99, 0))),
      (.diffManifest, deleteFileInfoMessage(duplicateDeleteFilename)),
    ]
    for (index, candidate) in cases.enumerated() {
      let input = try capability(
        bytes: candidate.1,
        kind: candidate.0,
        id: "wire-deep-schema-\(index)"
      )
      #expect(throws: ManifestProtobufWireScanningError.schemaDrift) {
        try ManifestProtobufWireBudgetScanner.scan(input)
      }
    }
  }

  @Test
  func rejectsNonminimalOverflowingAndTruncatedWire() throws {
    let fieldZero = Data([0x00])
    let nonminimalTag = Data([0x8A, 0x00, 0x00])
    let nonminimalLength = Data([0x0A, 0x80, 0x00])
    var overflowingVarint = Data([0x18])
    overflowingVarint.append(contentsOf: Array(repeating: 0x80, count: 10))
    overflowingVarint.append(0x00)
    let elevenByteVarint = messageField(1, overflowingVarint)
    var overflowingTenthPayload = Data([0x18])
    overflowingTenthPayload.append(contentsOf: Array(repeating: 0x80, count: 9))
    overflowingTenthPayload.append(0x02)
    let invalidTenthPayload = messageField(1, overflowingTenthPayload)
    let truncatedLength = Data([0x0A, 0x05, 0x01])
    let unterminatedTag = Data([0x80])

    for (index, bytes) in [
      fieldZero, nonminimalTag, nonminimalLength, elevenByteVarint,
      invalidTenthPayload, truncatedLength, unterminatedTag,
    ].enumerated() {
      let input = try capability(
        bytes: bytes, kind: .chunkManifest, id: "wire-invalid-\(index)")
      #expect(throws: ManifestProtobufWireScanningError.invalidWire) {
        try ManifestProtobufWireBudgetScanner.scan(input)
      }
    }
  }

  @Test
  func rejectsEveryKnownWrongWireAndAcceptsExplicitNumericZero() throws {
    for wire in [UInt64(3), 4, 6, 7] {
      let input = try capability(
        bytes: key(1, wire: wire),
        kind: .chunkManifest,
        id: "wire-known-type-\(wire)"
      )
      #expect(throws: ManifestProtobufWireScanningError.schemaDrift) {
        try ManifestProtobufWireBudgetScanner.scan(input)
      }
    }

    var file = varintField(3, 0)
    file.append(varintField(4, 0))
    let explicitDefaults = try capability(
      bytes: messageField(1, file),
      kind: .chunkManifest,
      id: "wire-explicit-zero"
    )
    #expect(
      try ManifestProtobufWireBudgetScanner.scan(explicitDefaults).fileCount == 1)
  }

  @Test
  func enforcesSchemaAwareIntegerRanges() throws {
    let int32Values = [UInt64(Int32.max), 0xFFFF_FFFF_8000_0000, UInt64.max]
    for (index, value) in int32Values.enumerated() {
      let input = try capability(
        bytes: messageField(1, varintField(3, value)),
        kind: .chunkManifest,
        id: "wire-int32-valid-\(index)"
      )
      #expect(try ManifestProtobufWireBudgetScanner.scan(input).fileCount == 1)
    }

    for (index, value) in [
      UInt64(0x8000_0000), 0xFFFF_FFFF, 0xFFFF_FFFF_7FFF_FFFF,
    ].enumerated() {
      let input = try capability(
        bytes: messageField(1, varintField(3, value)),
        kind: .chunkManifest,
        id: "wire-int32-alias-\(index)"
      )
      #expect(throws: ManifestProtobufWireScanningError.invalidWire) {
        try ManifestProtobufWireBudgetScanner.scan(input)
      }
    }

    let uint32Maximum = try capability(
      bytes: chunkInfoField(4, UInt64(UInt32.max)),
      kind: .chunkManifest,
      id: "wire-uint32-maximum"
    )
    #expect(try ManifestProtobufWireBudgetScanner.scan(uint32Maximum).chunkCount == 1)
    let uint32Overflow = try capability(
      bytes: chunkInfoField(4, UInt64(UInt32.max) + 1),
      kind: .chunkManifest,
      id: "wire-uint32-overflow"
    )
    #expect(throws: ManifestProtobufWireScanningError.invalidWire) {
      try ManifestProtobufWireBudgetScanner.scan(uint32Overflow)
    }

    for (index, bytes) in [
      chunkInfoField(3, UInt64.max),
      patchInfoField(4, UInt64.max),
    ].enumerated() {
      let kind: ManifestEvidenceArtifactKind = index == 0 ? .chunkManifest : .diffManifest
      let input = try capability(bytes: bytes, kind: kind, id: "wire-64bit-\(index)")
      #expect(try ManifestProtobufWireBudgetScanner.scan(input).nodeCount > 0)
    }
  }

  @Test
  func allowsOpaquePatchIdentifiersThrough256Bytes() throws {
    var exactInfo = stringField(1, String(repeating: "i", count: 256))
    exactInfo.append(stringField(5, String(repeating: "n", count: 256)))
    let exact = try capability(
      bytes: patchInfoMessage(exactInfo),
      kind: .diffManifest,
      id: "wire-patch-opaque-exact"
    )
    #expect(try ManifestProtobufWireBudgetScanner.scan(exact).patchCount == 1)

    for (index, field) in [UInt64(1), 5].enumerated() {
      let oversized = try capability(
        bytes: patchInfoMessage(stringField(field, String(repeating: "x", count: 257))),
        kind: .diffManifest,
        id: "wire-patch-opaque-oversized-\(index)"
      )
      #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
        try ManifestProtobufWireBudgetScanner.scan(oversized)
      }
    }
  }

  @Test
  func enforcesDepthAndNodeLimitsAtExactBoundary() throws {
    #expect(ManifestProtobufWireBudgetLimits.default.maximumDepth == 3)
    let input = try capability(
      bytes: try generatedLdiffData(), kind: .diffManifest, id: "wire-depth")
    let exactDepth = try limits(maximumDepth: 3, maximumNodeCount: 7)
    #expect(try ManifestProtobufWireBudgetScanner.scan(input, limits: exactDepth).nodeCount == 7)

    let shallow = try limits(maximumDepth: 2, maximumNodeCount: 7)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(input, limits: shallow)
    }
    let tooFewNodes = try limits(maximumDepth: 3, maximumNodeCount: 6)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(input, limits: tooFewNodes)
    }
  }

  @Test
  func enforcesFileChunkPatchAndDeleteCountsWhileAllowingRepeatedFields() throws {
    var twoFiles = messageField(1, Data())
    twoFiles.append(messageField(1, Data()))
    let filesInput = try capability(
      bytes: twoFiles, kind: .chunkManifest, id: "wire-files")
    #expect(
      try ManifestProtobufWireBudgetScanner.scan(
        filesInput,
        limits: try limits(maximumFileCount: 2)
      ).fileCount == 2)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        filesInput, limits: try limits(maximumFileCount: 1))
    }

    var twoChunks = messageField(2, Data())
    twoChunks.append(messageField(2, Data()))
    let chunksInput = try capability(
      bytes: messageField(1, twoChunks), kind: .chunkManifest, id: "wire-chunks")
    let chunksExact = try limits(maximumTotalChunkCount: 2, maximumChunksPerFile: 2)
    #expect(
      try ManifestProtobufWireBudgetScanner.scan(chunksInput, limits: chunksExact).chunkCount == 2)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        chunksInput,
        limits: try limits(maximumTotalChunkCount: 2, maximumChunksPerFile: 1))
    }
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        chunksInput,
        limits: try limits(maximumTotalChunkCount: 1, maximumChunksPerFile: 2))
    }

    var patches = messageField(4, Data())
    patches.append(messageField(4, Data()))
    let patchInput = try capability(
      bytes: messageField(1, patches), kind: .diffManifest, id: "wire-patches")
    #expect(
      try ManifestProtobufWireBudgetScanner.scan(
        patchInput,
        limits: try limits(maximumTotalPatchCount: 2, maximumPatchesPerFile: 2)
      ).patchCount == 2)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        patchInput,
        limits: try limits(maximumTotalPatchCount: 1, maximumPatchesPerFile: 2))
    }
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        patchInput,
        limits: try limits(maximumTotalPatchCount: 2, maximumPatchesPerFile: 1))
    }

    var deleteGroups = messageField(2, messageField(2, messageField(1, Data())))
    deleteGroups.append(messageField(2, messageField(2, messageField(1, Data()))))
    let deletesInput = try capability(
      bytes: deleteGroups, kind: .diffManifest, id: "wire-deletes")
    let deleteExact = try limits(maximumDeleteGroupCount: 2, maximumDeleteEntryCount: 2)
    let deletes = try ManifestProtobufWireBudgetScanner.scan(deletesInput, limits: deleteExact)
    #expect(deletes.deleteGroupCount == 2)
    #expect(deletes.deleteEntryCount == 2)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        deletesInput,
        limits: try limits(maximumDeleteGroupCount: 1, maximumDeleteEntryCount: 2))
    }
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        deletesInput,
        limits: try limits(maximumDeleteGroupCount: 2, maximumDeleteEntryCount: 1))
    }
  }

  @Test
  func enforcesPerFieldAndTotalStringBudgetsAtExactBoundary() throws {
    let input = try capability(
      bytes: messageField(1, stringField(1, "abc")),
      kind: .chunkManifest,
      id: "wire-strings"
    )
    let exact = try limits(maximumStringFieldBytes: 3, maximumTotalStringBytes: 3)
    #expect(try ManifestProtobufWireBudgetScanner.scan(input, limits: exact).totalStringBytes == 3)
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        input,
        limits: try limits(maximumStringFieldBytes: 2, maximumTotalStringBytes: 3))
    }
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(
        input,
        limits: try limits(maximumStringFieldBytes: 3, maximumTotalStringBytes: 2))
    }
    let oversizedPath = try capability(
      bytes: messageField(1, stringField(1, String(repeating: "a", count: 1_025))),
      kind: .chunkManifest,
      id: "wire-string-field"
    )
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetScanner.scan(oversizedPath)
    }
  }

  @Test
  func rejectsRelaxedLimitsAndHonorsCancellationAndConcurrency() async throws {
    let defaults = ManifestProtobufWireBudgetLimits.default
    #expect(throws: ManifestProtobufWireScanningError.resourceLimit) {
      try ManifestProtobufWireBudgetLimits(
        maximumTotalPatchCount: defaults.maximumTotalPatchCount + 1)
    }
    let input = try capability(
      bytes: try generatedChunkData(), kind: .chunkManifest, id: "wire-concurrent")
    let cancelled = Task { () throws -> ManifestProtobufWireBudgetSummary in
      withUnsafeCurrentTask { $0?.cancel() }
      return try ManifestProtobufWireBudgetScanner.scan(input)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let expected = try ManifestProtobufWireBudgetScanner.scan(input)
    let values = try await withThrowingTaskGroup(
      of: ManifestProtobufWireBudgetSummary.self,
      returning: [ManifestProtobufWireBudgetSummary].self
    ) { group in
      for _ in 0..<16 {
        group.addTask { try ManifestProtobufWireBudgetScanner.scan(input) }
      }
      var values: [ManifestProtobufWireBudgetSummary] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(values.allSatisfy { $0 == expected })
  }

  private func generatedChunkData() throws -> Data {
    var chunk = ChunkInfo()
    chunk.chunkID = "object"
    chunk.md5 = String(repeating: "a", count: 32)
    chunk.offset = 0
    chunk.compressedSize = 3
    chunk.uncompressedSize = 4
    chunk.xxhash = 1
    var file = FileInfo()
    file.filename = "game.bin"
    file.chunks = [chunk]
    file.flags = 0
    file.size = 4
    file.md5 = String(repeating: "b", count: 32)
    var manifest = Manifest()
    manifest.files = [file]
    return try manifest.serializedData()
  }

  private func generatedLdiffData() throws -> Data {
    var info = PatchInfo()
    info.patchID = String(repeating: "a", count: 16) + "_" + String(repeating: "b", count: 32)
    info.tag = "1.0.0"
    info.buildID = "build"
    info.patchSize = 5
    info.patchName = String(repeating: "a", count: 16)
    info.patchOffset = 0
    info.patchLength = 5
    info.originalName = "game.bin"
    info.originalSize = 4
    info.originalHash = String(repeating: "c", count: 32)
    var patch = Patch()
    patch.key = "1.0.0"
    patch.info = info
    var file = DiffFileInfo()
    file.filename = "game.bin"
    file.size = 4
    file.hash = String(repeating: "d", count: 32)
    file.patches = [patch]
    var deletionInfo = DeleteFileInfo()
    deletionInfo.filename = "old.bin"
    deletionInfo.size = 1
    deletionInfo.hash = String(repeating: "e", count: 32)
    var deletionList = DeleteFiles()
    deletionList.list = [deletionInfo]
    var deletion = DeleteFile()
    deletion.key = "1.0.0"
    deletion.info = deletionList
    var manifest = DiffManifest()
    manifest.files = [file]
    manifest.filesDelete = [deletion]
    return try manifest.serializedData()
  }

  private func capability(
    bytes: Data,
    kind: ManifestEvidenceArtifactKind,
    id: String
  ) throws -> ManifestZstdDecompressedCapability {
    let compressed = try compress(bytes)
    let shape: MaterializerTestShape = kind == .chunkManifest ? .full : .update
    let fixture = try MaterializerTestFixture.make(
      shape,
      id: id,
      artifactDataOverrides: [kind: compressed]
    )
    let artifact = try #require(
      fixture.bundle.externalArtifacts.first { $0.kind == kind })
    return try ManifestZstdDecompressor.decompress(
      artifact,
      manifestReference: try #require(artifact.manifestReferenceSHA256)
    )
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

  private func limits(
    maximumFileCount: UInt64 = 100_000,
    maximumTotalChunkCount: UInt64 = 1_000_000,
    maximumChunksPerFile: UInt64 = 100_000,
    maximumTotalPatchCount: UInt64 = 500_000,
    maximumPatchesPerFile: UInt64 = 256,
    maximumDeleteGroupCount: UInt64 = 256,
    maximumDeleteEntryCount: UInt64 = 100_000,
    maximumDepth: UInt8 = 3,
    maximumNodeCount: UInt64 = 1_250_000,
    maximumStringFieldBytes: UInt64 = 1_024,
    maximumTotalStringBytes: UInt64 = 128 * 1_024 * 1_024
  ) throws -> ManifestProtobufWireBudgetLimits {
    try ManifestProtobufWireBudgetLimits(
      maximumFileCount: maximumFileCount,
      maximumTotalChunkCount: maximumTotalChunkCount,
      maximumChunksPerFile: maximumChunksPerFile,
      maximumTotalPatchCount: maximumTotalPatchCount,
      maximumPatchesPerFile: maximumPatchesPerFile,
      maximumDeleteGroupCount: maximumDeleteGroupCount,
      maximumDeleteEntryCount: maximumDeleteEntryCount,
      maximumDepth: maximumDepth,
      maximumNodeCount: maximumNodeCount,
      maximumStringFieldBytes: maximumStringFieldBytes,
      maximumTotalStringBytes: maximumTotalStringBytes
    )
  }

  private func messageField(_ field: UInt64, _ value: Data) -> Data {
    var data = key(field, wire: 2)
    data.append(varint(UInt64(value.count)))
    data.append(value)
    return data
  }

  private func stringField(_ field: UInt64, _ value: String) -> Data {
    messageField(field, Data(value.utf8))
  }

  private func varintField(_ field: UInt64, _ value: UInt64) -> Data {
    var data = key(field, wire: 0)
    data.append(varint(value))
    return data
  }

  private func chunkInfoField(_ field: UInt64, _ value: UInt64) -> Data {
    chunkInfoMessage(varintField(field, value))
  }

  private func chunkInfoMessage(_ info: Data) -> Data {
    messageField(1, messageField(2, info))
  }

  private func patchInfoField(_ field: UInt64, _ value: UInt64) -> Data {
    patchInfoMessage(varintField(field, value))
  }

  private func patchInfoMessage(_ info: Data) -> Data {
    messageField(1, messageField(4, messageField(2, info)))
  }

  private func deleteFileInfoMessage(_ info: Data) -> Data {
    messageField(2, messageField(2, messageField(1, info)))
  }

  private func key(_ field: UInt64, wire: UInt64) -> Data {
    varint(field << 3 | wire)
  }

  private func varint(_ value: UInt64) -> Data {
    var value = value
    var data = Data()
    repeat {
      var byte = UInt8(value & 0x7F)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      data.append(byte)
    } while value != 0
    return data
  }

  private func isDecodable<T>(_ type: T.Type) -> Bool {
    type is any Decodable.Type
  }
}
