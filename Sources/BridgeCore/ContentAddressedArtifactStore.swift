import Darwin
import Foundation

public enum ArtifactStoreDisposition: String, Equatable, Sendable {
  case stored
  case reused
  case concurrentCacheHit
}

public struct StoredArtifact: Equatable, Sendable {
  public let url: URL
  public let disposition: ArtifactStoreDisposition

  public init(url: URL, disposition: ArtifactStoreDisposition) {
    self.url = url
    self.disposition = disposition
  }
}

public enum ArtifactStoreError: Error, Equatable, Sendable {
  case unsafeCacheDirectory(String)
  case corruptExistingObject(String)
  case stagingCrossVolume
  case publishFailed(Int32)
}

public struct ContentAddressedArtifactStore: Sendable {
  public let rootURL: URL

  public init(rootURL: URL) {
    self.rootURL = rootURL
  }

  public func store(
    fileAt sourceURL: URL,
    for runtime: RuntimeDefinition
  ) throws -> StoredArtifact {
    try Task.checkCancellation()

    guard runtime.acquisition == .managedDownload else {
      throw ArtifactVerificationError.runtimeIsNotManagedDownload(runtime.id)
    }
    guard let expectedByteSize = runtime.byteSize,
      expectedByteSize > 0,
      let sha256 = runtime.sha256,
      Self.isSHA256(sha256)
    else {
      throw ArtifactVerificationError.incompleteExpectation(runtime.id)
    }

    let normalizedHash = sha256.lowercased()
    let fileManager = FileManager.default
    let stagingDirectory = rootURL.appendingPathComponent(".staging", isDirectory: true)
    let objectsRoot = rootURL.appendingPathComponent("objects", isDirectory: true)
    let objectsDirectory = objectsRoot.appendingPathComponent("sha256", isDirectory: true)
    let objectDirectory = objectsDirectory.appendingPathComponent(
      String(normalizedHash.prefix(2)), isDirectory: true)
    let destinationURL = objectDirectory.appendingPathComponent(normalizedHash)

    try Self.createPrivateDirectory(rootURL)
    try Self.createPrivateDirectory(stagingDirectory)
    try Self.createPrivateDirectory(objectsRoot)
    try Self.createPrivateDirectory(objectsDirectory)
    try Self.createPrivateDirectory(objectDirectory)

    if fileManager.fileExists(atPath: destinationURL.path) {
      try Self.verifyExistingObject(at: destinationURL, for: runtime)
      return StoredArtifact(url: destinationURL, disposition: .reused)
    }

    let stagingURL = stagingDirectory.appendingPathComponent("\(UUID().uuidString).part")
    defer {
      try? fileManager.removeItem(at: stagingURL)
    }

    try Self.copyRegularFile(
      from: sourceURL,
      to: stagingURL,
      expectedByteSize: expectedByteSize
    )
    _ = try ArtifactVerifier.verify(fileAt: stagingURL, for: runtime)
    try Task.checkCancellation()
    try Self.prepareForCommit(stagingURL: stagingURL, destinationDirectory: objectDirectory)
    try Task.checkCancellation()

    let publishResult = stagingURL.path.withCString { sourcePath in
      destinationURL.path.withCString { destinationPath in
        let result = renameatx_np(
          AT_FDCWD,
          sourcePath,
          AT_FDCWD,
          destinationPath,
          UInt32(RENAME_EXCL)
        )
        return (result: result, error: result == 0 ? Int32(0) : errno)
      }
    }
    guard publishResult.result == 0 else {
      let publishError = publishResult.error
      if publishError == EEXIST {
        try Self.verifyExistingObject(at: destinationURL, for: runtime)
        return StoredArtifact(url: destinationURL, disposition: .concurrentCacheHit)
      }
      if publishError == EXDEV {
        throw ArtifactStoreError.stagingCrossVolume
      }
      throw ArtifactStoreError.publishFailed(publishError)
    }

    return StoredArtifact(url: destinationURL, disposition: .stored)
  }

  private static func copyRegularFile(
    from sourceURL: URL,
    to stagingURL: URL,
    expectedByteSize: UInt64
  ) throws {
    try Task.checkCancellation()

    let sourceDescriptor = open(
      sourceURL.path,
      O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
    )
    guard sourceDescriptor >= 0 else {
      if errno == ELOOP {
        throw ArtifactVerificationError.sourceIsNotRegularFile(sourceURL.path)
      }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(sourceDescriptor) }

    var sourceMetadata = stat()
    guard fstat(sourceDescriptor, &sourceMetadata) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard sourceMetadata.st_mode & S_IFMT == S_IFREG else {
      throw ArtifactVerificationError.sourceIsNotRegularFile(sourceURL.path)
    }
    guard sourceMetadata.st_size >= 0 else {
      throw ArtifactVerificationError.sizeMismatch(
        expected: expectedByteSize,
        actual: 0
      )
    }
    let initialByteSize = UInt64(sourceMetadata.st_size)
    guard initialByteSize == expectedByteSize else {
      throw ArtifactVerificationError.sizeMismatch(
        expected: expectedByteSize,
        actual: initialByteSize
      )
    }

    let stagingDescriptor = open(
      stagingURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard stagingDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(stagingDescriptor) }

    var copiedByteSize: UInt64 = 0
    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    while true {
      try Task.checkCancellation()
      let readCount = buffer.withUnsafeMutableBytes { bytes in
        read(sourceDescriptor, bytes.baseAddress, bytes.count)
      }
      if readCount == 0 { break }
      if readCount < 0 {
        if errno == EINTR { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }

      let chunkByteSize = UInt64(readCount)
      guard copiedByteSize <= UInt64.max - chunkByteSize else {
        throw ArtifactVerificationError.sizeMismatch(
          expected: expectedByteSize,
          actual: UInt64.max
        )
      }
      copiedByteSize += chunkByteSize
      guard copiedByteSize <= expectedByteSize else {
        throw ArtifactVerificationError.sizeMismatch(
          expected: expectedByteSize,
          actual: copiedByteSize
        )
      }

      var writtenCount = 0
      while writtenCount < readCount {
        try Task.checkCancellation()
        let writeCount = buffer.withUnsafeBytes { bytes in
          write(
            stagingDescriptor,
            bytes.baseAddress?.advanced(by: writtenCount),
            readCount - writtenCount
          )
        }
        if writeCount < 0 {
          if errno == EINTR { continue }
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard writeCount > 0 else {
          throw POSIXError(.EIO)
        }
        writtenCount += writeCount
      }
    }

    try Task.checkCancellation()
    guard copiedByteSize == expectedByteSize else {
      throw ArtifactVerificationError.sizeMismatch(
        expected: expectedByteSize,
        actual: copiedByteSize
      )
    }
  }

  private static func verifyExistingObject(
    at destinationURL: URL,
    for runtime: RuntimeDefinition
  ) throws {
    do {
      _ = try ArtifactVerifier.verify(fileAt: destinationURL, for: runtime)
    } catch let cancellation as CancellationError {
      throw cancellation
    } catch {
      throw ArtifactStoreError.corruptExistingObject(destinationURL.path)
    }
  }

  private static func prepareForCommit(stagingURL: URL, destinationDirectory: URL) throws {
    let stagingDescriptor = open(
      stagingURL.path,
      O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
    )
    guard stagingDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(stagingDescriptor) }

    let directoryDescriptor = open(destinationDirectory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard directoryDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(directoryDescriptor) }

    var stagingMetadata = stat()
    var directoryMetadata = stat()
    guard fstat(stagingDescriptor, &stagingMetadata) == 0,
      fstat(directoryDescriptor, &directoryMetadata) == 0
    else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard stagingMetadata.st_mode & S_IFMT == S_IFREG else {
      throw ArtifactStoreError.unsafeCacheDirectory(stagingURL.path)
    }
    guard stagingMetadata.st_dev == directoryMetadata.st_dev else {
      throw ArtifactStoreError.stagingCrossVolume
    }
    guard fchmod(stagingDescriptor, S_IRUSR | S_IRGRP | S_IROTH) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try Task.checkCancellation()
    guard fsync(stagingDescriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private static func createPrivateDirectory(_ url: URL) throws {
    let creationResult = url.path.withCString { mkdir($0, S_IRWXU) }
    if creationResult != 0 {
      let creationError = errno
      guard creationError == EEXIST else {
        throw POSIXError(POSIXErrorCode(rawValue: creationError) ?? .EIO)
      }
    }
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFDIR,
      metadata.st_uid == geteuid(),
      metadata.st_mode & 0o777 == 0o700
    else {
      throw ArtifactStoreError.unsafeCacheDirectory(url.path)
    }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
