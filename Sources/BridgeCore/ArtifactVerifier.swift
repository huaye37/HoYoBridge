import CryptoKit
import Darwin
import Foundation

public struct VerifiedArtifact: Equatable, Sendable {
  public let sourceURL: URL
  public let runtimeID: String
  public let byteSize: UInt64
  public let sha256: String
}

public enum ArtifactVerificationError: Error, Equatable, Sendable {
  case runtimeIsNotManagedDownload(String)
  case incompleteExpectation(String)
  case sourceIsNotRegularFile(String)
  case sizeMismatch(expected: UInt64, actual: UInt64)
  case hashMismatch(expected: String, actual: String)
}

public enum ArtifactVerifier {
  public static func verify(
    fileAt url: URL,
    for runtime: RuntimeDefinition
  ) throws -> VerifiedArtifact {
    try Task.checkCancellation()

    guard runtime.acquisition == .managedDownload else {
      throw ArtifactVerificationError.runtimeIsNotManagedDownload(runtime.id)
    }
    guard let expectedSize = runtime.byteSize,
      expectedSize > 0,
      let expectedHash = runtime.sha256,
      isSHA256(expectedHash)
    else {
      throw ArtifactVerificationError.incompleteExpectation(runtime.id)
    }

    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard descriptor >= 0 else {
      if errno == ELOOP {
        throw ArtifactVerificationError.sourceIsNotRegularFile(url.path)
      }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard metadata.st_mode & S_IFMT == S_IFREG else {
      throw ArtifactVerificationError.sourceIsNotRegularFile(url.path)
    }

    var hasher = SHA256()
    var actualSize: UInt64 = 0
    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    while true {
      try Task.checkCancellation()
      let readCount = buffer.withUnsafeMutableBytes { bytes in
        read(descriptor, bytes.baseAddress, bytes.count)
      }
      if readCount == 0 { break }
      if readCount < 0 {
        if errno == EINTR { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }

      let chunkSize = UInt64(readCount)
      guard actualSize <= UInt64.max - chunkSize else {
        throw ArtifactVerificationError.sizeMismatch(expected: expectedSize, actual: UInt64.max)
      }
      actualSize += chunkSize
      if actualSize > expectedSize {
        throw ArtifactVerificationError.sizeMismatch(expected: expectedSize, actual: actualSize)
      }
      hasher.update(data: Data(buffer[0..<Int(readCount)]))
    }

    try Task.checkCancellation()
    let actualHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    let normalizedExpectedHash = expectedHash.lowercased()
    guard actualSize == expectedSize else {
      throw ArtifactVerificationError.sizeMismatch(expected: expectedSize, actual: actualSize)
    }
    guard actualHash == normalizedExpectedHash else {
      throw ArtifactVerificationError.hashMismatch(
        expected: normalizedExpectedHash, actual: actualHash)
    }

    return VerifiedArtifact(
      sourceURL: url,
      runtimeID: runtime.id,
      byteSize: actualSize,
      sha256: actualHash
    )
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
