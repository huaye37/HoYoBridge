import CryptoKit
import Darwin
import Foundation

public protocol ArchiveEntryContentReading: AnyObject {
  /// Returns 0 for EOF. Values outside 0...buffer.count are invalid.
  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int
}

public protocol ArchivePlannedContentSource: AnyObject {
  var artifactSHA256: String { get }
  var entryCount: Int { get }

  func descriptor(forSourcePathSHA256 digest: String) throws -> ArchiveEntryDescriptor
  func reader(for entry: PlannedArchiveEntry) throws -> any ArchiveEntryContentReading
  func finish() throws
}

public enum SafeStagingExtractionError: Error, Equatable, Sendable {
  case unsupportedPolicyVersion(Int)
  case invalidArtifactIdentity
  case sourceEntryCountMismatch(expected: Int, actual: Int)
  case sourceDescriptorMismatch
  case invalidStagingRoot
  case unsafeParentDirectory
  case stagingRootAlreadyExists
  case filesystemEntryConflict
  case unsafeFilesystemEntry
  case invalidReaderCount(Int)
  case entrySizeExceeded(expected: UInt64)
  case entrySizeMismatch(expected: UInt64, actual: UInt64)
  case totalSizeExceeded(expected: UInt64)
  case totalSizeMismatch(expected: UInt64, actual: UInt64)
  case fileContentChanged
  case cleanupFailed
}

public struct SafeStagingExtractionAndCleanupError: Error {
  public let extractionError: any Error
  public let cleanupError: any Error
}

public struct StagingTreeSealEntry: Encodable, Equatable, Sendable {
  public let relativePath: String
  public let kind: ArchiveEntryKind
  public let size: UInt64
  public let mode: UInt16
  public let contentSHA256: String?
}

enum SafeStagingTreeSealer {
  static let currentVersion: UInt8 = 1

  static func canonicalSHA256(for entries: [StagingTreeSealEntry]) -> String {
    var digest = CanonicalSHA256Builder(domain: Array("MGBTREE".utf8))
    digest.append(currentVersion)
    let ordered = entries.sorted { utf8Less($0.relativePath, $1.relativePath) }
    digest.append(UInt32(ordered.count))
    for entry in ordered {
      digest.append(entry.kind.sealTag)
      digest.appendFramed(entry.relativePath.precomposedStringWithCanonicalMapping)
      digest.append(entry.mode)
      digest.append(entry.size)
      if entry.kind == .regularFile {
        guard let contentSHA256 = entry.contentSHA256 else {
          preconditionFailure("Regular-file tree seals require a content digest")
        }
        digest.appendSHA256(contentSHA256)
      } else {
        precondition(entry.kind == .directory && entry.contentSHA256 == nil)
      }
    }
    return digest.finalize()
  }

  private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
  }
}

public struct ExtractedStagingTree: Encodable, Equatable, Sendable {
  public let rootURL: URL
  public let regularFileCount: Int
  public let totalBytes: UInt64
  public let artifactSHA256: String
  public let planSHA256: String
  public let planPolicyVersion: Int
  public let treeSealVersion: UInt8
  public let rootDevice: UInt64
  public let rootInode: UInt64
  public let entries: [StagingTreeSealEntry]
  public let treeSHA256: String
}

public enum SafeStagingExtractor {
  public static func extract(
    plan: SafeArchivePlan,
    expectedArtifactSHA256: String,
    toNewRoot stagingRootURL: URL,
    source: any ArchivePlannedContentSource
  ) throws -> ExtractedStagingTree {
    try Task.checkCancellation()
    guard plan.policyVersion == SafeArchivePlanner.currentPolicyVersion else {
      throw SafeStagingExtractionError.unsupportedPolicyVersion(plan.policyVersion)
    }
    let planSHA256 = plan.canonicalSHA256
    guard isSHA256(expectedArtifactSHA256),
      source.artifactSHA256 == expectedArtifactSHA256,
      source.entryCount == plan.entries.count
    else {
      if source.entryCount != plan.entries.count {
        throw SafeStagingExtractionError.sourceEntryCountMismatch(
          expected: plan.entries.count,
          actual: source.entryCount
        )
      }
      throw SafeStagingExtractionError.invalidArtifactIdentity
    }

    let location = try openParent(for: stagingRootURL)
    defer { _ = close(location.parentDescriptor) }
    var rootDescriptor: Int32 = -1
    var rootMetadata = stat()
    var createdRoot = false
    var capturedRootIdentity = false
    do {
      guard mkdirat(location.parentDescriptor, location.rootName, S_IRWXU) == 0 else {
        if errno == EEXIST { throw SafeStagingExtractionError.stagingRootAlreadyExists }
        throw currentPOSIXError()
      }
      createdRoot = true
      var pathMetadata = stat()
      guard
        fstatat(
          location.parentDescriptor,
          location.rootName,
          &pathMetadata,
          AT_SYMLINK_NOFOLLOW
        ) == 0
      else {
        throw currentPOSIXError()
      }
      rootDescriptor = openat(
        location.parentDescriptor,
        location.rootName,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
      )
      guard rootDescriptor >= 0 else { throw currentPOSIXError() }
      guard fstat(rootDescriptor, &rootMetadata) == 0,
        isPrivateDirectory(rootMetadata),
        rootMetadata.st_dev == pathMetadata.st_dev,
        rootMetadata.st_ino == pathMetadata.st_ino,
        entryMatches(
          parentDescriptor: location.parentDescriptor,
          name: location.rootName,
          metadata: rootMetadata,
          requireDirectory: true
        )
      else {
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      capturedRootIdentity = true
      guard fsync(location.parentDescriptor) == 0 else { throw currentPOSIXError() }

      var totalBytes: UInt64 = 0
      var regularFileCount = 0
      var createdFileIdentities: [String: CreatedFileIdentity] = [:]
      for planned in plan.entries {
        try Task.checkCancellation()
        let descriptor = try source.descriptor(
          forSourcePathSHA256: planned.sourcePathSHA256
        )
        try validateSourceDescriptor(descriptor, matches: planned)
        switch planned.kind {
        case .directory:
          try createDirectory(
            relativePath: planned.relativePath,
            rootDescriptor: rootDescriptor,
            rootDevice: rootMetadata.st_dev
          )
        case .regularFile:
          let reader = try source.reader(for: planned)
          let identity = try writeFile(
            entry: planned,
            reader: reader,
            rootDescriptor: rootDescriptor,
            rootDevice: rootMetadata.st_dev,
            totalBytes: &totalBytes,
            expectedTotalBytes: plan.totalRegularFileBytes
          )
          createdFileIdentities[planned.relativePath] = identity
          regularFileCount += 1
        default:
          throw SafeStagingExtractionError.sourceDescriptorMismatch
        }
      }
      try source.finish()
      try Task.checkCancellation()
      guard totalBytes == plan.totalRegularFileBytes else {
        throw SafeStagingExtractionError.totalSizeMismatch(
          expected: plan.totalRegularFileBytes,
          actual: totalBytes
        )
      }
      var actualInventory: [String: StagedEntryIdentity] = [:]
      try syncDirectoryTree(
        rootDescriptor,
        rootDevice: rootMetadata.st_dev,
        relativePrefix: "",
        expectedFiles: createdFileIdentities,
        inventory: &actualInventory
      )
      var finalRootMetadata = stat()
      guard actualInventory == expectedInventory(for: plan, files: createdFileIdentities),
        fstat(rootDescriptor, &finalRootMetadata) == 0,
        isPrivateDirectory(finalRootMetadata),
        finalRootMetadata.st_dev == rootMetadata.st_dev,
        finalRootMetadata.st_ino == rootMetadata.st_ino,
        fsync(rootDescriptor) == 0,
        fsync(location.parentDescriptor) == 0,
        entryMatches(
          parentDescriptor: location.parentDescriptor,
          name: location.rootName,
          metadata: rootMetadata,
          requireDirectory: true
        )
      else {
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      try Task.checkCancellation()
      let entrySeals = actualInventory.map { path, identity in
        StagingTreeSealEntry(
          relativePath: path,
          kind: identity.kind,
          size: identity.size,
          mode: identity.permissions,
          contentSHA256: identity.contentSHA256
        )
      }
      .sorted { utf8Less($0.relativePath, $1.relativePath) }
      let treeDigest = SafeStagingTreeSealer.canonicalSHA256(for: entrySeals)
      guard let rootDevice = UInt64(exactly: finalRootMetadata.st_dev),
        let rootInode = UInt64(exactly: finalRootMetadata.st_ino)
      else {
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      _ = close(rootDescriptor)
      rootDescriptor = -1
      return ExtractedStagingTree(
        rootURL: location.rootURL,
        regularFileCount: regularFileCount,
        totalBytes: totalBytes,
        artifactSHA256: expectedArtifactSHA256,
        planSHA256: planSHA256,
        planPolicyVersion: plan.policyVersion,
        treeSealVersion: SafeStagingTreeSealer.currentVersion,
        rootDevice: rootDevice,
        rootInode: rootInode,
        entries: entrySeals,
        treeSHA256: treeDigest
      )
    } catch {
      let extractionError = error
      if createdRoot {
        guard capturedRootIdentity else {
          if rootDescriptor >= 0 { _ = close(rootDescriptor) }
          throw SafeStagingExtractionAndCleanupError(
            extractionError: extractionError,
            cleanupError: SafeStagingExtractionError.cleanupFailed
          )
        }
        do {
          guard rootDescriptor >= 0 else { throw currentPOSIXError() }
          try removeTreeContents(rootDescriptor, rootDevice: rootMetadata.st_dev)
          guard
            entryMatches(
              parentDescriptor: location.parentDescriptor,
              name: location.rootName,
              metadata: rootMetadata,
              requireDirectory: true
            )
          else {
            throw SafeStagingExtractionError.cleanupFailed
          }
          _ = close(rootDescriptor)
          rootDescriptor = -1
          guard unlinkat(location.parentDescriptor, location.rootName, AT_REMOVEDIR) == 0,
            fsync(location.parentDescriptor) == 0
          else {
            throw currentPOSIXError()
          }
        } catch {
          if rootDescriptor >= 0 { _ = close(rootDescriptor) }
          throw SafeStagingExtractionAndCleanupError(
            extractionError: extractionError,
            cleanupError: error
          )
        }
      } else if rootDescriptor >= 0 {
        _ = close(rootDescriptor)
      }
      throw extractionError
    }
  }

  public static func reverify(_ candidate: ExtractedStagingTree) throws {
    try Task.checkCancellation()
    let expected = try validatedEntries(for: candidate)
    let location = try openParent(for: candidate.rootURL)
    defer { _ = close(location.parentDescriptor) }
    let rootDescriptor = openat(
      location.parentDescriptor,
      location.rootName,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard rootDescriptor >= 0 else { throw currentPOSIXError() }
    defer { _ = close(rootDescriptor) }

    var rootMetadata = stat()
    guard fstat(rootDescriptor, &rootMetadata) == 0,
      isPrivateDirectory(rootMetadata),
      UInt64(exactly: rootMetadata.st_dev) == candidate.rootDevice,
      UInt64(exactly: rootMetadata.st_ino) == candidate.rootInode,
      entryMatches(
        parentDescriptor: location.parentDescriptor,
        name: location.rootName,
        metadata: rootMetadata,
        requireDirectory: true
      )
    else {
      throw SafeStagingExtractionError.unsafeFilesystemEntry
    }

    var seen = Set<String>()
    try reverifyDirectoryTree(
      rootDescriptor,
      rootDevice: rootMetadata.st_dev,
      relativePrefix: "",
      expected: expected,
      seen: &seen
    )
    var completedRoot = stat()
    guard seen.count == expected.count,
      fstat(rootDescriptor, &completedRoot) == 0,
      isPrivateDirectory(completedRoot),
      completedRoot.st_dev == rootMetadata.st_dev,
      completedRoot.st_ino == rootMetadata.st_ino,
      entryMatches(
        parentDescriptor: location.parentDescriptor,
        name: location.rootName,
        metadata: rootMetadata,
        requireDirectory: true
      )
    else {
      throw SafeStagingExtractionError.unsafeFilesystemEntry
    }
  }

  private struct StagingLocation {
    let parentDescriptor: Int32
    let rootName: String
    let rootURL: URL
  }

  private struct StagedEntryIdentity: Equatable {
    let kind: ArchiveEntryKind
    let size: UInt64
    let permissions: UInt16
    let contentSHA256: String?
  }

  private struct CreatedFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: UInt64
    let permissions: UInt16
    let contentSHA256: String
  }

  private static func openParent(for rootURL: URL) throws -> StagingLocation {
    guard rootURL.isFileURL, rootURL.host == nil || rootURL.host?.isEmpty == true,
      let pathComponents = absolutePathComponents(rootURL.path),
      let rootName = pathComponents.last
    else {
      throw SafeStagingExtractionError.invalidStagingRoot
    }
    guard !rootName.isEmpty, rootName != ".", rootName != "..",
      rootName.utf8.count <= 128,
      rootName.utf8.allSatisfy({ byte in
        (48...57).contains(byte)
          || (65...90).contains(byte)
          || (97...122).contains(byte)
          || byte == 45 || byte == 46 || byte == 95
      })
    else {
      throw SafeStagingExtractionError.invalidStagingRoot
    }
    let parentPath = "/" + pathComponents.dropLast().joined(separator: "/")
    let parentURL = URL(fileURLWithPath: parentPath, isDirectory: true)
    let descriptor = try openDirectoryWithoutSymlinkAncestors(parentURL)
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, isPrivateDirectory(metadata) else {
      _ = close(descriptor)
      throw SafeStagingExtractionError.unsafeParentDirectory
    }
    return StagingLocation(
      parentDescriptor: descriptor,
      rootName: rootName,
      rootURL: rootURL
    )
  }

  private static func openDirectoryWithoutSymlinkAncestors(_ url: URL) throws -> Int32 {
    guard url.isFileURL, let components = absolutePathComponents(url.path) else {
      throw SafeStagingExtractionError.unsafeParentDirectory
    }
    var current = open(
      "/",
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard current >= 0 else { throw currentPOSIXError() }
    do {
      for component in components {
        var pathMetadata = stat()
        guard fstatat(current, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
          throw currentPOSIXError()
        }
        guard pathMetadata.st_mode & S_IFMT == S_IFDIR else {
          throw SafeStagingExtractionError.unsafeParentDirectory
        }
        let next = openat(
          current,
          component,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard next >= 0 else {
          if errno == ELOOP || errno == ENOTDIR {
            throw SafeStagingExtractionError.unsafeParentDirectory
          }
          throw currentPOSIXError()
        }
        var opened = stat()
        guard fstat(next, &opened) == 0,
          opened.st_mode & S_IFMT == S_IFDIR,
          opened.st_dev == pathMetadata.st_dev,
          opened.st_ino == pathMetadata.st_ino
        else {
          _ = close(next)
          throw SafeStagingExtractionError.unsafeParentDirectory
        }
        _ = close(current)
        current = next
      }
      return current
    } catch {
      _ = close(current)
      throw error
    }
  }

  private static func absolutePathComponents(_ path: String) -> [String]? {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
    if path == "/" { return [] }
    let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false)
    guard rawComponents.first?.isEmpty == true else { return nil }
    let components = rawComponents.dropFirst()
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      return nil
    }
    return components.map(String.init)
  }

  private static func validateSourceDescriptor(
    _ descriptor: ArchiveEntryDescriptor,
    matches planned: PlannedArchiveEntry
  ) throws {
    let expectedMode: UInt16 =
      descriptor.kind == .directory
      ? 0o700
      : (descriptor.permissions & 0o111 == 0 ? 0o600 : 0o700)
    guard sha256(descriptor.path) == planned.sourcePathSHA256,
      descriptor.kind == planned.kind,
      descriptor.declaredSize == planned.declaredSize,
      descriptor.permissions == planned.sourcePermissions,
      descriptor.linkTarget == nil,
      expectedMode == planned.normalizedPermissions
    else {
      throw SafeStagingExtractionError.sourceDescriptorMismatch
    }
  }

  private static func createDirectory(
    relativePath: String,
    rootDescriptor: Int32,
    rootDevice: dev_t
  ) throws {
    let components = try components(of: relativePath)
    let directory = try openOrCreateDirectoryPath(
      components,
      rootDescriptor: rootDescriptor,
      rootDevice: rootDevice
    )
    defer { _ = close(directory) }
    guard fsync(directory) == 0 else { throw currentPOSIXError() }
  }

  private static func writeFile(
    entry: PlannedArchiveEntry,
    reader: any ArchiveEntryContentReading,
    rootDescriptor: Int32,
    rootDevice: dev_t,
    totalBytes: inout UInt64,
    expectedTotalBytes: UInt64
  ) throws -> CreatedFileIdentity {
    let pathComponents = try components(of: entry.relativePath)
    let parentComponents = Array(pathComponents.dropLast())
    let parentDescriptor = try openOrCreateDirectoryPath(
      parentComponents,
      rootDescriptor: rootDescriptor,
      rootDevice: rootDevice
    )
    defer { _ = close(parentDescriptor) }
    guard let fileName = pathComponents.last else {
      throw SafeStagingExtractionError.invalidStagingRoot
    }
    var fileDescriptor = openat(
      parentDescriptor,
      fileName,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard fileDescriptor >= 0 else {
      if errno == EEXIST { throw SafeStagingExtractionError.filesystemEntryConflict }
      throw currentPOSIXError()
    }
    defer { if fileDescriptor >= 0 { _ = close(fileDescriptor) } }
    var fileMetadata = stat()
    guard fstat(fileDescriptor, &fileMetadata) == 0,
      isPrivateRegularFile(fileMetadata, rootDevice: rootDevice)
    else {
      throw SafeStagingExtractionError.unsafeFilesystemEntry
    }

    var entryBytes: UInt64 = 0
    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    var contentHasher = SHA256()
    while true {
      try Task.checkCancellation()
      let readCount = try buffer.withUnsafeMutableBytes { try reader.read(into: $0) }
      guard readCount >= 0, readCount <= buffer.count else {
        throw SafeStagingExtractionError.invalidReaderCount(readCount)
      }
      if readCount == 0 { break }
      let chunkBytes = UInt64(readCount)
      guard entryBytes <= entry.declaredSize,
        chunkBytes <= entry.declaredSize - entryBytes
      else {
        throw SafeStagingExtractionError.entrySizeExceeded(expected: entry.declaredSize)
      }
      let (newTotal, overflow) = totalBytes.addingReportingOverflow(chunkBytes)
      guard !overflow, newTotal <= expectedTotalBytes else {
        throw SafeStagingExtractionError.totalSizeExceeded(expected: expectedTotalBytes)
      }
      buffer.withUnsafeBytes {
        contentHasher.update(
          bufferPointer: UnsafeRawBufferPointer(start: $0.baseAddress, count: readCount)
        )
      }
      try writeAll(buffer, count: readCount, descriptor: fileDescriptor)
      entryBytes += chunkBytes
      totalBytes = newTotal
    }
    guard entryBytes == entry.declaredSize else {
      throw SafeStagingExtractionError.entrySizeMismatch(
        expected: entry.declaredSize,
        actual: entryBytes
      )
    }
    guard fchmod(fileDescriptor, mode_t(entry.normalizedPermissions)) == 0,
      fsync(fileDescriptor) == 0
    else {
      throw currentPOSIXError()
    }
    var completedMetadata = stat()
    var pathMetadata = stat()
    guard fstat(fileDescriptor, &completedMetadata) == 0,
      fstatat(parentDescriptor, fileName, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      completedMetadata.st_dev == fileMetadata.st_dev,
      completedMetadata.st_ino == fileMetadata.st_ino,
      completedMetadata.st_dev == pathMetadata.st_dev,
      completedMetadata.st_ino == pathMetadata.st_ino,
      completedMetadata.st_mode & S_IFMT == S_IFREG,
      completedMetadata.st_uid == geteuid(),
      completedMetadata.st_nlink == 1,
      completedMetadata.st_mode & 0o777 == mode_t(entry.normalizedPermissions),
      completedMetadata.st_size >= 0,
      UInt64(completedMetadata.st_size) == entry.declaredSize
    else {
      throw SafeStagingExtractionError.unsafeFilesystemEntry
    }
    let completedDescriptor = fileDescriptor
    fileDescriptor = -1
    guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
    guard fsync(parentDescriptor) == 0 else { throw currentPOSIXError() }
    return CreatedFileIdentity(
      device: completedMetadata.st_dev,
      inode: completedMetadata.st_ino,
      size: entry.declaredSize,
      permissions: entry.normalizedPermissions,
      contentSHA256: hexDigest(contentHasher.finalize())
    )
  }

  private static func openOrCreateDirectoryPath(
    _ components: [String],
    rootDescriptor: Int32,
    rootDevice: dev_t
  ) throws -> Int32 {
    var current = dup(rootDescriptor)
    guard current >= 0 else { throw currentPOSIXError() }
    do {
      for component in components {
        try Task.checkCancellation()
        var created = false
        if mkdirat(current, component, S_IRWXU) == 0 {
          created = true
        } else if errno != EEXIST {
          throw currentPOSIXError()
        }
        var pathMetadata = stat()
        guard fstatat(current, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
          throw currentPOSIXError()
        }
        let next = openat(
          current,
          component,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard next >= 0 else {
          if errno == ELOOP || errno == ENOTDIR {
            throw SafeStagingExtractionError.unsafeFilesystemEntry
          }
          throw currentPOSIXError()
        }
        var metadata = stat()
        guard fstat(next, &metadata) == 0,
          isPrivateDirectory(metadata),
          metadata.st_dev == rootDevice,
          metadata.st_dev == pathMetadata.st_dev,
          metadata.st_ino == pathMetadata.st_ino
        else {
          _ = close(next)
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        if created, fsync(current) != 0 {
          _ = close(next)
          throw currentPOSIXError()
        }
        _ = close(current)
        current = next
      }
      return current
    } catch {
      _ = close(current)
      throw error
    }
  }

  private static func validatedEntries(
    for candidate: ExtractedStagingTree
  ) throws -> [String: StagingTreeSealEntry] {
    guard isSHA256(candidate.artifactSHA256),
      isSHA256(candidate.planSHA256),
      isSHA256(candidate.treeSHA256),
      candidate.planPolicyVersion == SafeArchivePlanner.currentPolicyVersion,
      candidate.treeSealVersion == SafeStagingTreeSealer.currentVersion,
      candidate.regularFileCount >= 0
    else {
      throw SafeStagingExtractionError.unsafeFilesystemEntry
    }

    var expected: [String: StagingTreeSealEntry] = [:]
    var previousPath: String?
    var regularFileCount = 0
    var totalBytes: UInt64 = 0
    for entry in candidate.entries {
      try Task.checkCancellation()
      guard entry.relativePath == entry.relativePath.precomposedStringWithCanonicalMapping,
        (try? components(of: entry.relativePath)) != nil,
        previousPath.map({ utf8Less($0, entry.relativePath) }) != false,
        expected[entry.relativePath] == nil
      else {
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      switch entry.kind {
      case .directory:
        guard entry.size == 0, entry.mode == 0o700, entry.contentSHA256 == nil else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
      case .regularFile:
        guard entry.mode == 0o600 || entry.mode == 0o700,
          let contentSHA256 = entry.contentSHA256,
          isSHA256(contentSHA256)
        else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        let (newTotal, overflow) = totalBytes.addingReportingOverflow(entry.size)
        guard !overflow else { throw SafeStagingExtractionError.unsafeFilesystemEntry }
        totalBytes = newTotal
        regularFileCount += 1
      default:
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      expected[entry.relativePath] = entry
      previousPath = entry.relativePath
    }

    for entry in candidate.entries {
      let pathComponents = entry.relativePath.split(separator: "/").map(String.init)
      guard pathComponents.count > 1 else { continue }
      for end in 1..<pathComponents.count {
        let ancestor = pathComponents[..<end].joined(separator: "/")
        guard expected[ancestor]?.kind == .directory else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
      }
    }
    guard regularFileCount == candidate.regularFileCount,
      totalBytes == candidate.totalBytes,
      SafeStagingTreeSealer.canonicalSHA256(for: candidate.entries) == candidate.treeSHA256
    else {
      throw SafeStagingExtractionError.unsafeFilesystemEntry
    }
    return expected
  }

  private static func reverifyDirectoryTree(
    _ descriptor: Int32,
    rootDevice: dev_t,
    relativePrefix: String,
    expected: [String: StagingTreeSealEntry],
    seen: inout Set<String>
  ) throws {
    for name in try directoryEntries(descriptor) {
      try Task.checkCancellation()
      let observedPath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
      let relativePath = observedPath.precomposedStringWithCanonicalMapping
      guard let expectedEntry = expected[relativePath], seen.insert(relativePath).inserted else {
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      var pathMetadata = stat()
      guard fstatat(descriptor, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw currentPOSIXError()
      }

      switch expectedEntry.kind {
      case .directory:
        guard pathMetadata.st_mode & S_IFMT == S_IFDIR,
          pathMetadata.st_dev == rootDevice,
          isPrivateDirectory(pathMetadata)
        else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        var child = openat(
          descriptor,
          name,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard child >= 0 else { throw currentPOSIXError() }
        do {
          var opened = stat()
          guard fstat(child, &opened) == 0,
            isPrivateDirectory(opened),
            opened.st_dev == pathMetadata.st_dev,
            opened.st_ino == pathMetadata.st_ino
          else {
            throw SafeStagingExtractionError.unsafeFilesystemEntry
          }
          try reverifyDirectoryTree(
            child,
            rootDevice: rootDevice,
            relativePrefix: relativePath,
            expected: expected,
            seen: &seen
          )
          var completed = stat()
          var currentPath = stat()
          guard fstat(child, &completed) == 0,
            fstatat(descriptor, name, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
            isPrivateDirectory(completed),
            isPrivateDirectory(currentPath),
            completed.st_dev == opened.st_dev,
            completed.st_ino == opened.st_ino,
            currentPath.st_dev == opened.st_dev,
            currentPath.st_ino == opened.st_ino
          else {
            throw SafeStagingExtractionError.unsafeFilesystemEntry
          }
          let completedDescriptor = child
          child = -1
          guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
        } catch {
          if child >= 0 { _ = close(child) }
          throw error
        }
      case .regularFile:
        guard isPrivateRegularFile(pathMetadata, rootDevice: rootDevice),
          pathMetadata.st_size >= 0,
          UInt64(pathMetadata.st_size) == expectedEntry.size,
          UInt16(pathMetadata.st_mode & 0o777) == expectedEntry.mode
        else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        var file = openat(
          descriptor,
          name,
          O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard file >= 0 else { throw currentPOSIXError() }
        do {
          var opened = stat()
          guard fstat(file, &opened) == 0,
            isPrivateRegularFile(opened, rootDevice: rootDevice),
            opened.st_dev == pathMetadata.st_dev,
            opened.st_ino == pathMetadata.st_ino,
            opened.st_size == pathMetadata.st_size,
            UInt16(opened.st_mode & 0o777) == expectedEntry.mode,
            try hashFile(file, expectedSize: expectedEntry.size) == expectedEntry.contentSHA256
          else {
            throw SafeStagingExtractionError.unsafeFilesystemEntry
          }
          var completed = stat()
          var currentPath = stat()
          guard fstat(file, &completed) == 0,
            fstatat(descriptor, name, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
            isPrivateRegularFile(completed, rootDevice: rootDevice),
            isPrivateRegularFile(currentPath, rootDevice: rootDevice),
            completed.st_dev == opened.st_dev,
            completed.st_ino == opened.st_ino,
            completed.st_size == opened.st_size,
            UInt16(completed.st_mode & 0o777) == expectedEntry.mode,
            currentPath.st_dev == opened.st_dev,
            currentPath.st_ino == opened.st_ino,
            currentPath.st_size == opened.st_size,
            UInt16(currentPath.st_mode & 0o777) == expectedEntry.mode
          else {
            throw SafeStagingExtractionError.unsafeFilesystemEntry
          }
          let completedDescriptor = file
          file = -1
          guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
        } catch {
          if file >= 0 { _ = close(file) }
          throw error
        }
      default:
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
    }
  }

  private static func syncDirectoryTree(
    _ descriptor: Int32,
    rootDevice: dev_t,
    relativePrefix: String,
    expectedFiles: [String: CreatedFileIdentity],
    inventory: inout [String: StagedEntryIdentity]
  ) throws {
    let entries = try directoryEntries(descriptor)
    for name in entries {
      let observedPath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
      let relativePath = observedPath.precomposedStringWithCanonicalMapping
      guard inventory[relativePath] == nil else {
        throw SafeStagingExtractionError.unsafeFilesystemEntry
      }
      var metadata = stat()
      guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw currentPOSIXError()
      }
      if metadata.st_mode & S_IFMT == S_IFDIR {
        guard metadata.st_dev == rootDevice else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        let child = openat(
          descriptor,
          name,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard child >= 0 else { throw currentPOSIXError() }
        var opened = stat()
        guard fstat(child, &opened) == 0,
          opened.st_dev == metadata.st_dev,
          opened.st_ino == metadata.st_ino,
          isPrivateDirectory(opened)
        else {
          _ = close(child)
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        inventory[relativePath] = StagedEntryIdentity(
          kind: .directory,
          size: 0,
          permissions: UInt16(opened.st_mode & 0o777),
          contentSHA256: nil
        )
        do {
          try syncDirectoryTree(
            child,
            rootDevice: rootDevice,
            relativePrefix: relativePath,
            expectedFiles: expectedFiles,
            inventory: &inventory
          )
          guard fsync(child) == 0 else { throw currentPOSIXError() }
          _ = close(child)
        } catch {
          _ = close(child)
          throw error
        }
      } else {
        guard let expectedIdentity = expectedFiles[relativePath],
          isPrivateRegularFile(metadata, rootDevice: rootDevice), metadata.st_size >= 0
        else {
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        let file = openat(
          descriptor,
          name,
          O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard file >= 0 else { throw currentPOSIXError() }
        var opened = stat()
        guard fstat(file, &opened) == 0,
          isPrivateRegularFile(opened, rootDevice: rootDevice),
          opened.st_dev == metadata.st_dev,
          opened.st_ino == metadata.st_ino,
          opened.st_dev == expectedIdentity.device,
          opened.st_ino == expectedIdentity.inode,
          opened.st_size >= 0,
          UInt64(opened.st_size) == expectedIdentity.size,
          UInt16(opened.st_mode & 0o777) == expectedIdentity.permissions
        else {
          _ = close(file)
          throw SafeStagingExtractionError.unsafeFilesystemEntry
        }
        let contentSHA256: String
        do {
          contentSHA256 = try hashFile(file, expectedSize: expectedIdentity.size)
        } catch {
          _ = close(file)
          throw error
        }
        var completed = stat()
        var currentPath = stat()
        guard contentSHA256 == expectedIdentity.contentSHA256,
          fstat(file, &completed) == 0,
          fstatat(descriptor, name, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
          isPrivateRegularFile(completed, rootDevice: rootDevice),
          isPrivateRegularFile(currentPath, rootDevice: rootDevice),
          completed.st_dev == opened.st_dev,
          completed.st_ino == opened.st_ino,
          completed.st_size >= 0,
          UInt64(completed.st_size) == expectedIdentity.size,
          UInt16(completed.st_mode & 0o777) == expectedIdentity.permissions,
          currentPath.st_dev == opened.st_dev,
          currentPath.st_ino == opened.st_ino,
          currentPath.st_mode & S_IFMT == S_IFREG,
          currentPath.st_size == completed.st_size,
          UInt16(currentPath.st_mode & 0o777) == expectedIdentity.permissions
        else {
          _ = close(file)
          throw SafeStagingExtractionError.fileContentChanged
        }
        guard close(file) == 0 else { throw currentPOSIXError() }
        inventory[relativePath] = StagedEntryIdentity(
          kind: .regularFile,
          size: UInt64(completed.st_size),
          permissions: UInt16(completed.st_mode & 0o777),
          contentSHA256: contentSHA256
        )
      }
    }
    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  private static func expectedInventory(
    for plan: SafeArchivePlan,
    files: [String: CreatedFileIdentity]
  ) -> [String: StagedEntryIdentity] {
    var inventory: [String: StagedEntryIdentity] = [:]
    for entry in plan.entries {
      let components = entry.relativePath.split(separator: "/").map(String.init)
      if components.count > 1 {
        for end in 1..<components.count {
          let implicitDirectory = components[..<end].joined(separator: "/")
          inventory[implicitDirectory] = StagedEntryIdentity(
            kind: .directory,
            size: 0,
            permissions: 0o700,
            contentSHA256: nil
          )
        }
      }
      inventory[entry.relativePath] = StagedEntryIdentity(
        kind: entry.kind,
        size: entry.declaredSize,
        permissions: entry.normalizedPermissions,
        contentSHA256: files[entry.relativePath]?.contentSHA256
      )
    }
    return inventory
  }

  private static func removeTreeContents(_ descriptor: Int32, rootDevice: dev_t) throws {
    for name in try directoryEntries(descriptor) {
      var metadata = stat()
      guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw currentPOSIXError()
      }
      let type = metadata.st_mode & S_IFMT
      if type == S_IFDIR {
        guard metadata.st_dev == rootDevice else {
          throw SafeStagingExtractionError.cleanupFailed
        }
        let child = openat(
          descriptor,
          name,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard child >= 0 else { throw currentPOSIXError() }
        var opened = stat()
        guard fstat(child, &opened) == 0,
          opened.st_dev == metadata.st_dev,
          opened.st_ino == metadata.st_ino
        else {
          _ = close(child)
          throw SafeStagingExtractionError.cleanupFailed
        }
        do {
          try removeTreeContents(child, rootDevice: rootDevice)
          _ = close(child)
        } catch {
          _ = close(child)
          throw error
        }
        guard unlinkat(descriptor, name, AT_REMOVEDIR) == 0 else {
          throw currentPOSIXError()
        }
      } else if type == S_IFLNK {
        guard unlinkat(descriptor, name, 0) == 0 else { throw currentPOSIXError() }
      } else if type == S_IFREG {
        guard metadata.st_dev == rootDevice, metadata.st_nlink == 1,
          unlinkat(descriptor, name, 0) == 0
        else {
          throw SafeStagingExtractionError.cleanupFailed
        }
      } else {
        throw SafeStagingExtractionError.cleanupFailed
      }
    }
    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  private static func directoryEntries(_ descriptor: Int32) throws -> [String] {
    let independent = openat(
      descriptor,
      ".",
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard independent >= 0 else { throw currentPOSIXError() }
    guard let directory = fdopendir(independent) else {
      let error = currentPOSIXError()
      _ = close(independent)
      throw error
    }
    defer { _ = closedir(directory) }
    var names: [String] = []
    while true {
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 { throw currentPOSIXError() }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(validatingCString: $0)
        }
      }
      guard let name else { throw SafeStagingExtractionError.cleanupFailed }
      if name != "." && name != ".." { names.append(name) }
    }
    return names.sorted()
  }

  private static func components(of path: String) throws -> [String] {
    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !components.isEmpty,
      components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else {
      throw SafeStagingExtractionError.sourceDescriptorMismatch
    }
    return components
  }

  private static func entryMatches(
    parentDescriptor: Int32,
    name: String,
    metadata: stat,
    requireDirectory: Bool
  ) -> Bool {
    var current = stat()
    return fstatat(parentDescriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0
      && current.st_dev == metadata.st_dev
      && current.st_ino == metadata.st_ino
      && (!requireDirectory || current.st_mode & S_IFMT == S_IFDIR)
  }

  private static func isPrivateDirectory(_ metadata: stat) -> Bool {
    metadata.st_mode & S_IFMT == S_IFDIR
      && metadata.st_uid == geteuid()
      && metadata.st_mode & 0o777 == 0o700
  }

  private static func isPrivateRegularFile(_ metadata: stat, rootDevice: dev_t) -> Bool {
    metadata.st_mode & S_IFMT == S_IFREG
      && metadata.st_uid == geteuid()
      && metadata.st_dev == rootDevice
      && metadata.st_nlink == 1
      && (metadata.st_mode & 0o777 == 0o600 || metadata.st_mode & 0o777 == 0o700)
  }

  private static func writeAll(_ buffer: [UInt8], count: Int, descriptor: Int32) throws {
    var written = 0
    while written < count {
      try Task.checkCancellation()
      let result = buffer.withUnsafeBytes {
        write(descriptor, $0.baseAddress?.advanced(by: written), count - written)
      }
      if result < 0 {
        if errno == EINTR { continue }
        throw currentPOSIXError()
      }
      guard result > 0 else { throw POSIXError(.EIO) }
      written += result
    }
  }

  private static func hashFile(_ descriptor: Int32, expectedSize: UInt64) throws -> String {
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    var totalBytes: UInt64 = 0
    while true {
      try Task.checkCancellation()
      let count = buffer.withUnsafeMutableBytes {
        read(descriptor, $0.baseAddress, $0.count)
      }
      if count == 0 {
        guard totalBytes == expectedSize else {
          throw SafeStagingExtractionError.fileContentChanged
        }
        return hexDigest(hasher.finalize())
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw currentPOSIXError()
      }
      let (newTotal, overflow) = totalBytes.addingReportingOverflow(UInt64(count))
      guard !overflow, newTotal <= expectedSize else {
        throw SafeStagingExtractionError.fileContentChanged
      }
      buffer.withUnsafeBytes {
        hasher.update(
          bufferPointer: UnsafeRawBufferPointer(start: $0.baseAddress, count: count)
        )
      }
      totalBytes = newTotal
    }
  }

  private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
  }

  private static func hexDigest(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
