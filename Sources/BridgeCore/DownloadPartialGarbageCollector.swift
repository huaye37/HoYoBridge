import Darwin
import Foundation

public enum DownloadPartialDirectory: String, Equatable, Sendable {
  case root
  case partial
  case leases
}

public enum DownloadPartialGarbageCollectorError: Error, Equatable, Sendable {
  case invalidRootURL
  case missingDirectory(DownloadPartialDirectory)
  case unsafeDirectory(DownloadPartialDirectory)
}

public struct DownloadPartialGarbageCollectionReport: Equatable, Sendable {
  public let cleaned: [String]
  public let skippedBusy: [String]
  public let unsafe: [String]
}

/// Explicit maintenance for resumable downloads. Nothing schedules this collector automatically.
public struct DownloadPartialGarbageCollector: Sendable {
  public let downloadRootURL: URL

  public init(downloadRootURL: URL) {
    self.downloadRootURL = downloadRootURL
  }

  public func collect(staleBefore cutoff: Date) throws
    -> DownloadPartialGarbageCollectionReport
  {
    let rootDescriptor = try Self.openRoot(downloadRootURL)
    defer { _ = close(rootDescriptor) }
    let partialDescriptor = try Self.openDirectory(
      named: ".partial",
      relativeTo: rootDescriptor,
      role: .partial
    )
    defer { _ = close(partialDescriptor) }
    let leaseDescriptor = try Self.openDirectory(
      named: ".leases",
      relativeTo: rootDescriptor,
      role: .leases
    )
    defer { _ = close(leaseDescriptor) }

    var cleaned: [String] = []
    var skippedBusy: [String] = []
    var unsafe: [String] = []
    let candidates = try Self.candidates(in: partialDescriptor)
    for hash in candidates.keys.sorted() {
      switch try Self.collect(
        hash: hash,
        names: candidates[hash, default: []],
        staleBefore: cutoff,
        partialDescriptor: partialDescriptor,
        leaseDescriptor: leaseDescriptor
      ) {
      case .cleaned: cleaned.append(hash)
      case .busy: skippedBusy.append(hash)
      case .unsafe: unsafe.append(hash)
      case .retained: break
      }
    }
    return DownloadPartialGarbageCollectionReport(
      cleaned: cleaned,
      skippedBusy: skippedBusy,
      unsafe: unsafe
    )
  }

  private enum CandidateOutcome {
    case cleaned
    case busy
    case retained
    case unsafe
  }

  private enum LeaseOutcome {
    case acquired(descriptor: Int32, created: Bool)
    case busy
    case unsafe
  }

  private struct CandidateFile {
    let descriptor: Int32
    let name: String
    let metadata: stat
  }

  private static func collect(
    hash: String,
    names: [String],
    staleBefore cutoff: Date,
    partialDescriptor: Int32,
    leaseDescriptor: Int32
  ) throws -> CandidateOutcome {
    switch try acquireLease(for: hash, in: leaseDescriptor) {
    case .busy:
      return .busy
    case .unsafe:
      return .unsafe
    case .acquired(let descriptor, let created):
      defer {
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
      }
      if created { try syncDirectory(leaseDescriptor) }
      return try inspectAndClean(
        names: names,
        staleBefore: cutoff,
        in: partialDescriptor
      )
    }
  }

  private static func acquireLease(for hash: String, in directory: Int32) throws
    -> LeaseOutcome
  {
    let name = "\(hash).lock"
    var descriptor = openat(
      directory,
      name,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    let created = descriptor >= 0
    if descriptor < 0, errno == EEXIST {
      descriptor = openat(
        directory,
        name,
        O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
      )
    }
    guard descriptor >= 0 else {
      if [EACCES, EISDIR, ELOOP, ENXIO].contains(errno) { return .unsafe }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    if created, fchmod(descriptor, S_IRUSR | S_IWUSR) != 0 {
      let savedError = errno
      _ = close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else {
      let savedError = errno
      _ = close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    guard isPrivateRegularFile(metadata) else {
      _ = close(descriptor)
      return .unsafe
    }
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      let lockError = errno
      if lockError == EINTR { continue }
      _ = close(descriptor)
      if lockError == EWOULDBLOCK || lockError == EAGAIN { return .busy }
      throw POSIXError(POSIXErrorCode(rawValue: lockError) ?? .EIO)
    }
    return .acquired(descriptor: descriptor, created: created)
  }

  private static func inspectAndClean(
    names: [String],
    staleBefore cutoff: Date,
    in directory: Int32
  ) throws -> CandidateOutcome {
    var files: [CandidateFile] = []
    defer {
      for file in files { _ = close(file.descriptor) }
    }

    for name in names.sorted() {
      switch try openCandidate(named: name, in: directory) {
      case .missing:
        continue
      case .unsafe:
        return .unsafe
      case .valid(let file):
        files.append(file)
      }
    }
    guard !files.isEmpty else { return .retained }
    guard files.allSatisfy({ modificationDate($0.metadata) < cutoff }) else {
      return .retained
    }
    guard files.allSatisfy({ entryStillMatches($0, in: directory, cutoff: cutoff) }) else {
      return .unsafe
    }
    var deletedAny = false
    do {
      for file in files {
        guard entryStillMatches(file, in: directory, cutoff: cutoff) else {
          if deletedAny { try syncDirectory(directory) }
          return .unsafe
        }
        guard unlinkat(directory, file.name, 0) == 0 else {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        deletedAny = true
      }
      if deletedAny { try syncDirectory(directory) }
      return .cleaned
    } catch {
      if deletedAny { try syncDirectory(directory) }
      throw error
    }
  }

  private enum CandidateFileOutcome {
    case missing
    case unsafe
    case valid(CandidateFile)
  }

  private static func openCandidate(named name: String, in directory: Int32) throws
    -> CandidateFileOutcome
  {
    var pathMetadata = stat()
    guard fstatat(directory, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return .missing }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard isPrivateRegularFile(pathMetadata) else { return .unsafe }

    let descriptor = openat(
      directory,
      name,
      O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      if errno == ENOENT || errno == ELOOP { return .unsafe }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var openedMetadata = stat()
    guard fstat(descriptor, &openedMetadata) == 0 else {
      let savedError = errno
      _ = close(descriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    guard isPrivateRegularFile(openedMetadata), sameFile(pathMetadata, openedMetadata) else {
      _ = close(descriptor)
      return .unsafe
    }
    return .valid(
      CandidateFile(descriptor: descriptor, name: name, metadata: openedMetadata)
    )
  }

  private static func entryStillMatches(
    _ file: CandidateFile,
    in directory: Int32,
    cutoff: Date
  ) -> Bool {
    var openedMetadata = stat()
    var pathMetadata = stat()
    return fstat(file.descriptor, &openedMetadata) == 0
      && fstatat(directory, file.name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0
      && isPrivateRegularFile(openedMetadata)
      && isPrivateRegularFile(pathMetadata)
      && sameFile(file.metadata, openedMetadata)
      && sameFile(openedMetadata, pathMetadata)
      && modificationDate(openedMetadata) < cutoff
  }

  private static func candidates(in descriptor: Int32) throws -> [String: [String]] {
    let duplicatedDescriptor = dup(descriptor)
    guard duplicatedDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard let directory = fdopendir(duplicatedDescriptor) else {
      let savedError = errno
      _ = close(duplicatedDescriptor)
      throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
    }
    defer { _ = closedir(directory) }

    var candidates: [String: [String]] = [:]
    while true {
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 {
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(cString: $0)
        }
      }
      if let hash = recognizedHash(in: name) {
        candidates[hash, default: []].append(name)
      }
    }
    return candidates
  }

  private static func recognizedHash(in name: String) -> String? {
    let suffix: String
    if name.hasSuffix(".part") {
      suffix = ".part"
    } else if name.hasSuffix(".resume.json") {
      suffix = ".resume.json"
    } else if name.hasPrefix("."), name.hasSuffix(".tmp") {
      let body = name.dropFirst().dropLast(4)
      guard body.count > 64 else { return nil }
      let hash = String(body.prefix(64))
      let remainder = body.dropFirst(64)
      let metadataPrefix = ".resume.json."
      guard remainder.hasPrefix(metadataPrefix) else { return nil }
      let uuid = String(remainder.dropFirst(metadataPrefix.count))
      guard UUID(uuidString: uuid) != nil, isLowercaseSHA256(hash) else { return nil }
      return hash
    } else {
      return nil
    }
    let hash = String(name.dropLast(suffix.count))
    guard isLowercaseSHA256(hash) else { return nil }
    return hash
  }

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
  }

  private static func openRoot(_ url: URL) throws -> Int32 {
    guard url.isFileURL else { throw DownloadPartialGarbageCollectorError.invalidRootURL }
    var beforeOpen = stat()
    guard lstat(url.path, &beforeOpen) == 0 else {
      if errno == ENOENT {
        throw DownloadPartialGarbageCollectorError.missingDirectory(.root)
      }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard isPrivateDirectory(beforeOpen) else {
      throw DownloadPartialGarbageCollectorError.unsafeDirectory(.root)
    }
    let descriptor = open(
      url.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var afterOpen = stat()
    guard fstat(descriptor, &afterOpen) == 0,
      isPrivateDirectory(afterOpen),
      sameFile(beforeOpen, afterOpen)
    else {
      _ = close(descriptor)
      throw DownloadPartialGarbageCollectorError.unsafeDirectory(.root)
    }
    return descriptor
  }

  private static func openDirectory(
    named name: String,
    relativeTo parent: Int32,
    role: DownloadPartialDirectory
  ) throws -> Int32 {
    var beforeOpen = stat()
    guard fstatat(parent, name, &beforeOpen, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT {
        throw DownloadPartialGarbageCollectorError.missingDirectory(role)
      }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard isPrivateDirectory(beforeOpen) else {
      throw DownloadPartialGarbageCollectorError.unsafeDirectory(role)
    }
    let descriptor = openat(
      parent,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    var afterOpen = stat()
    guard fstat(descriptor, &afterOpen) == 0,
      isPrivateDirectory(afterOpen),
      sameFile(beforeOpen, afterOpen)
    else {
      _ = close(descriptor)
      throw DownloadPartialGarbageCollectorError.unsafeDirectory(role)
    }
    return descriptor
  }

  private static func isPrivateDirectory(_ metadata: stat) -> Bool {
    metadata.st_mode & S_IFMT == S_IFDIR
      && metadata.st_uid == geteuid()
      && metadata.st_mode & 0o777 == 0o700
  }

  private static func isPrivateRegularFile(_ metadata: stat) -> Bool {
    metadata.st_mode & S_IFMT == S_IFREG
      && metadata.st_uid == geteuid()
      && metadata.st_mode & 0o777 == 0o600
      && metadata.st_nlink == 1
  }

  private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
  }

  private static func modificationDate(_ metadata: stat) -> Date {
    Date(
      timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec)
        + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000
    )
  }

  private static func syncDirectory(_ descriptor: Int32) throws {
    guard fsync(descriptor) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
