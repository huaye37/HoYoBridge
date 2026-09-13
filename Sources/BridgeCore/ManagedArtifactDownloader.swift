import CryptoKit
import Darwin
import Foundation

public enum ManagedArtifactDownloadError: Error, Equatable, Sendable {
  case invalidRuntimeExpectation(String)
  case disallowedURL(String)
  case tooManyRedirects(Int)
  case redirectRejected(String)
  case nonHTTPResponse
  case unexpectedStatus(Int)
  case invalidContentLength(String?)
  case invalidContentRange(String?)
  case unsupportedContentEncoding(String)
  case resumeValidatorChanged
  case artifactBusy(String)
  case sizeExceeded(expected: UInt64)
  case sizeMismatch(expected: UInt64, actual: UInt64)
}

private enum ResumeValidator: Codable, Equatable, Sendable {
  case strongETag(String)
  case lastModified(String)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  private enum Kind: String, Codable {
    case strongETag
    case lastModified
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    let value = try container.decode(String.self, forKey: .value)
    switch kind {
    case .strongETag: self = .strongETag(value)
    case .lastModified: self = .lastModified(value)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .strongETag(let value):
      try container.encode(Kind.strongETag, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .lastModified(let value):
      try container.encode(Kind.lastModified, forKey: .kind)
      try container.encode(value, forKey: .value)
    }
  }

  var headerValue: String {
    switch self {
    case .strongETag(let value), .lastModified(let value): value
    }
  }
}

private struct DownloadResumeMetadata: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let sourceURLSHA256: String
  let finalURLSHA256: String
  let expectedSize: UInt64
  let expectedSHA256: String
  let byteCount: UInt64
  let validator: ResumeValidator
}

private struct DownloadPaths: Sendable {
  let partialDirectory: URL
  let partialURL: URL
  let metadataURL: URL
  let leaseDirectory: URL
  let leaseURL: URL

  init(rootURL: URL, artifactSHA256: String) {
    partialDirectory = rootURL.appendingPathComponent(".partial", isDirectory: true)
    partialURL = partialDirectory.appendingPathComponent("\(artifactSHA256).part")
    metadataURL = partialDirectory.appendingPathComponent("\(artifactSHA256).resume.json")
    leaseDirectory = rootURL.appendingPathComponent(".leases", isDirectory: true)
    leaseURL = leaseDirectory.appendingPathComponent("\(artifactSHA256).lock")
  }
}

private struct ResumeTransferState: Sendable {
  let descriptor: Int32
  let metadata: DownloadResumeMetadata?

  var byteCount: UInt64 { metadata?.byteCount ?? 0 }
}

private struct ResumeCheckpointIdentity: Sendable {
  let sourceURLSHA256: String
  let finalURLSHA256: String
  let expectedSize: UInt64
  let expectedSHA256: String
  let validator: ResumeValidator

  func metadata(byteCount: UInt64) -> DownloadResumeMetadata {
    DownloadResumeMetadata(
      schemaVersion: 1,
      sourceURLSHA256: sourceURLSHA256,
      finalURLSHA256: finalURLSHA256,
      expectedSize: expectedSize,
      expectedSHA256: expectedSHA256,
      byteCount: byteCount,
      validator: validator
    )
  }
}

private enum DownloadRequestMode: Sendable {
  case fresh
  case resume(DownloadResumeMetadata)
}

private struct ValidatedDownloadResponse: Sendable {
  let startsAt: UInt64
  let resetsPartial: Bool
  let checkpointIdentity: ResumeCheckpointIdentity?
}

private final class ArtifactDownloadLease: @unchecked Sendable {
  private var descriptor: Int32

  private init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  static func acquire(at url: URL, artifactSHA256: String) throws -> ArtifactDownloadLease {
    var created = false
    var descriptor = open(
      url.path,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    if descriptor >= 0 {
      created = true
    } else if errno == EEXIST {
      descriptor = open(url.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    if created, fchmod(descriptor, S_IRUSR | S_IWUSR) != 0 {
      let savedError = errno
      close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFREG,
      metadata.st_uid == geteuid(),
      metadata.st_mode & 0o777 == 0o600,
      metadata.st_nlink == 1
    else {
      let savedError = errno
      close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }

    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      let lockError = errno
      if lockError == EINTR { continue }
      close(descriptor)
      if lockError == EWOULDBLOCK || lockError == EAGAIN {
        throw ManagedArtifactDownloadError.artifactBusy(artifactSHA256)
      }
      throw POSIXError(POSIXErrorCode(rawValue: lockError) ?? .EIO)
    }
    return ArtifactDownloadLease(descriptor: descriptor)
  }

  deinit {
    if descriptor >= 0 {
      _ = flock(descriptor, LOCK_UN)
      _ = close(descriptor)
      descriptor = -1
    }
  }
}

public struct ManagedArtifactDownloader: @unchecked Sendable {
  public static let defaultCapacitySafetyMarginBytes: UInt64 = 1_073_741_824

  public let downloadRootURL: URL
  public let allowedHosts: Set<String>
  public let maximumRedirects: Int
  public let capacitySafetyMarginBytes: UInt64

  private let configuration: URLSessionConfiguration
  private let capacityProvider: DownloadCapacityProvider

  public init(
    downloadRootURL: URL,
    allowedHosts: Set<String>,
    maximumRedirects: Int = 3,
    capacitySafetyMarginBytes: UInt64 = Self.defaultCapacitySafetyMarginBytes
  ) {
    self.init(
      downloadRootURL: downloadRootURL,
      allowedHosts: allowedHosts,
      maximumRedirects: maximumRedirects,
      configuration: .ephemeral,
      capacitySafetyMarginBytes: capacitySafetyMarginBytes
    )
  }

  init(
    downloadRootURL: URL,
    allowedHosts: Set<String>,
    maximumRedirects: Int = 3,
    configuration: URLSessionConfiguration,
    capacitySafetyMarginBytes: UInt64 = Self.defaultCapacitySafetyMarginBytes,
    capacityProvider: DownloadCapacityProvider = .system
  ) {
    self.downloadRootURL = downloadRootURL
    self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
    self.maximumRedirects = maximumRedirects
    self.capacitySafetyMarginBytes = capacitySafetyMarginBytes
    self.configuration = configuration.copy() as! URLSessionConfiguration
    self.capacityProvider = capacityProvider
  }

  public func download(
    runtime: RuntimeDefinition,
    into store: ContentAddressedArtifactStore
  ) async throws -> StoredArtifact {
    try Task.checkCancellation()

    guard runtime.acquisition == .managedDownload,
      let source = runtime.sourceURL,
      let sourceURL = URL(string: source),
      let expectedSize = runtime.byteSize,
      expectedSize > 0,
      expectedSize <= UInt64(Int64.max),
      let expectedHash = runtime.sha256,
      Self.isSHA256(expectedHash),
      runtime.redistributable,
      !runtime.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ManagedArtifactDownloadError.invalidRuntimeExpectation(runtime.id)
    }
    guard maximumRedirects >= 0 else {
      throw ManagedArtifactDownloadError.invalidRuntimeExpectation(runtime.id)
    }

    let normalizedHash = expectedHash.lowercased()
    let sourceURLSHA256 = Self.sha256(source)
    let policy = DownloadURLPolicy(
      allowedHosts: allowedHosts,
      maximumRedirects: maximumRedirects
    )
    try policy.validate(sourceURL)
    try Self.createPrivateDirectory(downloadRootURL)
    let paths = DownloadPaths(rootURL: downloadRootURL, artifactSHA256: normalizedHash)
    try Self.createPrivateDirectory(paths.partialDirectory)
    try Self.createPrivateDirectory(paths.leaseDirectory)
    let lease = try ArtifactDownloadLease.acquire(
      at: paths.leaseURL,
      artifactSHA256: normalizedHash
    )
    defer { withExtendedLifetime(lease) {} }

    let transfer = try Self.prepareTransfer(
      paths: paths,
      sourceURLSHA256: sourceURLSHA256,
      expectedSize: expectedSize,
      expectedSHA256: normalizedHash
    )
    var descriptor = transfer.descriptor
    var cleanupResumeStateOnExit = true
    defer {
      if descriptor >= 0 { _ = close(descriptor) }
      if cleanupResumeStateOnExit { try? Self.removeResumeState(paths: paths) }
    }

    do {
      try Self.createPrivateDirectory(store.rootURL)
      try DownloadCapacityPreflight(
        safetyMarginBytes: capacitySafetyMarginBytes,
        capacityProvider: capacityProvider
      ).check(
        downloadRootURL: downloadRootURL,
        artifactStoreRootURL: store.rootURL,
        expectedByteCount: expectedSize,
        partialByteCount: transfer.byteCount
      )
    } catch {
      if transfer.metadata != nil { cleanupResumeStateOnExit = false }
      throw error
    }

    if transfer.byteCount == expectedSize {
      guard fsync(descriptor) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      try Self.closeForCommit(&descriptor)
      _ = try ArtifactVerifier.verify(fileAt: paths.partialURL, for: runtime)
      try Task.checkCancellation()
      let stored = try store.store(fileAt: paths.partialURL, for: runtime)
      try Self.removeResumeState(paths: paths)
      cleanupResumeStateOnExit = false
      return stored
    }

    let sessionConfiguration = configuration.copy() as! URLSessionConfiguration
    sessionConfiguration.urlCache = nil
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    sessionConfiguration.httpCookieStorage = nil
    sessionConfiguration.httpShouldSetCookies = false
    sessionConfiguration.urlCredentialStorage = nil
    sessionConfiguration.timeoutIntervalForRequest = 60
    sessionConfiguration.timeoutIntervalForResource = 24 * 60 * 60
    sessionConfiguration.waitsForConnectivity = false
    let requestMode = transfer.metadata.map(DownloadRequestMode.resume) ?? .fresh
    let transferDelegate = ManagedDownloadDelegate(
      policy: policy,
      sourceURLSHA256: sourceURLSHA256,
      expectedSHA256: normalizedHash,
      expectedSize: expectedSize,
      descriptor: descriptor,
      mode: requestMode,
      metadataURL: paths.metadataURL,
      partialDirectory: paths.partialDirectory
    )
    let delegateQueue = OperationQueue()
    delegateQueue.maxConcurrentOperationCount = 1
    delegateQueue.qualityOfService = .utility
    let session = URLSession(
      configuration: sessionConfiguration,
      delegate: transferDelegate,
      delegateQueue: delegateQueue
    )
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: sourceURL)
    request.httpMethod = "GET"
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    if let resumeMetadata = transfer.metadata {
      request.setValue(
        "bytes=\(resumeMetadata.byteCount)-",
        forHTTPHeaderField: "Range"
      )
      request.setValue(
        resumeMetadata.validator.headerValue,
        forHTTPHeaderField: "If-Range"
      )
    }
    let dataTask = session.dataTask(with: request)

    do {
      try await withTaskCancellationHandler {
        try await transferDelegate.run(dataTask)
      } onCancel: {
        dataTask.cancel()
      }
      try Task.checkCancellation()
      guard fsync(descriptor) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      try Self.closeForCommit(&descriptor)
      _ = try ArtifactVerifier.verify(fileAt: paths.partialURL, for: runtime)
      try Task.checkCancellation()
      let stored = try store.store(fileAt: paths.partialURL, for: runtime)
      try Self.removeResumeState(paths: paths)
      cleanupResumeStateOnExit = false
      return stored
    } catch {
      let mayPreserve = Task.isCancelled || Self.isTransientNetworkFailure(error)
      if mayPreserve, let identity = transferDelegate.checkpointIdentity {
        do {
          try Self.checkpoint(
            descriptor: descriptor,
            identity: identity,
            paths: paths
          )
          cleanupResumeStateOnExit = false
        } catch {
          cleanupResumeStateOnExit = true
        }
      }
      if Task.isCancelled { throw CancellationError() }
      throw error
    }
  }

  fileprivate static func validate(
    response: URLResponse,
    policy: DownloadURLPolicy,
    sourceURLSHA256: String,
    expectedSHA256: String,
    expectedSize: UInt64,
    mode: DownloadRequestMode
  ) throws -> ValidatedDownloadResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ManagedArtifactDownloadError.nonHTTPResponse
    }
    guard let finalURL = httpResponse.url else {
      throw ManagedArtifactDownloadError.nonHTTPResponse
    }
    try policy.validate(finalURL)
    if let encoding = httpResponse.value(forHTTPHeaderField: "Content-Encoding"),
      encoding.caseInsensitiveCompare("identity") != .orderedSame
    {
      throw ManagedArtifactDownloadError.unsupportedContentEncoding(encoding)
    }

    switch mode {
    case .fresh:
      guard httpResponse.statusCode == 200 else {
        throw ManagedArtifactDownloadError.unexpectedStatus(httpResponse.statusCode)
      }
      try validateContentLength(httpResponse, expected: expectedSize)
      return ValidatedDownloadResponse(
        startsAt: 0,
        resetsPartial: false,
        checkpointIdentity: checkpointIdentity(
          response: httpResponse,
          sourceURLSHA256: sourceURLSHA256,
          expectedSHA256: expectedSHA256,
          expectedSize: expectedSize
        )
      )

    case .resume(let metadata):
      if httpResponse.statusCode == 200 {
        try validateContentLength(httpResponse, expected: expectedSize)
        return ValidatedDownloadResponse(
          startsAt: 0,
          resetsPartial: true,
          checkpointIdentity: checkpointIdentity(
            response: httpResponse,
            sourceURLSHA256: sourceURLSHA256,
            expectedSHA256: expectedSHA256,
            expectedSize: expectedSize
          )
        )
      }
      guard httpResponse.statusCode == 206 else {
        throw ManagedArtifactDownloadError.unexpectedStatus(httpResponse.statusCode)
      }
      guard Self.sha256(finalURL.absoluteString) == metadata.finalURLSHA256 else {
        throw ManagedArtifactDownloadError.resumeValidatorChanged
      }
      guard responseValidator(httpResponse, matches: metadata.validator) else {
        throw ManagedArtifactDownloadError.resumeValidatorChanged
      }
      let expectedRemaining = expectedSize - metadata.byteCount
      try validateContentLength(httpResponse, expected: expectedRemaining)
      let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range")
      guard let parsedRange = parseContentRange(contentRange),
        parsedRange.start == metadata.byteCount,
        parsedRange.end == expectedSize - 1,
        parsedRange.total == expectedSize
      else {
        throw ManagedArtifactDownloadError.invalidContentRange(contentRange)
      }
      return ValidatedDownloadResponse(
        startsAt: metadata.byteCount,
        resetsPartial: false,
        checkpointIdentity: ResumeCheckpointIdentity(
          sourceURLSHA256: sourceURLSHA256,
          finalURLSHA256: metadata.finalURLSHA256,
          expectedSize: expectedSize,
          expectedSHA256: expectedSHA256,
          validator: metadata.validator
        )
      )
    }
  }

  private static func prepareTransfer(
    paths: DownloadPaths,
    sourceURLSHA256: String,
    expectedSize: UInt64,
    expectedSHA256: String
  ) throws -> ResumeTransferState {
    let hasPartial = try entryExists(at: paths.partialURL)
    let hasMetadata = try entryExists(at: paths.metadataURL)
    if hasPartial, hasMetadata {
      var descriptor: Int32 = -1
      do {
        descriptor = try openExistingPartial(at: paths.partialURL)
        let fileSize = try validatedPartialSize(
          descriptor: descriptor,
          expectedSize: expectedSize,
          allowComplete: true
        )
        let metadata = try readMetadata(at: paths.metadataURL)
        guard metadata.schemaVersion == 1,
          metadata.sourceURLSHA256 == sourceURLSHA256,
          metadata.expectedSize == expectedSize,
          metadata.expectedSHA256 == expectedSHA256,
          metadata.byteCount == fileSize,
          metadata.byteCount > 0,
          metadata.byteCount <= expectedSize,
          isSHA256(metadata.sourceURLSHA256),
          isSHA256(metadata.finalURLSHA256),
          isSHA256(metadata.expectedSHA256),
          validatorIsValid(metadata.validator),
          lseek(descriptor, off_t(fileSize), SEEK_SET) == off_t(fileSize)
        else {
          throw POSIXError(.EINVAL)
        }
        return ResumeTransferState(descriptor: descriptor, metadata: metadata)
      } catch {
        if descriptor >= 0 { _ = close(descriptor) }
        try removeResumeState(paths: paths)
      }
    } else if hasPartial || hasMetadata {
      try removeResumeState(paths: paths)
    }
    return ResumeTransferState(
      descriptor: try createPartial(at: paths.partialURL),
      metadata: nil
    )
  }

  private static func createPartial(at url: URL) throws -> Int32 {
    let descriptor = open(
      url.path,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    if fchmod(descriptor, S_IRUSR | S_IWUSR) != 0 {
      let savedError = errno
      close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFREG,
      metadata.st_uid == geteuid(),
      metadata.st_mode & 0o777 == 0o600,
      metadata.st_nlink == 1
    else {
      let savedError = errno
      close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    return descriptor
  }

  private static func openExistingPartial(at url: URL) throws -> Int32 {
    let descriptor = open(url.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFREG,
      metadata.st_uid == geteuid(),
      metadata.st_mode & 0o777 == 0o600,
      metadata.st_nlink == 1
    else {
      let savedError = errno
      close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    return descriptor
  }

  private static func validatedPartialSize(
    descriptor: Int32,
    expectedSize: UInt64,
    allowComplete: Bool
  ) throws -> UInt64 {
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
      metadata.st_size > 0,
      metadata.st_size <= Int64.max
    else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
    }
    let size = UInt64(metadata.st_size)
    guard size < expectedSize || (allowComplete && size == expectedSize) else {
      throw POSIXError(.EINVAL)
    }
    return size
  }

  private static func readMetadata(at url: URL) throws -> DownloadResumeMetadata {
    let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { _ = close(descriptor) }
    var fileMetadata = stat()
    guard fstat(descriptor, &fileMetadata) == 0,
      fileMetadata.st_mode & S_IFMT == S_IFREG,
      fileMetadata.st_uid == geteuid(),
      fileMetadata.st_mode & 0o777 == 0o600,
      fileMetadata.st_nlink == 1,
      fileMetadata.st_size > 0,
      fileMetadata.st_size <= 16_384
    else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
    }
    var bytes = [UInt8](repeating: 0, count: Int(fileMetadata.st_size))
    var offset = 0
    while offset < bytes.count {
      let remaining = bytes.count - offset
      let count = bytes.withUnsafeMutableBytes { buffer in
        read(descriptor, buffer.baseAddress?.advanced(by: offset), remaining)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard count > 0 else { throw POSIXError(.EIO) }
      offset += count
    }
    return try JSONDecoder().decode(DownloadResumeMetadata.self, from: Data(bytes))
  }

  private static func checkpoint(
    descriptor: Int32,
    identity: ResumeCheckpointIdentity,
    paths: DownloadPaths
  ) throws {
    guard fsync(descriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let byteCount = try validatedPartialSize(
      descriptor: descriptor,
      expectedSize: identity.expectedSize,
      allowComplete: false
    )
    try writeMetadataAtomically(
      identity.metadata(byteCount: byteCount),
      to: paths.metadataURL,
      in: paths.partialDirectory
    )
  }

  private static func writeMetadataAtomically(
    _ metadata: DownloadResumeMetadata,
    to url: URL,
    in directory: URL
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(metadata)
    guard !data.isEmpty, data.count <= 16_384 else { throw POSIXError(.EFBIG) }
    let temporaryURL = directory.appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
    )
    var descriptor = open(
      temporaryURL.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer {
      if descriptor >= 0 { _ = close(descriptor) }
      _ = unlink(temporaryURL.path)
    }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try writeAll(data, to: descriptor)
    guard fsync(descriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try closeForCommit(&descriptor)
    guard rename(temporaryURL.path, url.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try fsyncDirectory(directory)
  }

  private static func removeResumeState(paths: DownloadPaths) throws {
    try unlinkIfPresent(paths.metadataURL)
    try unlinkIfPresent(paths.partialURL)
    try fsyncDirectory(paths.partialDirectory)
  }

  fileprivate static func invalidateMetadata(at url: URL, in directory: URL) throws {
    try unlinkIfPresent(url)
    try fsyncDirectory(directory)
  }

  private static func unlinkIfPresent(_ url: URL) throws {
    guard unlink(url.path) == 0 || errno == ENOENT else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private static func entryExists(at url: URL) throws -> Bool {
    var metadata = stat()
    if lstat(url.path, &metadata) == 0 { return true }
    if errno == ENOENT { return false }
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  private static func fsyncDirectory(_ url: URL) throws {
    let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { _ = close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private static func closeForCommit(_ descriptor: inout Int32) throws {
    let ownedDescriptor = descriptor
    descriptor = -1
    guard close(ownedDescriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private static func validateContentLength(
    _ response: HTTPURLResponse,
    expected: UInt64
  ) throws {
    let contentLength = response.value(forHTTPHeaderField: "Content-Length")
    guard let contentLength,
      !contentLength.isEmpty,
      contentLength.utf8.allSatisfy({ (48...57).contains($0) }),
      let parsedLength = UInt64(contentLength),
      parsedLength == expected
    else {
      throw ManagedArtifactDownloadError.invalidContentLength(contentLength)
    }
  }

  static func parseContentRange(
    _ value: String?
  ) -> (start: UInt64, end: UInt64, total: UInt64)? {
    guard let value, value.hasPrefix("bytes ") else { return nil }
    let components = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
    guard components.count == 2,
      !components[0].isEmpty,
      !components[1].isEmpty,
      components[1].utf8.allSatisfy({ (48...57).contains($0) }),
      let total = UInt64(components[1])
    else { return nil }
    let bounds = components[0].split(separator: "-", omittingEmptySubsequences: false)
    guard bounds.count == 2,
      !bounds[0].isEmpty,
      !bounds[1].isEmpty,
      bounds[0].utf8.allSatisfy({ (48...57).contains($0) }),
      bounds[1].utf8.allSatisfy({ (48...57).contains($0) }),
      let start = UInt64(bounds[0]),
      let end = UInt64(bounds[1]),
      start <= end,
      end < total
    else { return nil }
    return (start, end, total)
  }

  private static func checkpointIdentity(
    response: HTTPURLResponse,
    sourceURLSHA256: String,
    expectedSHA256: String,
    expectedSize: UInt64
  ) -> ResumeCheckpointIdentity? {
    guard let finalURL = response.url,
      let validator = responseValidator(response)
    else { return nil }
    return ResumeCheckpointIdentity(
      sourceURLSHA256: sourceURLSHA256,
      finalURLSHA256: sha256(finalURL.absoluteString),
      expectedSize: expectedSize,
      expectedSHA256: expectedSHA256,
      validator: validator
    )
  }

  private static func responseValidator(_ response: HTTPURLResponse) -> ResumeValidator? {
    if let etag = response.value(forHTTPHeaderField: "ETag"), isStrongETag(etag) {
      return .strongETag(etag)
    }
    if let lastModified = response.value(forHTTPHeaderField: "Last-Modified"),
      isStrongLastModified(lastModified, in: response)
    {
      return .lastModified(lastModified)
    }
    return nil
  }

  private static func responseValidator(
    _ response: HTTPURLResponse,
    matches validator: ResumeValidator
  ) -> Bool {
    switch validator {
    case .strongETag(let expected):
      guard let actual = response.value(forHTTPHeaderField: "ETag") else { return false }
      return actual == expected && isStrongETag(actual)
    case .lastModified(let expected):
      guard let actual = response.value(forHTTPHeaderField: "Last-Modified") else {
        return false
      }
      return actual == expected && isStrongLastModified(actual, in: response)
    }
  }

  private static func validatorIsValid(_ validator: ResumeValidator) -> Bool {
    switch validator {
    case .strongETag(let value): isStrongETag(value)
    case .lastModified(let value): isStrictHTTPDate(value)
    }
  }

  static func isStrongETag(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count >= 2,
      bytes.count <= 1_024,
      bytes.first == 0x22,
      bytes.last == 0x22
    else { return false }
    return bytes.dropFirst().dropLast().allSatisfy { byte in
      byte == 0x21 || (0x23...0x7E).contains(byte) || byte >= 0x80
    }
  }

  private static func isStrictHTTPDate(_ value: String) -> Bool {
    parseHTTPDate(value) != nil
  }

  static func isStrongLastModified(
    _ value: String,
    in response: HTTPURLResponse
  ) -> Bool {
    guard let lastModified = parseHTTPDate(value),
      let dateValue = response.value(forHTTPHeaderField: "Date"),
      let responseDate = parseHTTPDate(dateValue)
    else { return false }
    return responseDate.timeIntervalSince(lastModified) >= 60
  }

  private static func parseHTTPDate(_ value: String) -> Date? {
    guard value.utf8.count == 29,
      value.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E })
    else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
    formatter.isLenient = false
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
      return nil
    }
    return date
  }

  private static func isTransientNetworkFailure(_ error: any Error) -> Bool {
    guard let error = error as? URLError else { return false }
    switch error.code {
    case .timedOut, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed,
      .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed,
      .resourceUnavailable:
      return true
    default:
      return false
    }
  }

  fileprivate static func writeAll(_ data: Data, to descriptor: Int32) throws {
    var written = 0
    while written < data.count {
      let count = data.withUnsafeBytes { buffer in
        write(descriptor, buffer.baseAddress?.advanced(by: written), data.count - written)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard count > 0 else { throw POSIXError(.EIO) }
      written += count
    }
  }

  private static func createPrivateDirectory(_ url: URL) throws {
    let result = url.path.withCString { mkdir($0, S_IRWXU) }
    if result != 0 {
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

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

struct DownloadURLPolicy: Sendable {
  let allowedHosts: Set<String>
  let maximumRedirects: Int

  func validate(_ url: URL) throws {
    let host = url.host?.lowercased()
    guard url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      url.fragment == nil,
      url.port == nil || url.port == 443,
      let host,
      allowedHosts.contains(host),
      isPublicDNSName(host)
    else {
      throw ManagedArtifactDownloadError.disallowedURL(Self.redactedOrigin(url))
    }
  }

  func validateRedirect(_ url: URL, number: Int) throws {
    guard number <= maximumRedirects else {
      throw ManagedArtifactDownloadError.tooManyRedirects(maximumRedirects)
    }
    do {
      try validate(url)
    } catch {
      throw ManagedArtifactDownloadError.redirectRejected(Self.redactedOrigin(url))
    }
  }

  private func isPublicDNSName(_ host: String) -> Bool {
    guard host.contains("."),
      !host.hasSuffix("."),
      host != "localhost",
      !host.hasSuffix(".localhost"),
      !host.hasSuffix(".local")
    else {
      return false
    }

    var ipv4 = in_addr()
    if host.withCString({ inet_aton($0, &ipv4) }) == 1 { return false }
    var ipv6 = in6_addr()
    if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 { return false }
    return true
  }

  static func redactedOrigin(_ url: URL) -> String {
    let scheme = url.scheme?.lowercased() ?? "unknown"
    let host = url.host?.lowercased() ?? "unknown"
    return "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")"
  }
}

struct DownloadByteCounter: Sendable {
  let expectedSize: UInt64
  private(set) var actualSize: UInt64

  init(expectedSize: UInt64, actualSize: UInt64 = 0) {
    self.expectedSize = expectedSize
    self.actualSize = actualSize
  }

  mutating func consume(count: UInt64 = 1) throws {
    guard actualSize <= expectedSize, count <= expectedSize - actualSize else {
      throw ManagedArtifactDownloadError.sizeExceeded(expected: expectedSize)
    }
    actualSize += count
  }

  mutating func reset(to size: UInt64) throws {
    guard size <= expectedSize else {
      throw ManagedArtifactDownloadError.sizeExceeded(expected: expectedSize)
    }
    actualSize = size
  }

  func finish() throws {
    guard actualSize == expectedSize else {
      throw ManagedArtifactDownloadError.sizeMismatch(
        expected: expectedSize,
        actual: actualSize
      )
    }
  }
}

final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let policy: DownloadURLPolicy
  private let rangeHeader: String?
  private let ifRangeHeader: String?
  private let lock = NSLock()
  private var redirectCount = 0
  private var storedRejection: ManagedArtifactDownloadError?

  init(
    policy: DownloadURLPolicy,
    rangeHeader: String? = nil,
    ifRangeHeader: String? = nil
  ) {
    self.policy = policy
    self.rangeHeader = rangeHeader
    self.ifRangeHeader = ifRangeHeader
  }

  var rejection: ManagedArtifactDownloadError? {
    lock.lock()
    defer { lock.unlock() }
    return storedRejection
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    let decision: Result<URLRequest, ManagedArtifactDownloadError>
    lock.lock()
    redirectCount += 1
    let currentCount = redirectCount
    lock.unlock()

    if let url = request.url {
      do {
        try policy.validateRedirect(url, number: currentCount)
        var sanitizedRequest = request
        sanitizedRequest.httpMethod = "GET"
        sanitizedRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        sanitizedRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        sanitizedRequest.setValue(ifRangeHeader, forHTTPHeaderField: "If-Range")
        decision = .success(sanitizedRequest)
      } catch let error as ManagedArtifactDownloadError {
        decision = .failure(error)
      } catch {
        decision = .failure(.redirectRejected(DownloadURLPolicy.redactedOrigin(url)))
      }
    } else {
      decision = .failure(.redirectRejected("unknown://unknown"))
    }

    switch decision {
    case .success(let request):
      completionHandler(request)
    case .failure(let error):
      lock.lock()
      if storedRejection == nil { storedRejection = error }
      lock.unlock()
      completionHandler(nil)
    }
  }
}

private final class ManagedDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let policy: DownloadURLPolicy
  private let sourceURLSHA256: String
  private let expectedSHA256: String
  private let expectedSize: UInt64
  private let descriptor: Int32
  private let mode: DownloadRequestMode
  private let metadataURL: URL
  private let partialDirectory: URL
  private let redirectDelegate: RedirectDelegate
  private let stateLock = NSLock()

  private var byteCounter: DownloadByteCounter
  private var terminalError: (any Error)?
  private var storedCheckpointIdentity: ResumeCheckpointIdentity?
  private var receivedResponse = false
  private var continuation: CheckedContinuation<Void, any Error>?
  private var completionResult: Result<Void, any Error>?
  private var completed = false

  init(
    policy: DownloadURLPolicy,
    sourceURLSHA256: String,
    expectedSHA256: String,
    expectedSize: UInt64,
    descriptor: Int32,
    mode: DownloadRequestMode,
    metadataURL: URL,
    partialDirectory: URL
  ) {
    self.policy = policy
    self.sourceURLSHA256 = sourceURLSHA256
    self.expectedSHA256 = expectedSHA256
    self.expectedSize = expectedSize
    self.descriptor = descriptor
    self.mode = mode
    self.metadataURL = metadataURL
    self.partialDirectory = partialDirectory
    switch mode {
    case .fresh:
      redirectDelegate = RedirectDelegate(policy: policy)
      byteCounter = DownloadByteCounter(expectedSize: expectedSize)
    case .resume(let metadata):
      redirectDelegate = RedirectDelegate(
        policy: policy,
        rangeHeader: "bytes=\(metadata.byteCount)-",
        ifRangeHeader: metadata.validator.headerValue
      )
      byteCounter = DownloadByteCounter(
        expectedSize: expectedSize,
        actualSize: metadata.byteCount
      )
      storedCheckpointIdentity = ResumeCheckpointIdentity(
        sourceURLSHA256: metadata.sourceURLSHA256,
        finalURLSHA256: metadata.finalURLSHA256,
        expectedSize: metadata.expectedSize,
        expectedSHA256: metadata.expectedSHA256,
        validator: metadata.validator
      )
    }
  }

  var checkpointIdentity: ResumeCheckpointIdentity? {
    stateLock.lock()
    defer { stateLock.unlock() }
    return storedCheckpointIdentity
  }

  func run(_ task: URLSessionDataTask) async throws {
    try await withCheckedThrowingContinuation { continuation in
      stateLock.lock()
      precondition(self.continuation == nil)
      if let completionResult {
        stateLock.unlock()
        continuation.resume(with: completionResult)
        return
      }
      self.continuation = continuation
      stateLock.unlock()
      task.resume()
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    redirectDelegate.urlSession(
      session,
      task: task,
      willPerformHTTPRedirection: response,
      newRequest: request,
      completionHandler: completionHandler
    )
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    do {
      if let redirectError = redirectDelegate.rejection { throw redirectError }
      guard !receivedResponse else { throw ManagedArtifactDownloadError.nonHTTPResponse }
      let validated = try ManagedArtifactDownloader.validate(
        response: response,
        policy: policy,
        sourceURLSHA256: sourceURLSHA256,
        expectedSHA256: expectedSHA256,
        expectedSize: expectedSize,
        mode: mode
      )
      if validated.resetsPartial {
        try ManagedArtifactDownloader.invalidateMetadata(
          at: metadataURL,
          in: partialDirectory
        )
        guard ftruncate(descriptor, 0) == 0,
          lseek(descriptor, 0, SEEK_SET) == 0
        else {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try byteCounter.reset(to: 0)
      } else {
        guard byteCounter.actualSize == validated.startsAt,
          lseek(descriptor, off_t(validated.startsAt), SEEK_SET) == off_t(validated.startsAt)
        else {
          throw POSIXError(.EINVAL)
        }
      }
      stateLock.lock()
      storedCheckpointIdentity = validated.checkpointIdentity
      stateLock.unlock()
      receivedResponse = true
      completionHandler(.allow)
    } catch {
      recordTerminalError(error)
      completionHandler(.cancel)
    }
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard terminalError == nil else { return }
    do {
      try byteCounter.consume(count: UInt64(data.count))
      try ManagedArtifactDownloader.writeAll(data, to: descriptor)
    } catch {
      recordTerminalError(error)
      dataTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let redirectError = redirectDelegate.rejection {
      finish(.failure(redirectError))
      return
    }
    if let terminalError {
      finish(.failure(terminalError))
      return
    }
    if let error {
      if (error as? URLError)?.code == .cancelled {
        finish(.failure(CancellationError()))
      } else {
        finish(.failure(error))
      }
      return
    }
    do {
      try byteCounter.finish()
      finish(.success(()))
    } catch {
      finish(.failure(error))
    }
  }

  private func recordTerminalError(_ error: any Error) {
    if terminalError == nil { terminalError = error }
  }

  private func finish(_ result: Result<Void, any Error>) {
    stateLock.lock()
    guard !completed else {
      stateLock.unlock()
      return
    }
    completed = true
    let continuation = continuation
    self.continuation = nil
    if continuation == nil { completionResult = result }
    stateLock.unlock()
    continuation?.resume(with: result)
  }
}
