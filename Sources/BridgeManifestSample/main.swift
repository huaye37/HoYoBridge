import BridgeCore
import Darwin
import Foundation
import ManifestSamplingCore

private struct BridgeCoreManifestBodyInspector: ManifestBodyStructurallyInspecting {
  func inspect(
    _ input: ManifestLiveBodyInspectionInput
  ) throws -> ManifestChunkStructuralEvidence {
    do {
      let evidence = try ManifestLiveChunkInspector.inspect(
        compressedData: input.data,
        compressedSHA256: input.compressedSHA256,
        compressedByteSize: input.byteSize,
        manifestID: input.manifestID,
        profileRevision: input.profileRevision,
        release: input.release,
        category: input.category,
        schemaBaseline: input.schemaBaseline
      )
      return ManifestChunkStructuralEvidence(
        decompressedBodySHA256: evidence.decompressedBodySHA256,
        decompressedByteSize: evidence.decompressedByteSize,
        wirePolicyVersion: evidence.wirePolicyVersion,
        fileCount: evidence.fileCount,
        directoryCount: evidence.directoryCount,
        chunkReferenceCount: evidence.chunkReferenceCount,
        uniqueChunkObjectCount: evidence.uniqueChunkObjectCount,
        targetInstalledBytes: evidence.targetInstalledBytes,
        referencedChunkCompressedBytes: evidence.referencedChunkCompressedBytes,
        uniqueChunkObjectBytes: evidence.uniqueChunkObjectBytes,
        wireNodeCount: evidence.wireNodeCount,
        wireStringBytes: evidence.wireStringBytes,
        payloadCandidate: ManifestChunkPayloadCandidate(
          objectID: evidence.payloadCandidate.objectID,
          compressedBytes: evidence.payloadCandidate.compressedBytes,
          uncompressedBytes: evidence.payloadCandidate.uncompressedBytes,
          uncompressedMD5: evidence.payloadCandidate.uncompressedMD5,
          compressedXXHash: evidence.payloadCandidate.compressedXXHash,
          wireField7OpaqueHash: evidence.payloadCandidate.wireField7OpaqueHash
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestLiveChunkInspectionError {
      switch error {
      case .invalidInput:
        throw ManifestSamplingError.semanticShapeRejected
      case .zstdInvalidFrame:
        throw ManifestSamplingError.manifestZstdFrameRejected
      case .zstdDictionaryRejected:
        throw ManifestSamplingError.manifestZstdDictionaryRejected
      case .zstdWindowRejected:
        throw ManifestSamplingError.manifestZstdWindowRejected
      case .zstdOutputRejected:
        throw ManifestSamplingError.manifestZstdOutputRejected
      case .zstdRatioRejected:
        throw ManifestSamplingError.manifestZstdRatioRejected
      case .zstdTruncated:
        throw ManifestSamplingError.manifestZstdTruncated
      case .zstdTrailingData:
        throw ManifestSamplingError.manifestZstdTrailingData
      case .zstdDecoderRejected:
        throw ManifestSamplingError.manifestZstdDecoderRejected
      case .wireSchemaDrift(let messageKind, let fieldNumber, let wireType):
        throw ManifestSamplingError.manifestWireSchemaDrift(
          messageKind: messageKind,
          fieldNumber: fieldNumber,
          wireType: wireType
        )
      case .wireInvalid:
        throw ManifestSamplingError.manifestWireInvalid
      case .wireResourceLimit:
        throw ManifestSamplingError.manifestWireResourceLimit
      case .structuralRejected:
        throw ManifestSamplingError.manifestStructuralRejected
      }
    } catch {
      throw ManifestSamplingError.semanticShapeRejected
    }
  }
}

private struct BridgeCoreManifestChunkPayloadVerifier: ManifestChunkPayloadVerifying {
  func verifyAndStore(
    _ input: ManifestChunkPayloadVerificationInput
  ) throws -> ManifestChunkPayloadStoredEvidence {
    let candidate = ManifestLiveChunkPayloadCandidate(
      objectID: input.candidate.objectID,
      compressedBytes: input.candidate.compressedBytes,
      uncompressedBytes: input.candidate.uncompressedBytes,
      uncompressedMD5: input.candidate.uncompressedMD5,
      compressedXXHash: input.candidate.compressedXXHash,
      wireField7OpaqueHash: input.candidate.wireField7OpaqueHash
    )
    let verification: ManifestChunkPayloadVerificationEvidence
    do {
      verification = try ManifestChunkPayloadVerifier.verify(input.data, candidate: candidate)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestChunkPayloadVerificationError {
      switch error {
      case .invalidCandidate, .sizeMismatch:
        throw ManifestSamplingError.chunkIntegrityRejected
      case .field7MD5Mismatch:
        throw ManifestSamplingError.chunkField7MD5Rejected
      case .decompressionRejected, .uncompressedSizeMismatch:
        throw ManifestSamplingError.chunkDecompressionRejected
      case .uncompressedMD5Mismatch:
        throw ManifestSamplingError.chunkUncompressedMD5Rejected
      }
    } catch {
      throw ManifestSamplingError.chunkIntegrityRejected
    }

    let localRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("LocalRuntimes", isDirectory: true)
    let cacheRoot = localRoot.appendingPathComponent("ChunkProbeCache", isDirectory: true)
    let sourceURL: URL
    do {
      try Self.requirePrivateDirectory(localRoot)
      sourceURL = try Self.writeTemporaryPayload(input.data)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestSamplingError.chunkCacheRejected
    }
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let runtime = RuntimeDefinition(
      id: "cn-chunk-probe-\(verification.sha256.prefix(16))",
      backend: .custom,
      version: "observed-cn-v2",
      verification: .candidate,
      acquisition: .managedDownload,
      byteSize: verification.byteSize,
      sha256: verification.sha256,
      license: "Vendor game content; local verification only",
      redistributable: false
    )
    let stored: StoredArtifact
    do {
      stored = try ContentAddressedArtifactStore(rootURL: cacheRoot).store(
        fileAt: sourceURL,
        for: runtime
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestSamplingError.chunkCacheRejected
    }
    let relativePath =
      "objects/sha256/\(verification.sha256.prefix(2))/\(verification.sha256)"
    guard
      stored.url.standardizedFileURL
        == cacheRoot.appendingPathComponent(relativePath).standardizedFileURL
    else {
      throw ManifestSamplingError.chunkCacheRejected
    }
    return ManifestChunkPayloadStoredEvidence(
      byteSize: verification.byteSize,
      sha256: verification.sha256,
      compressedMD5: verification.compressedMD5,
      uncompressedByteSize: verification.uncompressedByteSize,
      uncompressedMD5: verification.uncompressedMD5,
      cacheDisposition: stored.disposition.rawValue,
      cacheRelativePath: relativePath
    )
  }

  private static func requirePrivateDirectory(_ url: URL) throws {
    let result = url.path.withCString { mkdir($0, S_IRWXU) }
    if result != 0, errno != EEXIST {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFDIR,
      metadata.st_uid == geteuid(),
      metadata.st_mode & 0o777 == 0o700
    else {
      throw POSIXError(.EPERM)
    }
  }

  private static func writeTemporaryPayload(_ data: Data) throws -> URL {
    var template = Array(
      (FileManager.default.temporaryDirectory.path + "/mgb-chunk-probe.XXXXXX").utf8CString)
    let descriptor = mkstemp(&template)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let path = String(
      decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
      as: UTF8.self
    )
    var shouldRemove = true
    defer {
      _ = close(descriptor)
      if shouldRemove { _ = unlink(path) }
    }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var written = 0
    while written < data.count {
      try Task.checkCancellation()
      let count = data.withUnsafeBytes { bytes in
        write(descriptor, bytes.baseAddress?.advanced(by: written), data.count - written)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard count > 0 else { throw POSIXError(.EIO) }
      written += count
    }
    guard fsync(descriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    shouldRemove = false
    return URL(fileURLWithPath: path)
  }
}

@main
struct BridgeManifestSampleMain {
  static func main() async {
    do {
      let output = try await ManifestSampleCommandRunner.execute(
        arguments: Array(CommandLine.arguments.dropFirst()),
        environment: ProcessInfo.processInfo.environment,
        structuralInspector: BridgeCoreManifestBodyInspector(),
        chunkPayloadVerifier: BridgeCoreManifestChunkPayloadVerifier()
      )
      guard let text = String(data: output, encoding: .utf8) else {
        throw ManifestSamplingError.transportFailure
      }
      print(text)
    } catch is CancellationError {
      fputs("cancelled\n", stderr)
      exit(2)
    } catch let error as ManifestSamplingError {
      fputs(error.safeCode + "\n", stderr)
      exit(1)
    } catch {
      fputs("transport-failure\n", stderr)
      exit(1)
    }
  }
}
