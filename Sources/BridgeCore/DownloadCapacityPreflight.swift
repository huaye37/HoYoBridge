import Darwin
import Foundation

public enum DownloadCapacityScope: String, Equatable, Sendable {
  case download
  case artifactStore
  case sharedVolume
}

public enum DownloadCapacityPreflightError: Error, Equatable, Sendable {
  case directoryUnavailable(scope: DownloadCapacityScope, code: Int32)
  case invalidPartialByteCount(expected: UInt64, actual: UInt64)
  case arithmeticOverflow(scope: DownloadCapacityScope)
  case insufficientCapacity(
    scope: DownloadCapacityScope,
    required: UInt64,
    available: UInt64
  )
}

struct DownloadFileSystemCapacity: Equatable, Sendable {
  let deviceID: Int32
  let availableBlocks: UInt64
  let blockSize: UInt64
}

struct DownloadCapacityProvider: Sendable {
  private let readCapacity: @Sendable (URL) throws -> DownloadFileSystemCapacity

  init(
    readCapacity: @escaping @Sendable (URL) throws -> DownloadFileSystemCapacity
  ) {
    self.readCapacity = readCapacity
  }

  func capacity(at directoryURL: URL) throws -> DownloadFileSystemCapacity {
    try readCapacity(directoryURL)
  }

  static let system = DownloadCapacityProvider { directoryURL in
    let descriptor = open(
      directoryURL.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { _ = close(descriptor) }

    var directoryMetadata = stat()
    guard fstat(descriptor, &directoryMetadata) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard directoryMetadata.st_mode & S_IFMT == S_IFDIR else {
      throw POSIXError(.ENOTDIR)
    }

    var fileSystemMetadata = statfs()
    guard fstatfs(descriptor, &fileSystemMetadata) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return DownloadFileSystemCapacity(
      deviceID: directoryMetadata.st_dev,
      availableBlocks: fileSystemMetadata.f_bavail,
      blockSize: UInt64(fileSystemMetadata.f_bsize)
    )
  }
}

struct DownloadCapacityPreflight: Sendable {
  let safetyMarginBytes: UInt64
  let capacityProvider: DownloadCapacityProvider

  func check(
    downloadRootURL: URL,
    artifactStoreRootURL: URL,
    expectedByteCount: UInt64,
    partialByteCount: UInt64
  ) throws {
    guard partialByteCount <= expectedByteCount else {
      throw DownloadCapacityPreflightError.invalidPartialByteCount(
        expected: expectedByteCount,
        actual: partialByteCount
      )
    }

    let remainingDownloadBytes = expectedByteCount - partialByteCount
    let downloadCapacity = try capacity(
      at: downloadRootURL,
      scope: .download
    )
    let artifactStoreCapacity = try capacity(
      at: artifactStoreRootURL,
      scope: .artifactStore
    )

    if downloadCapacity.deviceID == artifactStoreCapacity.deviceID {
      let transferAndStagingBytes = try adding(
        remainingDownloadBytes,
        expectedByteCount,
        scope: .sharedVolume
      )
      let requiredBytes = try adding(
        transferAndStagingBytes,
        safetyMarginBytes,
        scope: .sharedVolume
      )
      try require(
        requiredBytes,
        availableBytes: min(
          downloadCapacity.availableBytes,
          artifactStoreCapacity.availableBytes
        ),
        scope: .sharedVolume
      )
      return
    }

    let requiredDownloadBytes = try adding(
      remainingDownloadBytes,
      safetyMarginBytes,
      scope: .download
    )
    try require(
      requiredDownloadBytes,
      availableBytes: downloadCapacity.availableBytes,
      scope: .download
    )

    let requiredArtifactStoreBytes = try adding(
      expectedByteCount,
      safetyMarginBytes,
      scope: .artifactStore
    )
    try require(
      requiredArtifactStoreBytes,
      availableBytes: artifactStoreCapacity.availableBytes,
      scope: .artifactStore
    )
  }

  private func capacity(
    at directoryURL: URL,
    scope: DownloadCapacityScope
  ) throws -> (deviceID: Int32, availableBytes: UInt64) {
    let capacity: DownloadFileSystemCapacity
    do {
      capacity = try capacityProvider.capacity(at: directoryURL)
    } catch let error as DownloadCapacityPreflightError {
      throw error
    } catch let error as POSIXError {
      throw DownloadCapacityPreflightError.directoryUnavailable(
        scope: scope,
        code: error.code.rawValue
      )
    } catch {
      throw DownloadCapacityPreflightError.directoryUnavailable(
        scope: scope,
        code: EIO
      )
    }

    let (availableBytes, overflow) = capacity.availableBlocks
      .multipliedReportingOverflow(by: capacity.blockSize)
    guard !overflow else {
      throw DownloadCapacityPreflightError.arithmeticOverflow(scope: scope)
    }
    return (capacity.deviceID, availableBytes)
  }

  private func adding(
    _ left: UInt64,
    _ right: UInt64,
    scope: DownloadCapacityScope
  ) throws -> UInt64 {
    let (sum, overflow) = left.addingReportingOverflow(right)
    guard !overflow else {
      throw DownloadCapacityPreflightError.arithmeticOverflow(scope: scope)
    }
    return sum
  }

  private func require(
    _ requiredBytes: UInt64,
    availableBytes: UInt64,
    scope: DownloadCapacityScope
  ) throws {
    guard availableBytes >= requiredBytes else {
      throw DownloadCapacityPreflightError.insufficientCapacity(
        scope: scope,
        required: requiredBytes,
        available: availableBytes
      )
    }
  }
}
