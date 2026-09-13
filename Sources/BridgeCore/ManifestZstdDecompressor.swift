import CZstdBridge
import CryptoKit
import Foundation

struct ManifestZstdDecompressionLimits: Equatable, Sendable {
  static let `default` = ManifestZstdDecompressionLimits(
    uncheckedMaximumWindowLog: 23,
    maximumChunkManifestBytes: 256 * 1_024 * 1_024,
    maximumDiffManifestBytes: 256 * 1_024 * 1_024,
    ratioBaseBytes: 1 * 1_024 * 1_024,
    ratioMultiplier: 128
  )
  static let observedCNChunkManifest = ManifestZstdDecompressionLimits(
    uncheckedMaximumWindowLog: 24,
    maximumChunkManifestBytes: 256 * 1_024 * 1_024,
    maximumDiffManifestBytes: 256 * 1_024 * 1_024,
    ratioBaseBytes: 1 * 1_024 * 1_024,
    ratioMultiplier: 128
  )

  let maximumWindowLog: UInt32
  let maximumChunkManifestBytes: UInt64
  let maximumDiffManifestBytes: UInt64
  let ratioBaseBytes: UInt64
  let ratioMultiplier: UInt64

  init(
    maximumWindowLog: UInt32 = Self.default.maximumWindowLog,
    maximumChunkManifestBytes: UInt64 = Self.default.maximumChunkManifestBytes,
    maximumDiffManifestBytes: UInt64 = Self.default.maximumDiffManifestBytes,
    ratioBaseBytes: UInt64 = Self.default.ratioBaseBytes,
    ratioMultiplier: UInt64 = Self.default.ratioMultiplier
  ) throws {
    let defaults = Self.default
    guard (10...defaults.maximumWindowLog).contains(maximumWindowLog),
      maximumChunkManifestBytes > 0,
      maximumChunkManifestBytes <= defaults.maximumChunkManifestBytes,
      maximumDiffManifestBytes > 0,
      maximumDiffManifestBytes <= defaults.maximumDiffManifestBytes,
      ratioBaseBytes > 0,
      ratioBaseBytes <= defaults.ratioBaseBytes,
      ratioMultiplier > 0,
      ratioMultiplier <= defaults.ratioMultiplier
    else {
      throw ManifestZstdDecompressionError.invalidLimits
    }
    self.maximumWindowLog = maximumWindowLog
    self.maximumChunkManifestBytes = maximumChunkManifestBytes
    self.maximumDiffManifestBytes = maximumDiffManifestBytes
    self.ratioBaseBytes = ratioBaseBytes
    self.ratioMultiplier = ratioMultiplier
  }

  private init(
    uncheckedMaximumWindowLog: UInt32,
    maximumChunkManifestBytes: UInt64,
    maximumDiffManifestBytes: UInt64,
    ratioBaseBytes: UInt64,
    ratioMultiplier: UInt64
  ) {
    maximumWindowLog = uncheckedMaximumWindowLog
    self.maximumChunkManifestBytes = maximumChunkManifestBytes
    self.maximumDiffManifestBytes = maximumDiffManifestBytes
    self.ratioBaseBytes = ratioBaseBytes
    self.ratioMultiplier = ratioMultiplier
  }

  fileprivate func maximumOutputBytes(
    for kind: ManifestEvidenceArtifactKind
  ) -> UInt64? {
    switch kind {
    case .chunkManifest: maximumChunkManifestBytes
    case .diffManifest: maximumDiffManifestBytes
    default: nil
    }
  }
}

enum ManifestZstdDecompressionError: Error, Equatable, Sendable {
  case invalidLimits
  case invalidArtifact
  case invalidFrame
  case dictionaryRequired
  case windowLimitExceeded
  case outputLimitExceeded
  case ratioLimitExceeded
  case truncatedFrame
  case trailingData
  case noProgress
  case decoderFailure
}

struct ManifestZstdDecompressedCapability: Equatable, Sendable {
  let compressedArtifactIdentity: ManifestReplayArtifactIdentity
  let data: Data
  let sha256: ManifestSHA256
  let byteSize: UInt64

  fileprivate init(
    compressedArtifactIdentity: ManifestReplayArtifactIdentity,
    data: Data,
    sha256: ManifestSHA256,
    byteSize: UInt64
  ) {
    self.compressedArtifactIdentity = compressedArtifactIdentity
    self.data = data
    self.sha256 = sha256
    self.byteSize = byteSize
  }
}

extension ManifestZstdDecompressedCapability: ManifestReplayRedactedValue {}

enum ManifestZstdDecompressor {
  private static let inputChunkBytes = 64 * 1_024
  private static let outputChunkBytes = 128 * 1_024

  static func decompress(
    _ artifact: ValidatedReplayArtifactData,
    manifestReference: ManifestReferenceDigest,
    limits: ManifestZstdDecompressionLimits = .default
  ) throws -> ManifestZstdDecompressedCapability {
    try Task.checkCancellation()
    guard let maximumOutputBytes = limits.maximumOutputBytes(for: artifact.kind),
      artifact.manifestReferenceSHA256 == manifestReference,
      !artifact.data.isEmpty,
      UInt64(exactly: artifact.data.count) == artifact.byteSize
    else {
      throw ManifestZstdDecompressionError.invalidArtifact
    }

    var probe = MGBZstdFrameProbe()
    let probeStatus = artifact.data.withUnsafeBytes { bytes in
      mgb_zstd_probe(
        bytes.bindMemory(to: UInt8.self).baseAddress,
        bytes.count,
        &probe
      )
    }
    guard probeStatus == MGB_ZSTD_STATUS_OK else {
      throw ManifestZstdDecompressionError.invalidFrame
    }
    guard probe.dictionary_id == 0 else {
      throw ManifestZstdDecompressionError.dictionaryRequired
    }
    if probe.content_size_known != 0, probe.content_size > maximumOutputBytes {
      throw ManifestZstdDecompressionError.outputLimitExceeded
    }

    var decoderPointer: OpaquePointer?
    let createStatus = mgb_zstd_decoder_create(limits.maximumWindowLog, &decoderPointer)
    guard createStatus == MGB_ZSTD_STATUS_OK, let decoder = decoderPointer else {
      if createStatus == MGB_ZSTD_STATUS_WINDOW_LIMIT {
        throw ManifestZstdDecompressionError.windowLimitExceeded
      }
      throw ManifestZstdDecompressionError.decoderFailure
    }
    var decoderIsActive = true
    defer {
      if decoderIsActive { _ = mgb_zstd_decoder_destroy(decoder) }
    }

    var output = Data()
    if probe.content_size_known != 0, probe.content_size <= UInt64(Int.max) {
      let reserveBytes = min(
        probe.content_size,
        maximumOutputBytes,
        limits.ratioBaseBytes
      )
      output.reserveCapacity(Int(reserveBytes))
    }
    var outputBuffer = [UInt8](repeating: 0, count: outputChunkBytes)
    var outputHasher = SHA256()
    var totalConsumed = 0
    var finished = false

    try artifact.data.withUnsafeBytes { rawInput in
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
        guard consumed <= offered, produced <= outputBuffer.count else {
          throw ManifestZstdDecompressionError.decoderFailure
        }
        let (nextConsumed, consumedOverflow) = totalConsumed.addingReportingOverflow(consumed)
        guard !consumedOverflow, nextConsumed <= input.count else {
          throw ManifestZstdDecompressionError.decoderFailure
        }
        let prospectiveOutput = try checkedOutputSize(output.count, adding: produced)
        guard prospectiveOutput <= maximumOutputBytes else {
          throw ManifestZstdDecompressionError.outputLimitExceeded
        }
        let ratioLimit = try ratioLimit(consumedBytes: nextConsumed, limits: limits)
        guard prospectiveOutput <= ratioLimit else {
          throw ManifestZstdDecompressionError.ratioLimitExceeded
        }
        if produced > 0 {
          let chunk = Data(bytes: outputBuffer, count: produced)
          outputHasher.update(data: chunk)
          output.append(chunk)
        }
        totalConsumed = nextConsumed
        switch status {
        case MGB_ZSTD_STATUS_PROGRESS:
          break
        case MGB_ZSTD_STATUS_FRAME_FINISHED:
          guard totalConsumed == input.count else {
            throw ManifestZstdDecompressionError.trailingData
          }
          finished = true
        case MGB_ZSTD_STATUS_WINDOW_LIMIT:
          throw ManifestZstdDecompressionError.windowLimitExceeded
        case MGB_ZSTD_STATUS_DICTIONARY_REQUIRED:
          throw ManifestZstdDecompressionError.dictionaryRequired
        case MGB_ZSTD_STATUS_INVALID_FRAME:
          throw ManifestZstdDecompressionError.invalidFrame
        case MGB_ZSTD_STATUS_NO_PROGRESS:
          if totalConsumed == input.count {
            throw ManifestZstdDecompressionError.truncatedFrame
          }
          throw ManifestZstdDecompressionError.noProgress
        default:
          throw ManifestZstdDecompressionError.decoderFailure
        }
      }
    }
    try Task.checkCancellation()
    guard probe.content_size_known == 0 || probe.content_size == UInt64(output.count) else {
      throw ManifestZstdDecompressionError.invalidFrame
    }
    let destroyStatus = mgb_zstd_decoder_destroy(decoder)
    decoderIsActive = false
    guard destroyStatus == MGB_ZSTD_STATUS_OK else {
      throw ManifestZstdDecompressionError.decoderFailure
    }
    let digest = outputHasher.finalize().map { String(format: "%02x", $0) }.joined()
    return try ManifestZstdDecompressedCapability(
      compressedArtifactIdentity: ManifestReplayArtifactIdentity(artifact),
      data: output,
      sha256: ManifestSHA256(digest),
      byteSize: UInt64(output.count)
    )
  }

  private static func checkedOutputSize(_ current: Int, adding: Int) throws -> UInt64 {
    let (result, overflow) = current.addingReportingOverflow(adding)
    guard !overflow, let converted = UInt64(exactly: result) else {
      throw ManifestZstdDecompressionError.outputLimitExceeded
    }
    return converted
  }

  private static func ratioLimit(
    consumedBytes: Int,
    limits: ManifestZstdDecompressionLimits
  ) throws -> UInt64 {
    guard let consumed = UInt64(exactly: consumedBytes) else {
      throw ManifestZstdDecompressionError.ratioLimitExceeded
    }
    let (scaled, multiplyOverflow) = consumed.multipliedReportingOverflow(
      by: limits.ratioMultiplier)
    let (result, addOverflow) = limits.ratioBaseBytes.addingReportingOverflow(scaled)
    guard !multiplyOverflow, !addOverflow else {
      throw ManifestZstdDecompressionError.ratioLimitExceeded
    }
    return result
  }
}
