import CZstdTestSupport
import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct ManifestChunkPayloadVerifierTests {
  @Test
  func verifiesCompressedAndUncompressedIntegrity() throws {
    let raw = Data("hello".utf8)
    let compressed = try compress(raw)
    let candidate = makeCandidate(compressed: compressed, raw: raw)
    let evidence = try ManifestChunkPayloadVerifier.verify(compressed, candidate: candidate)

    #expect(evidence.byteSize == UInt64(compressed.count))
    #expect(evidence.compressedMD5 == md5(compressed))
    #expect(evidence.uncompressedByteSize == 5)
    #expect(evidence.uncompressedMD5 == "5d41402abc4b2a76b9719d911017c592")
    #expect(evidence.sha256 == sha256(compressed))
  }

  @Test
  func rejectsSizeCompressedMD5AndUncompressedMD5Mismatches() throws {
    let raw = Data("hello".utf8)
    let compressed = try compress(raw)
    let base = makeCandidate(compressed: compressed, raw: raw)
    #expect(throws: ManifestChunkPayloadVerificationError.sizeMismatch) {
      try ManifestChunkPayloadVerifier.verify(
        compressed,
        candidate: ManifestLiveChunkPayloadCandidate(
          objectID: base.objectID,
          compressedBytes: base.compressedBytes + 1,
          uncompressedBytes: base.uncompressedBytes,
          uncompressedMD5: base.uncompressedMD5,
          compressedXXHash: base.compressedXXHash,
          wireField7OpaqueHash: base.wireField7OpaqueHash
        )
      )
    }
    #expect(throws: ManifestChunkPayloadVerificationError.field7MD5Mismatch) {
      try ManifestChunkPayloadVerifier.verify(
        compressed,
        candidate: ManifestLiveChunkPayloadCandidate(
          objectID: base.objectID,
          compressedBytes: base.compressedBytes,
          uncompressedBytes: base.uncompressedBytes,
          uncompressedMD5: base.uncompressedMD5,
          compressedXXHash: base.compressedXXHash,
          wireField7OpaqueHash: String(repeating: "0", count: 32)
        )
      )
    }
    #expect(throws: ManifestChunkPayloadVerificationError.uncompressedMD5Mismatch) {
      try ManifestChunkPayloadVerifier.verify(
        compressed,
        candidate: ManifestLiveChunkPayloadCandidate(
          objectID: base.objectID,
          compressedBytes: base.compressedBytes,
          uncompressedBytes: base.uncompressedBytes,
          uncompressedMD5: String(repeating: "0", count: 32),
          compressedXXHash: base.compressedXXHash,
          wireField7OpaqueHash: base.wireField7OpaqueHash
        )
      )
    }
  }

  private func makeCandidate(
    compressed: Data,
    raw: Data
  ) -> ManifestLiveChunkPayloadCandidate {
    ManifestLiveChunkPayloadCandidate(
      objectID: "object",
      compressedBytes: UInt64(compressed.count),
      uncompressedBytes: UInt64(raw.count),
      uncompressedMD5: md5(raw),
      compressedXXHash: 123,
      wireField7OpaqueHash: md5(compressed)
    )
  }

  private func compress(_ input: Data) throws -> Data {
    var buffer = MGBZstdTestBuffer(bytes: nil, size: 0)
    let status = input.withUnsafeBytes { bytes in
      mgb_zstd_test_compress(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        0,
        0,
        &buffer
      )
    }
    guard status == 0 else {
      throw ManifestChunkPayloadVerificationError.decompressionRejected
    }
    defer { mgb_zstd_test_buffer_destroy(&buffer) }
    return Data(bytes: buffer.bytes, count: buffer.size)
  }

  private func md5(_ data: Data) -> String {
    Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
