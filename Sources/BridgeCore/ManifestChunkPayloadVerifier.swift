import CZstdBridge
import CryptoKit
import Foundation

package enum ManifestChunkPayloadVerificationError: Error, Equatable, Sendable {
  case invalidCandidate
  case sizeMismatch
  case field7MD5Mismatch
  case decompressionRejected
  case uncompressedSizeMismatch
  case uncompressedMD5Mismatch
}

package struct ManifestChunkPayloadVerificationEvidence: Equatable, Sendable {
  package let byteSize: UInt64
  package let sha256: String
  package let compressedMD5: String
  package let uncompressedByteSize: UInt64
  package let uncompressedMD5: String
}

extension ManifestChunkPayloadVerificationEvidence: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  package var description: String { "<redacted>" }
  package var debugDescription: String { "<redacted>" }
  package var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

package enum ManifestChunkPayloadVerifier {
  private static let maximumUncompressedBytes: UInt64 = 64 * 1_024 * 1_024
  private static let inputChunkBytes = 64 * 1_024
  private static let outputChunkBytes = 128 * 1_024

  package static func verify(
    _ data: Data,
    candidate: ManifestLiveChunkPayloadCandidate
  ) throws -> ManifestChunkPayloadVerificationEvidence {
    try Task.checkCancellation()
    guard candidate.compressedBytes > 0, candidate.uncompressedBytes > 0,
      candidate.uncompressedBytes <= maximumUncompressedBytes,
      candidate.wireField7OpaqueHash.utf8.count == 32,
      candidate.wireField7OpaqueHash.utf8.allSatisfy({
        (48...57).contains($0) || (97...102).contains($0)
      })
    else {
      throw ManifestChunkPayloadVerificationError.invalidCandidate
    }
    let owned = data.withUnsafeBytes { Data($0) }
    guard UInt64(exactly: owned.count) == candidate.compressedBytes else {
      throw ManifestChunkPayloadVerificationError.sizeMismatch
    }
    try Task.checkCancellation()
    let actualMD5 = Insecure.MD5.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    guard actualMD5 == candidate.wireField7OpaqueHash else {
      throw ManifestChunkPayloadVerificationError.field7MD5Mismatch
    }
    let uncompressed = try decompress(
      owned,
      expectedByteSize: candidate.uncompressedBytes
    )
    guard UInt64(exactly: uncompressed.count) == candidate.uncompressedBytes else {
      throw ManifestChunkPayloadVerificationError.uncompressedSizeMismatch
    }
    let actualUncompressedMD5 = Insecure.MD5.hash(data: uncompressed)
      .map { String(format: "%02x", $0) }
      .joined()
    guard actualUncompressedMD5 == candidate.uncompressedMD5 else {
      throw ManifestChunkPayloadVerificationError.uncompressedMD5Mismatch
    }
    let actualSHA256 = SHA256.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    try Task.checkCancellation()
    return ManifestChunkPayloadVerificationEvidence(
      byteSize: candidate.compressedBytes,
      sha256: actualSHA256,
      compressedMD5: actualMD5,
      uncompressedByteSize: candidate.uncompressedBytes,
      uncompressedMD5: actualUncompressedMD5
    )
  }

  private static func decompress(
    _ data: Data,
    expectedByteSize: UInt64
  ) throws -> Data {
    var probe = MGBZstdFrameProbe()
    let probeStatus = data.withUnsafeBytes { bytes in
      mgb_zstd_probe(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        &probe
      )
    }
    guard probeStatus == MGB_ZSTD_STATUS_OK, probe.dictionary_id == 0,
      probe.content_size_known == 0 || probe.content_size == expectedByteSize
    else {
      throw ManifestChunkPayloadVerificationError.decompressionRejected
    }

    var decoderPointer: OpaquePointer?
    guard mgb_zstd_decoder_create(24, &decoderPointer) == MGB_ZSTD_STATUS_OK,
      let decoder = decoderPointer
    else {
      throw ManifestChunkPayloadVerificationError.decompressionRejected
    }
    var decoderIsActive = true
    defer {
      if decoderIsActive { _ = mgb_zstd_decoder_destroy(decoder) }
    }

    var output = Data()
    output.reserveCapacity(Int(min(expectedByteSize, 1 * 1_024 * 1_024)))
    var outputBuffer = [UInt8](repeating: 0, count: outputChunkBytes)
    var totalConsumed = 0
    var finished = false
    try data.withUnsafeBytes { rawInput in
      let input = rawInput.bindMemory(to: UInt8.self)
      while !finished {
        try Task.checkCancellation()
        let remaining = input.count - totalConsumed
        let offered = min(inputChunkBytes, remaining)
        let inputPointer = offered == 0 ? nil : input.baseAddress?.advanced(by: totalConsumed)
        var consumed = 0
        var produced = 0
        let status = outputBuffer.withUnsafeMutableBufferPointer { writable in
          mgb_zstd_decoder_step(
            decoder,
            inputPointer,
            offered,
            &consumed,
            writable.baseAddress,
            writable.count,
            &produced
          )
        }
        guard consumed <= offered, produced <= outputBuffer.count,
          totalConsumed <= input.count - consumed,
          UInt64(output.count) <= expectedByteSize,
          UInt64(produced) <= expectedByteSize - UInt64(output.count)
        else {
          throw ManifestChunkPayloadVerificationError.decompressionRejected
        }
        if produced > 0 {
          output.append(Data(bytes: outputBuffer, count: produced))
        }
        totalConsumed += consumed
        switch status {
        case MGB_ZSTD_STATUS_PROGRESS:
          break
        case MGB_ZSTD_STATUS_FRAME_FINISHED:
          guard totalConsumed == input.count else {
            throw ManifestChunkPayloadVerificationError.decompressionRejected
          }
          finished = true
        default:
          throw ManifestChunkPayloadVerificationError.decompressionRejected
        }
      }
    }
    guard UInt64(exactly: output.count) == expectedByteSize,
      mgb_zstd_decoder_destroy(decoder) == MGB_ZSTD_STATUS_OK
    else {
      throw ManifestChunkPayloadVerificationError.uncompressedSizeMismatch
    }
    decoderIsActive = false
    return output
  }
}
