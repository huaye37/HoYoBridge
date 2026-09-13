import CryptoKit
import Darwin
import Foundation

enum ManifestReplayFixtureFileLoadingError: Error, Equatable, Sendable {
  case invalidRoot
  case fixtureUnavailable
  case unsafeEntry
  case invalidInventory
  case descriptorMismatch
  case invalidDescriptor
  case artifactMismatch
  case oversized
  case ioFailure
}

extension ManifestReplayFixtureFileLoadingError: ManifestReplayRedactedValue {}

struct ManifestReplayFixtureFileLoaderHooks: Sendable {
  static let none = ManifestReplayFixtureFileLoaderHooks()

  let afterDescriptorRead: @Sendable () throws -> Void
  let afterArtifactPreflight: @Sendable () throws -> Void
  let afterArtifactRead: @Sendable (ManifestEvidenceArtifactKind) throws -> Void
  let beforeFinalVerification: @Sendable () throws -> Void

  init(
    afterDescriptorRead: @escaping @Sendable () throws -> Void = {},
    afterArtifactPreflight: @escaping @Sendable () throws -> Void = {},
    afterArtifactRead: @escaping @Sendable (ManifestEvidenceArtifactKind) throws -> Void = { _ in },
    beforeFinalVerification: @escaping @Sendable () throws -> Void = {}
  ) {
    self.afterDescriptorRead = afterDescriptorRead
    self.afterArtifactPreflight = afterArtifactPreflight
    self.afterArtifactRead = afterArtifactRead
    self.beforeFinalVerification = beforeFinalVerification
  }
}

extension ManifestReplayFixtureFileLoaderHooks: ManifestReplayRedactedValue {}

struct ManifestReplayFixtureFileLoader: Sendable {
  private static let descriptorName = "fixture.json"
  private static let maximumInventoryCount = 6
  private static let maximumRootComponents = 64
  private static let readChunkBytes = 64 * 1_024
  private static let filenames: [ManifestEvidenceArtifactKind: String] = [
    .branchResponse: "branch-response.redacted.json",
    .buildResponse: "build-response.redacted.json",
    .patchResponse: "patch-response.redacted.json",
    .chunkManifest: "chunk-manifest.pb.zst",
    .diffManifest: "ldiff-manifest.pb.zst",
  ]

  private let rootURL: URL
  private let hooks: ManifestReplayFixtureFileLoaderHooks

  init(
    rootURL: URL,
    hooks: ManifestReplayFixtureFileLoaderHooks = .none
  ) {
    self.rootURL = rootURL
    self.hooks = hooks
  }

  func load(
    id: ManifestFixtureID,
    expectedDescriptorSHA256: ManifestSHA256
  ) throws -> ValidatedReplayArtifactBundle {
    try Task.checkCancellation()
    var rootDescriptor: Int32 = -1
    var fixtureDescriptor: Int32 = -1
    defer {
      if fixtureDescriptor >= 0 { _ = close(fixtureDescriptor) }
      if rootDescriptor >= 0 { _ = close(rootDescriptor) }
    }
    do {
      let root = try Self.openRoot(rootURL)
      rootDescriptor = root.descriptor
      let fixture = try Self.openFixture(
        named: id.value,
        parent: rootDescriptor,
        rootDevice: root.metadata.st_dev
      )
      fixtureDescriptor = fixture.descriptor

      let descriptorRead = try Self.readDescriptor(
        parent: fixtureDescriptor,
        expectedSHA256: expectedDescriptorSHA256,
        rootDevice: root.metadata.st_dev,
        hook: hooks.afterDescriptorRead
      )
      let descriptor = try Self.decodeDescriptor(descriptorRead.data)
      guard descriptor.fixtureID == id,
        descriptor.fixtureDescriptorSHA256 == expectedDescriptorSHA256.lowercaseHex,
        descriptor.fixtureDescriptorByteSize == descriptorRead.byteSize
      else {
        throw ManifestReplayFixtureFileLoadingError.descriptorMismatch
      }

      let expectedNames = try Self.expectedInventory(descriptor)
      try Self.requireExactInventory(fixtureDescriptor, expected: expectedNames)
      let openedArtifacts = try Self.preflightArtifacts(
        descriptor: descriptor,
        parent: fixtureDescriptor,
        rootDevice: root.metadata.st_dev,
        descriptorByteSize: descriptorRead.byteSize
      )
      var files = openedArtifacts.files
      defer { Self.closeAllIgnoringErrors(&files) }
      try Self.run(hooks.afterArtifactPreflight)

      var artifacts: [ManifestReplayArtifactData] = []
      artifacts.reserveCapacity(files.count)
      for index in files.indices {
        try Task.checkCancellation()
        let read = try Self.readArtifact(
          &files[index],
          parent: fixtureDescriptor,
          hook: hooks.afterArtifactRead
        )
        guard let kind = files[index].kind else {
          throw ManifestReplayFixtureFileLoadingError.invalidDescriptor
        }
        artifacts.append(
          ManifestReplayArtifactData(kind: kind, data: read))
      }
      let bundle = try Self.validateBundle(descriptor: descriptor, artifacts: artifacts)
      guard bundle.totalByteSize == openedArtifacts.totalByteSize else {
        throw ManifestReplayFixtureFileLoadingError.artifactMismatch
      }

      try Self.run(hooks.beforeFinalVerification)
      try Task.checkCancellation()
      try Self.requireExactInventory(fixtureDescriptor, expected: expectedNames)
      try Self.requireDirectoryStillAnchored(
        fixtureDescriptor,
        metadata: fixture.metadata,
        name: id.value,
        parent: rootDescriptor
      )
      try Self.requireRootStillAnchored(
        rootURL,
        descriptor: rootDescriptor,
        metadata: root.metadata
      )
      try Task.checkCancellation()

      let completedFixture = fixtureDescriptor
      fixtureDescriptor = -1
      guard close(completedFixture) == 0 else {
        throw ManifestReplayFixtureFileLoadingError.ioFailure
      }
      let completedRoot = rootDescriptor
      rootDescriptor = -1
      guard close(completedRoot) == 0 else {
        throw ManifestReplayFixtureFileLoadingError.ioFailure
      }
      return bundle
    } catch let error as CancellationError {
      throw error
    } catch let error as ManifestReplayFixtureFileLoadingError {
      throw error
    } catch {
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
  }

  private static func openRoot(_ url: URL) throws -> OpenedDirectory {
    guard url.isFileURL, url.host == nil || url.host?.isEmpty == true,
      let components = absolutePathComponents(url.path), !components.isEmpty,
      components.count <= maximumRootComponents
    else {
      throw ManifestReplayFixtureFileLoadingError.invalidRoot
    }
    var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard current >= 0 else { throw ManifestReplayFixtureFileLoadingError.ioFailure }
    do {
      for component in components {
        var pathMetadata = stat()
        guard fstatat(current, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
          pathMetadata.st_mode & S_IFMT == S_IFDIR
        else {
          throw ManifestReplayFixtureFileLoadingError.invalidRoot
        }
        let next = openat(
          current,
          component,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard next >= 0 else { throw ManifestReplayFixtureFileLoadingError.invalidRoot }
        var opened = stat()
        guard fstat(next, &opened) == 0,
          isDirectory(opened), sameFile(opened, pathMetadata)
        else {
          _ = close(next)
          throw ManifestReplayFixtureFileLoadingError.invalidRoot
        }
        let previous = current
        current = next
        guard close(previous) == 0 else {
          throw ManifestReplayFixtureFileLoadingError.ioFailure
        }
      }
      var rootMetadata = stat()
      guard fstat(current, &rootMetadata) == 0,
        isAllowedDirectory(rootMetadata)
      else {
        throw ManifestReplayFixtureFileLoadingError.invalidRoot
      }
      return OpenedDirectory(descriptor: current, metadata: rootMetadata)
    } catch {
      _ = close(current)
      throw error
    }
  }

  private static func openFixture(
    named name: String,
    parent: Int32,
    rootDevice: dev_t
  ) throws -> OpenedDirectory {
    var pathMetadata = stat()
    guard fstatat(parent, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { throw ManifestReplayFixtureFileLoadingError.fixtureUnavailable }
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
    guard isAllowedDirectory(pathMetadata), pathMetadata.st_dev == rootDevice else {
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
    let descriptor = openat(
      parent,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
    var opened = stat()
    guard fstat(descriptor, &opened) == 0,
      isAllowedDirectory(opened), opened.st_dev == rootDevice,
      sameFile(opened, pathMetadata),
      sameStableMetadata(opened, pathMetadata)
    else {
      _ = close(descriptor)
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
    return OpenedDirectory(descriptor: descriptor, metadata: opened)
  }

  private static func readDescriptor(
    parent: Int32,
    expectedSHA256: ManifestSHA256,
    rootDevice: dev_t,
    hook: @Sendable () throws -> Void
  ) throws -> ReadFile {
    var file = try openFile(
      parent: parent,
      name: descriptorName,
      expectedSize: nil,
      maximumSize: UInt64(ManifestReplayDescriptorDecoder.maximumBytes),
      kind: nil,
      expectedSHA256: expectedSHA256.lowercaseHex,
      rootDevice: rootDevice
    )
    defer { if file.descriptor >= 0 { _ = close(file.descriptor) } }
    let read = try preadFile(&file, parent: parent) {
      try run(hook)
    }
    guard read.sha256 == expectedSHA256.lowercaseHex else {
      throw ManifestReplayFixtureFileLoadingError.descriptorMismatch
    }
    return read
  }

  private static func decodeDescriptor(_ data: Data) throws -> ValidatedReplayDescriptor {
    do {
      return try ManifestReplayDescriptorDecoder.decode(data)
    } catch ManifestReplayDescriptorDecodingError.oversized {
      throw ManifestReplayFixtureFileLoadingError.oversized
    } catch {
      throw ManifestReplayFixtureFileLoadingError.invalidDescriptor
    }
  }

  private static func expectedInventory(
    _ descriptor: ValidatedReplayDescriptor
  ) throws -> Set<String> {
    var result: Set<String> = [descriptorName]
    for binding in descriptor.externalArtifactBindings {
      guard let name = filenames[binding.kind], result.insert(name).inserted else {
        throw ManifestReplayFixtureFileLoadingError.invalidDescriptor
      }
    }
    guard result.count <= maximumInventoryCount else {
      throw ManifestReplayFixtureFileLoadingError.invalidInventory
    }
    return result
  }

  private static func preflightArtifacts(
    descriptor: ValidatedReplayDescriptor,
    parent: Int32,
    rootDevice: dev_t,
    descriptorByteSize: UInt64
  ) throws -> OpenedArtifacts {
    let limits = ManifestReplayArtifactBundleLimits.default
    var total = descriptorByteSize
    var files: [OpenedFile] = []
    files.reserveCapacity(descriptor.externalArtifactBindings.count)
    do {
      for binding in descriptor.externalArtifactBindings {
        try Task.checkCancellation()
        guard let name = filenames[binding.kind],
          let maximum = limits.maximumBytes(for: binding.kind)
        else {
          throw ManifestReplayFixtureFileLoadingError.invalidDescriptor
        }
        let file = try openFile(
          parent: parent,
          name: name,
          expectedSize: binding.byteSize,
          maximumSize: maximum,
          kind: binding.kind,
          expectedSHA256: binding.sha256.lowercaseHex,
          rootDevice: rootDevice
        )
        let (next, overflow) = total.addingReportingOverflow(binding.byteSize)
        guard !overflow, next <= limits.totalBytes else {
          _ = close(file.descriptor)
          throw ManifestReplayFixtureFileLoadingError.oversized
        }
        total = next
        files.append(file)
      }
      return OpenedArtifacts(files: files, totalByteSize: total)
    } catch {
      closeAllIgnoringErrors(&files)
      throw error
    }
  }

  private static func readArtifact(
    _ file: inout OpenedFile,
    parent: Int32,
    hook: @Sendable (ManifestEvidenceArtifactKind) throws -> Void
  ) throws -> Data {
    guard let kind = file.kind else {
      throw ManifestReplayFixtureFileLoadingError.invalidDescriptor
    }
    let read = try preadFile(&file, parent: parent) {
      try run { try hook(kind) }
    }
    guard read.sha256 == file.expectedSHA256 else {
      throw ManifestReplayFixtureFileLoadingError.artifactMismatch
    }
    return read.data
  }

  private static func openFile(
    parent: Int32,
    name: String,
    expectedSize: UInt64?,
    maximumSize: UInt64,
    kind: ManifestEvidenceArtifactKind?,
    expectedSHA256: String,
    rootDevice: dev_t
  ) throws -> OpenedFile {
    var pathMetadata = stat()
    guard fstatat(parent, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { throw ManifestReplayFixtureFileLoadingError.invalidInventory }
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
    guard isAllowedRegularFile(pathMetadata), pathMetadata.st_dev == rootDevice,
      pathMetadata.st_size > 0,
      let byteSize = UInt64(exactly: pathMetadata.st_size)
    else {
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
    guard byteSize <= maximumSize else {
      throw ManifestReplayFixtureFileLoadingError.oversized
    }
    guard expectedSize.map({ $0 == byteSize }) != false else {
      throw ManifestReplayFixtureFileLoadingError.artifactMismatch
    }
    let descriptor = openat(
      parent,
      name,
      O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
    var opened = stat()
    guard fstat(descriptor, &opened) == 0,
      isAllowedRegularFile(opened), opened.st_dev == rootDevice,
      sameFile(opened, pathMetadata),
      sameStableMetadata(opened, pathMetadata)
    else {
      _ = close(descriptor)
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
    return OpenedFile(
      descriptor: descriptor,
      name: name,
      kind: kind,
      expectedSHA256: expectedSHA256,
      byteSize: byteSize,
      identity: opened
    )
  }

  private static func preadFile(
    _ file: inout OpenedFile,
    parent: Int32,
    beforePostCheck: () throws -> Void
  ) throws -> ReadFile {
    guard file.descriptor >= 0, let count = Int(exactly: file.byteSize) else {
      throw ManifestReplayFixtureFileLoadingError.oversized
    }
    var data = Data(count: count)
    var hasher = SHA256()
    try data.withUnsafeMutableBytes { bytes in
      var offset = 0
      while offset < count {
        try Task.checkCancellation()
        let requested = min(readChunkBytes, count - offset)
        let readCount = pread(
          file.descriptor,
          bytes.baseAddress?.advanced(by: offset),
          requested,
          off_t(offset)
        )
        if readCount < 0, errno == EINTR { continue }
        guard readCount > 0 else {
          throw ManifestReplayFixtureFileLoadingError.artifactMismatch
        }
        hasher.update(
          bufferPointer: UnsafeRawBufferPointer(
            start: bytes.baseAddress?.advanced(by: offset),
            count: readCount
          ))
        offset += readCount
      }
    }
    var extra: UInt8 = 0
    var extraCount: Int
    repeat {
      extraCount = pread(file.descriptor, &extra, 1, off_t(count))
    } while extraCount < 0 && errno == EINTR
    guard extraCount == 0 else {
      throw ManifestReplayFixtureFileLoadingError.artifactMismatch
    }
    try beforePostCheck()
    try requireFileStillAnchored(file, parent: parent)
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()

    let completed = file.descriptor
    file.descriptor = -1
    guard close(completed) == 0 else {
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
    return ReadFile(data: data, sha256: digest, byteSize: file.byteSize)
  }

  private static func requireFileStillAnchored(
    _ file: OpenedFile,
    parent: Int32
  ) throws {
    var completed = stat()
    var path = stat()
    guard fstat(file.descriptor, &completed) == 0,
      fstatat(parent, file.name, &path, AT_SYMLINK_NOFOLLOW) == 0,
      isAllowedRegularFile(completed), isAllowedRegularFile(path),
      sameFile(completed, file.identity), sameFile(path, file.identity),
      sameStableMetadata(completed, file.identity), sameStableMetadata(path, file.identity)
    else {
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
  }

  private static func validateBundle(
    descriptor: ValidatedReplayDescriptor,
    artifacts: [ManifestReplayArtifactData]
  ) throws -> ValidatedReplayArtifactBundle {
    do {
      return try ManifestReplayArtifactBundleValidator.validate(
        descriptor: descriptor,
        artifacts: artifacts
      )
    } catch let error as CancellationError {
      throw error
    } catch ManifestReplayArtifactBundleValidationError.oversized {
      throw ManifestReplayFixtureFileLoadingError.oversized
    } catch ManifestReplayArtifactBundleValidationError.artifactMismatch {
      throw ManifestReplayFixtureFileLoadingError.artifactMismatch
    } catch {
      throw ManifestReplayFixtureFileLoadingError.invalidDescriptor
    }
  }

  private static func requireExactInventory(
    _ descriptor: Int32,
    expected: Set<String>
  ) throws {
    let actual = try directoryEntries(descriptor)
    guard actual == expected else {
      throw ManifestReplayFixtureFileLoadingError.invalidInventory
    }
  }

  private static func directoryEntries(_ descriptor: Int32) throws -> Set<String> {
    let independent = openat(
      descriptor,
      ".",
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard independent >= 0 else {
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
    guard let directory = fdopendir(independent) else {
      _ = close(independent)
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
    var ownsDirectory = true
    defer { if ownsDirectory { _ = closedir(directory) } }
    let allowed = Set(filenames.values).union([descriptorName])
    var names = Set<String>()
    while true {
      errno = 0
      guard let entry = readdir(directory) else {
        if errno != 0 { throw ManifestReplayFixtureFileLoadingError.ioFailure }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(validatingCString: $0)
        }
      }
      guard let name else { throw ManifestReplayFixtureFileLoadingError.invalidInventory }
      if name == "." || name == ".." { continue }
      guard allowed.contains(name), names.insert(name).inserted,
        names.count <= maximumInventoryCount
      else {
        throw ManifestReplayFixtureFileLoadingError.invalidInventory
      }
    }
    ownsDirectory = false
    guard closedir(directory) == 0 else {
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
    return names
  }

  private static func requireDirectoryStillAnchored(
    _ descriptor: Int32,
    metadata: stat,
    name: String,
    parent: Int32
  ) throws {
    var opened = stat()
    var path = stat()
    guard fstat(descriptor, &opened) == 0,
      fstatat(parent, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
      isAllowedDirectory(opened), isAllowedDirectory(path),
      sameFile(opened, metadata), sameFile(path, metadata),
      sameStableMetadata(opened, metadata), sameStableMetadata(path, metadata)
    else {
      throw ManifestReplayFixtureFileLoadingError.unsafeEntry
    }
  }

  private static func requireRootStillAnchored(
    _ url: URL,
    descriptor: Int32,
    metadata: stat
  ) throws {
    var opened = stat()
    guard fstat(descriptor, &opened) == 0,
      isAllowedDirectory(opened), sameFile(opened, metadata),
      sameStableMetadata(opened, metadata)
    else {
      throw ManifestReplayFixtureFileLoadingError.invalidRoot
    }
    let current = try openRoot(url)
    var currentDescriptor = current.descriptor
    defer { if currentDescriptor >= 0 { _ = close(currentDescriptor) } }
    guard sameFile(current.metadata, metadata),
      sameStableMetadata(current.metadata, metadata)
    else {
      throw ManifestReplayFixtureFileLoadingError.invalidRoot
    }
    let completed = currentDescriptor
    currentDescriptor = -1
    guard close(completed) == 0 else {
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
  }

  private static func absolutePathComponents(_ path: String) -> [String]? {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
    if path == "/" { return [] }
    let raw = path.split(separator: "/", omittingEmptySubsequences: false)
    guard raw.first?.isEmpty == true else { return nil }
    let components = raw.dropFirst()
    guard
      components.allSatisfy({
        !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= Int(NAME_MAX)
      })
    else {
      return nil
    }
    return components.map(String.init)
  }

  private static func isDirectory(_ metadata: stat) -> Bool {
    metadata.st_mode & S_IFMT == S_IFDIR
  }

  private static func isAllowedDirectory(_ metadata: stat) -> Bool {
    isDirectory(metadata)
      && metadata.st_uid == geteuid()
      && metadata.st_mode & (S_ISUID | S_ISGID | S_ISVTX) == 0
      && metadata.st_mode & S_IRWXU == S_IRWXU
      && metadata.st_mode & 0o022 == 0
  }

  private static func isAllowedRegularFile(_ metadata: stat) -> Bool {
    metadata.st_mode & S_IFMT == S_IFREG
      && metadata.st_uid == geteuid()
      && metadata.st_nlink == 1
      && metadata.st_mode & (S_ISUID | S_ISGID | S_ISVTX) == 0
      && metadata.st_mode & S_IRUSR != 0
      && metadata.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH) == 0
      && metadata.st_mode & 0o022 == 0
  }

  private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
  }

  private static func sameModeAndSize(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_mode == rhs.st_mode && lhs.st_size == rhs.st_size
  }

  private static func sameStableMetadata(_ lhs: stat, _ rhs: stat) -> Bool {
    sameModeAndSize(lhs, rhs)
      && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
      && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
      && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
      && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
  }

  private static func run(_ hook: @Sendable () throws -> Void) throws {
    do {
      try hook()
    } catch let error as CancellationError {
      throw error
    } catch {
      throw ManifestReplayFixtureFileLoadingError.ioFailure
    }
  }

  private static func closeAllIgnoringErrors(_ files: inout [OpenedFile]) {
    for index in files.indices where files[index].descriptor >= 0 {
      _ = close(files[index].descriptor)
      files[index].descriptor = -1
    }
  }
}

extension ManifestReplayFixtureFileLoader: ManifestReplayRedactedValue {}

private struct OpenedDirectory {
  let descriptor: Int32
  let metadata: stat
}

private struct OpenedFile {
  var descriptor: Int32
  let name: String
  let kind: ManifestEvidenceArtifactKind?
  var expectedSHA256: String
  let byteSize: UInt64
  let identity: stat
}

private struct OpenedArtifacts {
  var files: [OpenedFile]
  let totalByteSize: UInt64
}

private struct ReadFile {
  let data: Data
  let sha256: String
  let byteSize: UInt64
}
