import CZstdBridge
import CZstdTestSupport
import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct ManifestZstdDecompressorTests {
  @Test
  func decodesIndependentHardcodedFrameVector() throws {
    let compressed = try data(
      hex: "28b52ffd045829000068656c6c6fa36d9f88")
    let artifact = try validatedArtifact(
      kind: .chunkManifest,
      compressed: compressed,
      id: "zstd-known-vector"
    )
    let capability = try ManifestZstdDecompressor.decompress(
      artifact,
      manifestReference: try #require(artifact.manifestReferenceSHA256)
    )
    #expect(capability.data == Data("hello".utf8))
  }

  @Test
  func decodesKnownUnknownAndEmptyFramesWithOwnedSHA() throws {
    let payload = deterministicBytes(count: 300_000)
    for (index, flags) in [UInt32(0), UInt32(MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE)].enumerated() {
      let compressed = try compress(payload, flags: flags)
      let artifact = try validatedArtifact(
        kind: .chunkManifest,
        compressed: compressed,
        id: "zstd-roundtrip-\(index)"
      )
      let reference = try #require(artifact.manifestReferenceSHA256)
      let capability = try ManifestZstdDecompressor.decompress(
        artifact,
        manifestReference: reference
      )
      #expect(capability.data == payload)
      #expect(capability.byteSize == UInt64(payload.count))
      #expect(capability.compressedArtifactIdentity == ManifestReplayArtifactIdentity(artifact))
      #expect(capability.sha256.lowercaseHex == sha256(payload))
    }

    let emptyCompressed = try compress(Data())
    let emptyArtifact = try validatedArtifact(
      kind: .diffManifest,
      compressed: emptyCompressed,
      id: "zstd-empty"
    )
    let empty = try ManifestZstdDecompressor.decompress(
      emptyArtifact,
      manifestReference: try #require(emptyArtifact.manifestReferenceSHA256)
    )
    #expect(empty.data.isEmpty)
    #expect(
      empty.sha256.lowercaseHex
        == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  }

  @Test
  func rejectsChecksumCorruptionAndTruncation() throws {
    let payload = Data(repeating: 0x41, count: 200_000)
    var corrupted = try compress(payload, flags: UInt32(MGB_ZSTD_TEST_CHECKSUM))
    corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0x01
    let corruptArtifact = try validatedArtifact(
      kind: .chunkManifest,
      compressed: corrupted,
      id: "zstd-checksum"
    )
    #expect(throws: ManifestZstdDecompressionError.invalidFrame) {
      try ManifestZstdDecompressor.decompress(
        corruptArtifact,
        manifestReference: try #require(corruptArtifact.manifestReferenceSHA256)
      )
    }

    let complete = try compress(payload)
    let truncatedBytes = Data(complete.dropLast())
    let truncated = try validatedArtifact(
      kind: .chunkManifest,
      compressed: truncatedBytes,
      id: "zstd-truncated"
    )
    #expect(throws: ManifestZstdDecompressionError.truncatedFrame) {
      try ManifestZstdDecompressor.decompress(
        truncated,
        manifestReference: try #require(truncated.manifestReferenceSHA256)
      )
    }
  }

  @Test
  func rejectsTrailingConcatenatedSkippableAndWrongMagic() throws {
    let frame = try compress(Data("manifest".utf8))
    var trailingBytes = frame
    trailingBytes.append(0)
    var concatenatedBytes = frame
    concatenatedBytes.append(frame)
    var skippable = Data([0x50, 0x2A, 0x4D, 0x18, 0, 0, 0, 0])
    skippable.append(frame)
    var wrongMagic = frame
    wrongMagic[wrongMagic.startIndex] ^= 0xFF

    let cases: [(String, Data, ManifestZstdDecompressionError)] = [
      ("trailing", trailingBytes, .trailingData),
      ("concatenated", concatenatedBytes, .trailingData),
      ("skippable", skippable, .invalidFrame),
      ("magic", wrongMagic, .invalidFrame),
    ]
    for item in cases {
      let artifact = try validatedArtifact(
        kind: .chunkManifest,
        compressed: item.1,
        id: "zstd-\(item.0)"
      )
      #expect(throws: item.2) {
        try ManifestZstdDecompressor.decompress(
          artifact,
          manifestReference: try #require(artifact.manifestReferenceSHA256)
        )
      }
    }
  }

  @Test
  func rejectsDictionaryAndOversizedWindowFrames() throws {
    let payload = Data(repeating: 0x42, count: 32_000)
    let dictionaryFrame = try compress(
      payload,
      flags: UInt32(MGB_ZSTD_TEST_DICTIONARY)
    )
    let dictionaryArtifact = try validatedArtifact(
      kind: .diffManifest,
      compressed: dictionaryFrame,
      id: "zstd-dictionary"
    )
    #expect(throws: ManifestZstdDecompressionError.dictionaryRequired) {
      try ManifestZstdDecompressor.decompress(
        dictionaryArtifact,
        manifestReference: try #require(dictionaryArtifact.manifestReferenceSHA256)
      )
    }

    let rawDictionaryPayload = Data(
      String(
        repeating: "raw-manifest-dictionary-path-object-checksum-reference-payload-",
        count: 64
      ).utf8)
    let rawDictionaryFrame = try compress(
      rawDictionaryPayload,
      flags: UInt32(MGB_ZSTD_TEST_RAW_DICTIONARY)
    )
    var rawProbe = MGBZstdFrameProbe()
    let rawProbeStatus = rawDictionaryFrame.withUnsafeBytes { bytes in
      mgb_zstd_probe(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        &rawProbe
      )
    }
    #expect(rawProbeStatus == MGB_ZSTD_STATUS_OK)
    #expect(rawProbe.dictionary_id == 0)
    let rawDictionaryArtifact = try validatedArtifact(
      kind: .diffManifest,
      compressed: rawDictionaryFrame,
      id: "zstd-raw-dictionary"
    )
    #expect(throws: ManifestZstdDecompressionError.invalidFrame) {
      try ManifestZstdDecompressor.decompress(
        rawDictionaryArtifact,
        manifestReference: try #require(rawDictionaryArtifact.manifestReferenceSHA256)
      )
    }

    let windowFrame = try compress(
      payload,
      flags: UInt32(MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE),
      windowLog: 24
    )
    var windowSize: UInt64 = 0
    let inspectStatus = windowFrame.withUnsafeBytes { bytes in
      mgb_zstd_test_frame_window_size(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        &windowSize
      )
    }
    #expect(inspectStatus == 0)
    #expect(windowSize > 1 << 23)
    let windowArtifact = try validatedArtifact(
      kind: .chunkManifest,
      compressed: windowFrame,
      id: "zstd-window"
    )
    #expect(throws: ManifestZstdDecompressionError.windowLimitExceeded) {
      try ManifestZstdDecompressor.decompress(
        windowArtifact,
        manifestReference: try #require(windowArtifact.manifestReferenceSHA256)
      )
    }

    let acceptedWindowFrame = try compress(
      payload,
      flags: UInt32(MGB_ZSTD_TEST_UNKNOWN_CONTENT_SIZE),
      windowLog: 23
    )
    windowSize = 0
    let acceptedInspectStatus = acceptedWindowFrame.withUnsafeBytes { bytes in
      mgb_zstd_test_frame_window_size(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        &windowSize
      )
    }
    #expect(acceptedInspectStatus == 0)
    #expect(windowSize == 1 << 23)
    let acceptedWindowArtifact = try validatedArtifact(
      kind: .chunkManifest,
      compressed: acceptedWindowFrame,
      id: "zstd-window-boundary"
    )
    #expect(
      try ManifestZstdDecompressor.decompress(
        acceptedWindowArtifact,
        manifestReference: try #require(acceptedWindowArtifact.manifestReferenceSHA256)
      ).data == payload)
  }

  @Test
  func enforcesOutputAndActualConsumedRatioBoundaries() throws {
    let payload = Data(repeating: 0x43, count: 900_000)
    let compressed = try compress(payload)
    let artifact = try validatedArtifact(
      kind: .chunkManifest,
      compressed: compressed,
      id: "zstd-limits"
    )
    let reference = try #require(artifact.manifestReferenceSHA256)
    let exactOutput = try limits(
      chunk: UInt64(payload.count),
      ratioBase: 1 * 1_024 * 1_024,
      ratioMultiplier: 128
    )
    #expect(
      try ManifestZstdDecompressor.decompress(
        artifact, manifestReference: reference, limits: exactOutput
      ).data == payload)
    let belowOutput = try limits(
      chunk: UInt64(payload.count - 1),
      ratioBase: 1 * 1_024 * 1_024,
      ratioMultiplier: 128
    )
    #expect(throws: ManifestZstdDecompressionError.outputLimitExceeded) {
      try ManifestZstdDecompressor.decompress(
        artifact, manifestReference: reference, limits: belowOutput)
    }

    let exactBase = UInt64(payload.count - compressed.count)
    let exactRatio = try limits(
      chunk: UInt64(payload.count), ratioBase: exactBase, ratioMultiplier: 1)
    #expect(
      try ManifestZstdDecompressor.decompress(
        artifact, manifestReference: reference, limits: exactRatio
      ).data == payload)
    let belowRatio = try limits(
      chunk: UInt64(payload.count), ratioBase: exactBase - 1, ratioMultiplier: 1)
    #expect(throws: ManifestZstdDecompressionError.ratioLimitExceeded) {
      try ManifestZstdDecompressor.decompress(
        artifact, manifestReference: reference, limits: belowRatio)
    }

    var paddedFrame = compressed
    paddedFrame.append(Data(repeating: 0, count: 100_000))
    let paddedArtifact = try validatedArtifact(
      kind: .chunkManifest,
      compressed: paddedFrame,
      id: "zstd-ratio-consumed"
    )
    #expect(throws: ManifestZstdDecompressionError.ratioLimitExceeded) {
      try ManifestZstdDecompressor.decompress(
        paddedArtifact,
        manifestReference: try #require(paddedArtifact.manifestReferenceSHA256),
        limits: belowRatio
      )
    }
  }

  @Test
  func rejectsWrongKindReferenceAndRelaxedOrZeroLimits() throws {
    let compressed = try compress(Data("payload".utf8))
    let fixture = try MaterializerTestFixture.make(.full, id: "zstd-wrong-kind")
    let branch = try #require(
      fixture.bundle.externalArtifacts.first { $0.kind == .branchResponse })
    let chunk = try validatedArtifact(
      kind: .chunkManifest,
      compressed: compressed,
      id: "zstd-wrong-ref"
    )
    let chunkReference = try #require(chunk.manifestReferenceSHA256)
    #expect(throws: ManifestZstdDecompressionError.invalidArtifact) {
      try ManifestZstdDecompressor.decompress(
        branch, manifestReference: chunkReference)
    }
    #expect(throws: ManifestZstdDecompressionError.invalidArtifact) {
      try ManifestZstdDecompressor.decompress(
        chunk,
        manifestReference: try ManifestReferenceDigest.parseLowercaseHex(
          String(repeating: "f", count: 64))
      )
    }

    let defaults = ManifestZstdDecompressionLimits.default
    let invalid: [() throws -> ManifestZstdDecompressionLimits] = [
      { try ManifestZstdDecompressionLimits(maximumWindowLog: 24) },
      {
        try ManifestZstdDecompressionLimits(
          maximumChunkManifestBytes: defaults.maximumChunkManifestBytes + 1)
      },
      { try ManifestZstdDecompressionLimits(maximumChunkManifestBytes: 0) },
      { try ManifestZstdDecompressionLimits(maximumDiffManifestBytes: 0) },
      { try ManifestZstdDecompressionLimits(ratioBaseBytes: 0) },
      { try ManifestZstdDecompressionLimits(ratioMultiplier: 0) },
      { try ManifestZstdDecompressionLimits(ratioMultiplier: 129) },
    ]
    for build in invalid {
      #expect(throws: ManifestZstdDecompressionError.invalidLimits) { try build() }
    }
  }

  @Test
  func snapshotsMutableInputSupportsCancellationConcurrencyAndRedaction() async throws {
    let canary = "zstd-secret-canary"
    let payload = Data(canary.utf8)
    let compressed = try compress(payload)
    let mutable = NSMutableData(data: compressed)
    let shared = Data(referencing: mutable)
    let artifact = try validatedArtifact(
      kind: .diffManifest,
      compressed: shared,
      id: "zstd-owned"
    )
    memset(mutable.mutableBytes, 0, mutable.length)
    let reference = try #require(artifact.manifestReferenceSHA256)
    let capability = try ManifestZstdDecompressor.decompress(
      artifact, manifestReference: reference)
    #expect(capability.data == payload)

    let cancelled = Task { () throws -> ManifestZstdDecompressedCapability in
      withUnsafeCurrentTask { $0?.cancel() }
      return try ManifestZstdDecompressor.decompress(
        artifact, manifestReference: reference)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let values = try await withThrowingTaskGroup(
      of: ManifestZstdDecompressedCapability.self,
      returning: [ManifestZstdDecompressedCapability].self
    ) { group in
      for _ in 0..<16 {
        group.addTask {
          try ManifestZstdDecompressor.decompress(
            artifact, manifestReference: reference)
        }
      }
      var values: [ManifestZstdDecompressedCapability] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(values.count == 16)
    #expect(values.allSatisfy { $0 == capability })
    #expect(!isDecodable(ManifestZstdDecompressedCapability.self))
    var dumped = ""
    dump(capability, to: &dumped)
    #expect(!dumped.contains(canary))
    #expect(!String(describing: capability).contains(canary))
    #expect(!String(reflecting: capability).contains(canary))
    #expect(Mirror(reflecting: capability).children.first?.label == "redacted")
  }

  private func compress(
    _ data: Data,
    flags: UInt32 = 0,
    windowLog: UInt32 = 0
  ) throws -> Data {
    var output = MGBZstdTestBuffer()
    let status = data.withUnsafeBytes { bytes in
      mgb_zstd_test_compress(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        flags,
        windowLog,
        &output
      )
    }
    guard status == 0, let bytes = output.bytes else {
      throw ManifestAdapterError.invalidManifest
    }
    defer { mgb_zstd_test_buffer_destroy(&output) }
    return Data(bytes: bytes, count: output.size)
  }

  private func validatedArtifact(
    kind: ManifestEvidenceArtifactKind,
    compressed: Data,
    id: String
  ) throws -> ValidatedReplayArtifactData {
    let shape: MaterializerTestShape = kind == .chunkManifest ? .full : .update
    let fixture = try MaterializerTestFixture.make(
      shape,
      id: id,
      artifactDataOverrides: [kind: compressed]
    )
    return try #require(
      fixture.bundle.externalArtifacts.first { $0.kind == kind })
  }

  private func limits(
    chunk: UInt64,
    ratioBase: UInt64,
    ratioMultiplier: UInt64
  ) throws -> ManifestZstdDecompressionLimits {
    try ManifestZstdDecompressionLimits(
      maximumChunkManifestBytes: chunk,
      ratioBaseBytes: ratioBase,
      ratioMultiplier: ratioMultiplier
    )
  }

  private func deterministicBytes(count: Int) -> Data {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    return Data(
      (0..<count).map { _ in
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return UInt8(truncatingIfNeeded: state)
      })
  }

  private func data(hex: String) throws -> Data {
    guard hex.utf8.count.isMultiple(of: 2) else {
      throw ManifestAdapterError.invalidManifest
    }
    let bytes = Array(hex.utf8)
    var result = Data()
    result.reserveCapacity(bytes.count / 2)
    for index in stride(from: 0, to: bytes.count, by: 2) {
      guard let high = hexNibble(bytes[index]), let low = hexNibble(bytes[index + 1]) else {
        throw ManifestAdapterError.invalidManifest
      }
      result.append(high << 4 | low)
    }
    return result
  }

  private func hexNibble(_ value: UInt8) -> UInt8? {
    switch value {
    case 48...57: value - 48
    case 97...102: value - 87
    default: nil
    }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func isDecodable<T>(_ type: T.Type) -> Bool {
    type is any Decodable.Type
  }
}
