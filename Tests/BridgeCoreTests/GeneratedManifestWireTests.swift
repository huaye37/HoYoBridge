import Foundation
import SwiftProtobuf
import Testing

@testable import BridgeCore

struct GeneratedManifestWireTests {
  @Test
  func hardcodedIndependentWireVectorsDecodeAndReencodeExactly() throws {
    let chunkVector = Data([0x0A, 0x03, 0x0A, 0x01, 0x78])
    let chunk = try Manifest(serializedBytes: chunkVector)
    #expect(chunk.files.count == 1)
    #expect(chunk.files[0].filename == "x")
    #expect(try chunk.serializedData() == chunkVector)

    let field7Vector = Data([0x0A, 0x05, 0x12, 0x03, 0x3A, 0x01, 0x63])
    let field7 = try Manifest(serializedBytes: field7Vector)
    #expect(field7.files[0].chunks[0].opaqueHash == "c")
    #expect(try field7.serializedData() == field7Vector)

    let ldiffVector = Data([
      0x0A, 0x0A, 0x22, 0x08, 0x0A, 0x01, 0x73, 0x12,
      0x03, 0x0A, 0x01, 0x70, 0x12, 0x0A, 0x0A, 0x01,
      0x73, 0x12, 0x05, 0x0A, 0x03, 0x0A, 0x01, 0x64,
    ])
    let ldiff = try DiffManifest(serializedBytes: ldiffVector)
    #expect(ldiff.files[0].patches[0].hasInfo)
    #expect(ldiff.files[0].patches[0].info.patchID == "p")
    #expect(ldiff.filesDelete[0].info.list[0].filename == "d")
    #expect(try ldiff.serializedData() == ldiffVector)
  }

  @Test
  func chunkManifestSyntheticBinaryRoundTrip() throws {
    var chunk = ChunkInfo()
    chunk.chunkID = "chunk-a"
    chunk.md5 = String(repeating: "a", count: 32)
    chunk.offset = 4
    chunk.compressedSize = 10
    chunk.uncompressedSize = 20
    chunk.xxhash = 42
    chunk.opaqueHash = String(repeating: "c", count: 32)

    var file = FileInfo()
    file.filename = "Game/Data.bin"
    file.chunks = [chunk]
    file.flags = 0
    file.size = 24
    file.md5 = String(repeating: "b", count: 32)

    var manifest = Manifest()
    manifest.files = [file]
    let data = try manifest.serializedData()
    let decoded = try Manifest(serializedBytes: data)

    #expect(decoded == manifest)
    #expect(decoded.files[0].chunks[0].chunkID == "chunk-a")
    #expect(decoded.files[0].chunks[0].xxhash == 42)
    #expect(decoded.files[0].chunks[0].opaqueHash == String(repeating: "c", count: 32))
  }

  @Test
  func ldiffManifestSyntheticBinaryRoundTrip() throws {
    var info = PatchInfo()
    info.patchID = "patch-a"
    info.tag = "1.0.0"
    info.buildID = "build-a"
    info.patchSize = 100
    info.patchName = "patch-name"
    info.patchOffset = 4
    info.patchLength = 20
    info.originalName = "Game/Data.bin"
    info.originalSize = 24
    info.originalHash = String(repeating: "c", count: 32)

    var patch = Patch()
    patch.key = "1.0.0"
    patch.info = info

    var file = DiffFileInfo()
    file.filename = "Game/Data.bin"
    file.size = 30
    file.hash = String(repeating: "d", count: 32)
    file.patches = [patch]

    var deletedInfo = DeleteFileInfo()
    deletedInfo.filename = "Game/Old.bin"
    deletedInfo.size = 10
    deletedInfo.hash = String(repeating: "e", count: 32)
    var deletedFiles = DeleteFiles()
    deletedFiles.list = [deletedInfo]
    var deletion = DeleteFile()
    deletion.key = "1.0.0"
    deletion.info = deletedFiles

    var manifest = DiffManifest()
    manifest.files = [file]
    manifest.filesDelete = [deletion]
    let data = try manifest.serializedData()
    let decoded = try DiffManifest(serializedBytes: data)

    #expect(decoded == manifest)
    #expect(decoded.files[0].patches[0].hasInfo)
    #expect(decoded.filesDelete[0].info.list[0].filename == "Game/Old.bin")
  }

  @Test
  func preservesUnknownFieldsAndEnforcesMessageDepthLimit() throws {
    var file = FileInfo()
    file.filename = "nested"
    var manifest = Manifest()
    manifest.files = [file]
    var data = try manifest.serializedData()
    let unknownField = Data([0x98, 0x06, 0x01])  // field 99, varint 1
    data.append(unknownField)

    let decoded = try Manifest(serializedBytes: data)
    #expect(decoded.unknownFields.data == unknownField)
    let reencoded = try decoded.serializedData()
    #expect(Data(reencoded.suffix(unknownField.count)) == unknownField)

    let nestedUnknownVector = Data([
      0x0A, 0x06, 0x0A, 0x01, 0x78, 0x98, 0x06, 0x01,
    ])
    let nestedUnknown = try Manifest(serializedBytes: nestedUnknownVector)
    #expect(nestedUnknown.files[0].unknownFields.data == unknownField)
    #expect(try nestedUnknown.serializedData() == nestedUnknownVector)

    var restrictive = BinaryDecodingOptions()
    restrictive.messageDepthLimit = 0
    #expect(throws: (any Error).self) {
      try Manifest(serializedBytes: data, options: restrictive)
    }
    var sufficient = BinaryDecodingOptions()
    sufficient.messageDepthLimit = 2
    _ = try Manifest(serializedBytes: data, options: sufficient)
  }
}
