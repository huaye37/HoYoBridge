import CZstdTestSupport
import CryptoKit
import Foundation
import SwiftProtobuf
import Testing

@testable import BridgeCore

struct ManifestLiveChunkInspectorTests {
  @Test
  func inspectsCompressedChunkManifestThroughExistingGates() throws {
    let compressed = try compress(try validManifest().serializedData())
    let evidence = try inspect(compressed)
    #expect(evidence.wirePolicyVersion == 1)
    #expect(evidence.fileCount == 1)
    #expect(evidence.directoryCount == 0)
    #expect(evidence.chunkReferenceCount == 1)
    #expect(evidence.uniqueChunkObjectCount == 1)
    #expect(evidence.targetInstalledBytes == 4)
    #expect(evidence.referencedChunkCompressedBytes == 5)
    #expect(evidence.uniqueChunkObjectBytes == 5)
    #expect(evidence.wireNodeCount == 3)
    #expect(evidence.decompressedByteSize > 0)
    #expect(evidence.payloadCandidate.objectID == "object")
    #expect(evidence.payloadCandidate.compressedBytes == 5)
    #expect(evidence.payloadCandidate.wireField7OpaqueHash == String(repeating: "c", count: 32))
  }

  @Test
  func rejectsIdentityDecompressionWireAndStructuralMismatches() throws {
    let valid = try compress(try validManifest().serializedData())
    #expect(throws: ManifestLiveChunkInspectionError.invalidInput) {
      try ManifestLiveChunkInspector.inspect(
        compressedData: valid,
        compressedSHA256: String(repeating: "0", count: 64),
        compressedByteSize: UInt64(valid.count),
        manifestID: "live-inspector",
        profileRevision: 2,
        release: "genshinOfficialCN",
        category: "game",
        schemaBaseline: "mgb-observed-cn-sophon-protobuf-structural-v2"
      )
    }
    #expect(throws: ManifestLiveChunkInspectionError.zstdInvalidFrame) {
      try inspect(Data("not-zstd".utf8))
    }
    #expect(throws: ManifestLiveChunkInspectionError.wireInvalid) {
      try inspect(try compress(Data([0xFF])))
    }
    #expect(
      throws: ManifestLiveChunkInspectionError.wireSchemaDrift(
        messageKind: "chunkManifest",
        fieldNumber: 2,
        wireType: 0
      )
    ) {
      try inspect(try compress(Data([0x10, 0x01])))
    }
    #expect(
      throws: ManifestLiveChunkInspectionError.wireSchemaDrift(
        messageKind: "chunkFile",
        fieldNumber: 6,
        wireType: 0
      )
    ) {
      try inspect(try compress(Data([0x0A, 0x02, 0x30, 0x01])))
    }
    #expect(throws: ManifestLiveChunkInspectionError.structuralRejected) {
      try inspect(
        try compress(Data([0x0A, 0x08, 0x12, 0x06, 0x3A, 0x04, 0x61, 0x62, 0x63, 0x64]))
      )
    }
    #expect(throws: ManifestLiveChunkInspectionError.structuralRejected) {
      try inspect(try compress(try Manifest().serializedData()))
    }
    let payload = Data(repeating: 0x42, count: 32_000)
    #expect(throws: ManifestLiveChunkInspectionError.zstdDictionaryRejected) {
      try inspect(
        try compress(payload, flags: UInt32(MGB_ZSTD_TEST_DICTIONARY))
      )
    }
    let acceptedWindow = try compress(
      try validManifest().serializedData(),
      flags: UInt32(MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE),
      windowLog: 24
    )
    #expect(try inspect(acceptedWindow).fileCount == 1)
    #expect(throws: ManifestLiveChunkInspectionError.zstdWindowRejected) {
      try inspect(
        try compress(
          payload,
          flags: UInt32(MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE),
          windowLog: 25
        )
      )
    }
  }

  private func inspect(_ compressed: Data) throws -> ManifestLiveChunkInspectionEvidence {
    try ManifestLiveChunkInspector.inspect(
      compressedData: compressed,
      compressedSHA256: sha256(compressed),
      compressedByteSize: UInt64(compressed.count),
      manifestID: "live-inspector",
      profileRevision: 2,
      release: "genshinOfficialCN",
      category: "game",
      schemaBaseline: "mgb-observed-cn-sophon-protobuf-structural-v2"
    )
  }

  private func validManifest() -> Manifest {
    var chunk = ChunkInfo()
    chunk.chunkID = "object"
    chunk.offset = 0
    chunk.compressedSize = 5
    chunk.uncompressedSize = 4
    chunk.md5 = String(repeating: "a", count: 32)
    chunk.xxhash = 0
    chunk.opaqueHash = String(repeating: "c", count: 32)

    var file = FileInfo()
    file.filename = "asset.bin"
    file.flags = 0
    file.size = 4
    file.md5 = String(repeating: "b", count: 32)
    file.chunks = [chunk]

    var manifest = Manifest()
    manifest.files = [file]
    return manifest
  }

  private func compress(
    _ input: Data,
    flags: UInt32 = 0,
    windowLog: UInt32 = 0
  ) throws -> Data {
    var buffer = MGBZstdTestBuffer(bytes: nil, size: 0)
    let status = input.withUnsafeBytes { bytes in
      mgb_zstd_test_compress(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        flags,
        windowLog,
        &buffer
      )
    }
    guard status == 0 else { throw ManifestLiveChunkInspectionError.zstdDecoderRejected }
    defer { mgb_zstd_test_buffer_destroy(&buffer) }
    return Data(bytes: buffer.bytes, count: buffer.size)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
