import CryptoKit
import Foundation

package enum ManifestLiveChunkInspectionError: Error, Equatable, Sendable {
  case invalidInput
  case zstdInvalidFrame
  case zstdDictionaryRejected
  case zstdWindowRejected
  case zstdOutputRejected
  case zstdRatioRejected
  case zstdTruncated
  case zstdTrailingData
  case zstdDecoderRejected
  case wireSchemaDrift(messageKind: String, fieldNumber: UInt64, wireType: UInt8)
  case wireInvalid
  case wireResourceLimit
  case structuralRejected
}

package struct ManifestLiveChunkInspectionEvidence: Equatable, Sendable {
  package let decompressedBodySHA256: String
  package let decompressedByteSize: UInt64
  package let wirePolicyVersion: UInt8
  package let fileCount: UInt64
  package let directoryCount: UInt64
  package let chunkReferenceCount: UInt64
  package let uniqueChunkObjectCount: UInt64
  package let targetInstalledBytes: UInt64
  package let referencedChunkCompressedBytes: UInt64
  package let uniqueChunkObjectBytes: UInt64
  package let wireNodeCount: UInt64
  package let wireStringBytes: UInt64
  package let payloadCandidate: ManifestLiveChunkPayloadCandidate
}

package struct ManifestLiveChunkPayloadCandidate: Equatable, Sendable {
  package let objectID: String
  package let compressedBytes: UInt64
  package let uncompressedBytes: UInt64
  package let uncompressedMD5: String
  package let compressedXXHash: UInt64
  package let wireField7OpaqueHash: String

  package init(
    objectID: String,
    compressedBytes: UInt64,
    uncompressedBytes: UInt64,
    uncompressedMD5: String,
    compressedXXHash: UInt64,
    wireField7OpaqueHash: String
  ) {
    self.objectID = objectID
    self.compressedBytes = compressedBytes
    self.uncompressedBytes = uncompressedBytes
    self.uncompressedMD5 = uncompressedMD5
    self.compressedXXHash = compressedXXHash
    self.wireField7OpaqueHash = wireField7OpaqueHash
  }
}

extension ManifestLiveChunkPayloadCandidate: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  package var description: String { "<redacted>" }
  package var debugDescription: String { "<redacted>" }
  package var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

package enum ManifestLiveChunkInspector {
  package static func inspect(
    compressedData: Data,
    compressedSHA256: String,
    compressedByteSize: UInt64,
    manifestID: String,
    profileRevision: UInt64,
    release: String,
    category: String,
    schemaBaseline: String
  ) throws -> ManifestLiveChunkInspectionEvidence {
    try Task.checkCancellation()
    guard release == GameRelease.genshinOfficialCN.rawValue,
      category == ResourceCategory.game.rawValue,
      schemaBaseline == ManifestProtobufStructuralMapper.observedCNChunkSchemaBaseline,
      profileRevision > 0,
      UInt64(exactly: compressedData.count) == compressedByteSize
    else {
      throw ManifestLiveChunkInspectionError.invalidInput
    }
    let owned = compressedData.withUnsafeBytes { Data($0) }
    let actualSHA256 = SHA256.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    guard actualSHA256 == compressedSHA256 else {
      throw ManifestLiveChunkInspectionError.invalidInput
    }

    let reference: ManifestReferenceDigest
    let artifact: ValidatedReplayArtifactData
    do {
      reference = try ManifestReferenceDigest.make(
        release: .genshinOfficialCN,
        category: .game,
        manifestID: ManifestReferenceID(manifestID),
        profileRevision: profileRevision,
        kind: .chunk
      )
      artifact = ValidatedReplayArtifactData(
        kind: .chunkManifest,
        data: owned,
        sha256: try ManifestSHA256(actualSHA256),
        byteSize: compressedByteSize,
        manifestReferenceSHA256: reference
      )
    } catch {
      throw ManifestLiveChunkInspectionError.invalidInput
    }

    let decompressed: ManifestZstdDecompressedCapability
    do {
      decompressed = try ManifestZstdDecompressor.decompress(
        artifact,
        manifestReference: reference,
        limits: .observedCNChunkManifest
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestZstdDecompressionError {
      switch error {
      case .invalidLimits, .invalidArtifact:
        throw ManifestLiveChunkInspectionError.invalidInput
      case .invalidFrame:
        throw ManifestLiveChunkInspectionError.zstdInvalidFrame
      case .dictionaryRequired:
        throw ManifestLiveChunkInspectionError.zstdDictionaryRejected
      case .windowLimitExceeded:
        throw ManifestLiveChunkInspectionError.zstdWindowRejected
      case .outputLimitExceeded:
        throw ManifestLiveChunkInspectionError.zstdOutputRejected
      case .ratioLimitExceeded:
        throw ManifestLiveChunkInspectionError.zstdRatioRejected
      case .truncatedFrame:
        throw ManifestLiveChunkInspectionError.zstdTruncated
      case .trailingData:
        throw ManifestLiveChunkInspectionError.zstdTrailingData
      case .noProgress, .decoderFailure:
        throw ManifestLiveChunkInspectionError.zstdDecoderRejected
      }
    } catch {
      throw ManifestLiveChunkInspectionError.zstdDecoderRejected
    }

    let wireReceipt: ManifestProtobufWireBudgetSummary
    do {
      wireReceipt = try ManifestProtobufWireBudgetScanner.scan(decompressed)
    } catch is CancellationError {
      throw CancellationError()
    } catch ManifestProtobufWireScanningError.schemaDrift {
      let observation: ManifestProtobufWireSchemaDriftObservation?
      do {
        observation = try ManifestProtobufWireBudgetScanner.diagnoseSchemaDrift(decompressed)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        observation = nil
      }
      throw ManifestLiveChunkInspectionError.wireSchemaDrift(
        messageKind: observation?.messageKind ?? "unknown",
        fieldNumber: observation?.fieldNumber ?? 0,
        wireType: observation?.wireType ?? 0
      )
    } catch ManifestProtobufWireScanningError.invalidWire {
      throw ManifestLiveChunkInspectionError.wireInvalid
    } catch ManifestProtobufWireScanningError.resourceLimit {
      throw ManifestLiveChunkInspectionError.wireResourceLimit
    } catch {
      throw ManifestLiveChunkInspectionError.wireInvalid
    }

    do {
      let mapped = try ManifestProtobufStructuralMapper.mapChunk(
        decompressed,
        expectedManifestReference: reference,
        schemaBaseline: try ManifestSchemaBaseline(schemaBaseline)
      )
      let summary = mapped.validated.summary
      guard
        let candidate = mapped.validated.objects.min(by: { left, right in
          if left.compressedBytes != right.compressedBytes {
            return left.compressedBytes < right.compressedBytes
          }
          return ManifestSemanticValidation.utf8Less(left.id, right.id)
        }),
        let wireField7OpaqueHash = candidate.wireField7OpaqueHash
      else {
        throw ManifestAdapterError.invalidManifest
      }
      try Task.checkCancellation()
      return ManifestLiveChunkInspectionEvidence(
        decompressedBodySHA256: wireReceipt.decompressedSHA256.lowercaseHex,
        decompressedByteSize: wireReceipt.decompressedByteSize,
        wirePolicyVersion: wireReceipt.policyVersion,
        fileCount: summary.fileCount,
        directoryCount: summary.directoryCount,
        chunkReferenceCount: summary.chunkReferenceCount,
        uniqueChunkObjectCount: summary.uniqueChunkObjectCount,
        targetInstalledBytes: summary.sizes.targetInstalledBytes,
        referencedChunkCompressedBytes: summary.sizes.referencedChunkCompressedBytes,
        uniqueChunkObjectBytes: summary.sizes.uniqueChunkObjectBytes,
        wireNodeCount: wireReceipt.nodeCount,
        wireStringBytes: wireReceipt.totalStringBytes,
        payloadCandidate: ManifestLiveChunkPayloadCandidate(
          objectID: candidate.id,
          compressedBytes: candidate.compressedBytes,
          uncompressedBytes: candidate.uncompressedBytes,
          uncompressedMD5: candidate.uncompressedMD5,
          compressedXXHash: candidate.compressedXXHash,
          wireField7OpaqueHash: wireField7OpaqueHash
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestLiveChunkInspectionError.structuralRejected
    }
  }
}
