import Darwin
import Foundation

extension VersionedRuntimeStore {
  struct OpenedDirectory {
    let descriptor: Int32
    let metadata: stat
  }

  struct ReceiptIdentity {
    let metadata: stat
  }

  struct BoundedFile {
    let data: Data
    let identity: ReceiptIdentity
  }

  static func openRoot(_ url: URL) throws -> Int32 {
    guard url.isFileURL, url.host == nil || url.host?.isEmpty == true,
      let components = absolutePathComponents(url.path), !components.isEmpty
    else {
      throw VersionedRuntimeStoreError.invalidRootURL
    }
    var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard current >= 0 else { throw currentPOSIXError() }
    do {
      for component in components {
        var pathMetadata = stat()
        guard fstatat(current, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
          pathMetadata.st_mode & S_IFMT == S_IFDIR
        else {
          throw VersionedRuntimeStoreError.unsafeRuntimeRoot
        }
        let next = openat(
          current,
          component,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard next >= 0 else { throw VersionedRuntimeStoreError.unsafeRuntimeRoot }
        var opened = stat()
        guard fstat(next, &opened) == 0, sameFile(pathMetadata, opened),
          opened.st_mode & S_IFMT == S_IFDIR
        else {
          _ = close(next)
          throw VersionedRuntimeStoreError.unsafeRuntimeRoot
        }
        _ = close(current)
        current = next
      }
      var rootMetadata = stat()
      guard fstat(current, &rootMetadata) == 0, isPrivateDirectory(rootMetadata) else {
        throw VersionedRuntimeStoreError.unsafeRuntimeRoot
      }
      return current
    } catch {
      _ = close(current)
      throw error
    }
  }

  static func acquirePublishLock(
    rootDescriptor: Int32,
    rootDevice: dev_t
  ) throws -> Int32 {
    let name = ".publish.lock"
    var descriptor = openat(
      rootDescriptor,
      name,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    let created = descriptor >= 0
    if descriptor < 0, errno == EEXIST {
      descriptor = openat(rootDescriptor, name, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    }
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      if created {
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw currentPOSIXError() }
      }
      var metadata = stat()
      var pathMetadata = stat()
      guard fstat(descriptor, &metadata) == 0,
        fstatat(rootDescriptor, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
        isPrivateRegularFile(metadata, rootDevice: rootDevice),
        sameFile(metadata, pathMetadata)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      if created {
        try sync(descriptor)
        try sync(rootDescriptor)
      }
      while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
        let code = errno
        if code == EINTR { continue }
        if code == EWOULDBLOCK || code == EAGAIN {
          throw VersionedRuntimeStoreError.publisherBusy
        }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
      }
      return descriptor
    } catch {
      _ = close(descriptor)
      throw error
    }
  }

  static func openOrCreateDirectory(
    named name: String,
    parent: Int32,
    rootDevice: dev_t
  ) throws -> OpenedDirectory {
    var created = false
    if mkdirat(parent, name, S_IRWXU) == 0 {
      created = true
    } else if errno != EEXIST {
      throw currentPOSIXError()
    }
    var pathMetadata = stat()
    guard fstatat(parent, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      pathMetadata.st_mode & S_IFMT == S_IFDIR,
      pathMetadata.st_dev == rootDevice
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    let descriptor = openat(
      parent,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      if created { guard fchmod(descriptor, S_IRWXU) == 0 else { throw currentPOSIXError() } }
      var metadata = stat()
      guard fstat(descriptor, &metadata) == 0,
        isPrivateDirectory(metadata), metadata.st_dev == rootDevice,
        sameFile(metadata, pathMetadata)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      if created { try sync(parent) }
      return OpenedDirectory(descriptor: descriptor, metadata: metadata)
    } catch {
      _ = close(descriptor)
      throw error
    }
  }

  static func openExistingDirectory(
    named name: String,
    parent: Int32,
    rootDevice: dev_t
  ) throws -> OpenedDirectory {
    var pathMetadata = stat()
    guard fstatat(parent, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      isPrivateDirectory(pathMetadata), pathMetadata.st_dev == rootDevice
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    let descriptor = openat(
      parent,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    var opened = stat()
    guard fstat(descriptor, &opened) == 0,
      isPrivateDirectory(opened), sameFile(opened, pathMetadata)
    else {
      _ = close(descriptor)
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    return OpenedDirectory(descriptor: descriptor, metadata: opened)
  }

  static func createUniqueDirectory(
    named name: String,
    parent: Int32,
    rootDevice: dev_t
  ) throws -> (Int32, stat) {
    guard mkdirat(parent, name, S_IRWXU) == 0 else { throw currentPOSIXError() }
    var descriptor: Int32 = -1
    do {
      descriptor = openat(
        parent,
        name,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
      )
      guard descriptor >= 0 else { throw currentPOSIXError() }
      var metadata = stat()
      guard fchmod(descriptor, S_IRWXU) == 0,
        fstat(descriptor, &metadata) == 0,
        isPrivateDirectory(metadata), metadata.st_dev == rootDevice,
        entryMatches(parent: parent, name: name, metadata: metadata, type: S_IFDIR)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      try sync(parent)
      return (descriptor, metadata)
    } catch {
      let creationError = error
      var cleanupError: (any Error)?
      if descriptor >= 0, close(descriptor) != 0 { cleanupError = currentPOSIXError() }
      if unlinkat(parent, name, AT_REMOVEDIR) != 0 {
        cleanupError = currentPOSIXError()
      } else if cleanupError == nil {
        do { try sync(parent) } catch { cleanupError = error }
      }
      if let cleanupError {
        throw VersionedRuntimeInstallAndCleanupError(
          installError: creationError,
          cleanupError: cleanupError
        )
      }
      throw creationError
    }
  }

  static func writeReceipt(
    _ data: Data,
    wrapperDescriptor: Int32,
    rootDevice: dev_t
  ) throws -> ReceiptIdentity {
    try writeExactFile(
      data,
      name: "install.json",
      parentDescriptor: wrapperDescriptor,
      rootDevice: rootDevice
    )
  }

  private static func writeExactFile(
    _ data: Data,
    name: String,
    parentDescriptor: Int32,
    rootDevice: dev_t
  ) throws -> ReceiptIdentity {
    var descriptor = openat(
      parentDescriptor,
      name,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      try writeAll(data, descriptor: descriptor)
      guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0,
        fsync(descriptor) == 0
      else {
        throw currentPOSIXError()
      }
      var metadata = stat()
      guard fstat(descriptor, &metadata) == 0,
        isPrivateRegularFile(metadata, rootDevice: rootDevice),
        metadata.st_size >= 0, UInt64(metadata.st_size) == UInt64(data.count),
        entryMatches(parent: parentDescriptor, name: name, metadata: metadata, type: S_IFREG)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let completedDescriptor = descriptor
      descriptor = -1
      guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
      try sync(parentDescriptor)
      return ReceiptIdentity(metadata: metadata)
    } catch {
      if descriptor >= 0 { _ = close(descriptor) }
      throw error
    }
  }

  static func verifyWrapper(
    _ wrapperDescriptor: Int32,
    rootDevice: dev_t,
    candidate: ExtractedStagingTree,
    receipt: Data,
    receiptIdentity: ReceiptIdentity
  ) throws {
    guard try directoryEntries(wrapperDescriptor) == ["install.json", "payload"] else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    try verifyPayloadIdentity(wrapperDescriptor, rootDevice: rootDevice, candidate: candidate)
    try verifyReceipt(
      wrapperDescriptor,
      expected: receipt,
      identity: receiptIdentity,
      rootDevice: rootDevice
    )
  }

  private static func verifyReceipt(
    _ wrapperDescriptor: Int32,
    expected: Data,
    identity: ReceiptIdentity,
    rootDevice: dev_t
  ) throws {
    try verifyExactFile(
      parentDescriptor: wrapperDescriptor,
      name: "install.json",
      expected: expected,
      identity: identity,
      rootDevice: rootDevice
    )
  }

  static func verifyExactFile(
    parentDescriptor: Int32,
    name: String,
    expected: Data,
    identity: ReceiptIdentity,
    rootDevice: dev_t,
    checkCancellation: Bool = true
  ) throws {
    var pathMetadata = stat()
    guard fstatat(parentDescriptor, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      isPrivateRegularFile(pathMetadata, rootDevice: rootDevice),
      sameFile(pathMetadata, identity.metadata),
      pathMetadata.st_size >= 0,
      UInt64(pathMetadata.st_size) == UInt64(expected.count)
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    var descriptor = openat(
      parentDescriptor,
      name,
      O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      var opened = stat()
      guard fstat(descriptor, &opened) == 0,
        isPrivateRegularFile(opened, rootDevice: rootDevice),
        sameFile(opened, pathMetadata),
        try readExactly(
          descriptor,
          expected: expected,
          checkCancellation: checkCancellation
        )
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      var completed = stat()
      var currentPath = stat()
      guard fstat(descriptor, &completed) == 0,
        fstatat(parentDescriptor, name, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
        isPrivateRegularFile(completed, rootDevice: rootDevice),
        isPrivateRegularFile(currentPath, rootDevice: rootDevice),
        sameFile(completed, opened), sameFile(currentPath, opened),
        completed.st_size == opened.st_size,
        currentPath.st_size == opened.st_size
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let completedDescriptor = descriptor
      descriptor = -1
      guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
    } catch {
      if descriptor >= 0 { _ = close(descriptor) }
      throw error
    }
  }

  private static func verifyPayloadIdentity(
    _ wrapperDescriptor: Int32,
    rootDevice: dev_t,
    candidate: ExtractedStagingTree
  ) throws {
    var pathMetadata = stat()
    guard fstatat(wrapperDescriptor, "payload", &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      pathMetadata.st_mode & S_IFMT == S_IFDIR,
      isPrivateDirectory(pathMetadata), pathMetadata.st_dev == rootDevice,
      UInt64(exactly: pathMetadata.st_dev) == candidate.rootDevice,
      UInt64(exactly: pathMetadata.st_ino) == candidate.rootInode
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    let descriptor = openat(
      wrapperDescriptor,
      "payload",
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    defer { _ = close(descriptor) }
    var opened = stat()
    guard fstat(descriptor, &opened) == 0, sameFile(pathMetadata, opened),
      isPrivateDirectory(opened)
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
  }

  static func verifyExistingVersion(
    prefixDescriptor: Int32,
    installID: String,
    versionURL: URL,
    rootDevice: dev_t,
    candidate: ExtractedStagingTree,
    receipt: Data
  ) throws {
    var pathMetadata = stat()
    guard fstatat(prefixDescriptor, installID, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      isPrivateDirectory(pathMetadata), pathMetadata.st_dev == rootDevice
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    var descriptor = openat(
      prefixDescriptor,
      installID,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      var opened = stat()
      guard fstat(descriptor, &opened) == 0,
        isPrivateDirectory(opened), sameFile(opened, pathMetadata),
        try directoryEntries(descriptor) == ["install.json", "payload"]
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      var payload = stat()
      var receiptMetadata = stat()
      guard fstatat(descriptor, "payload", &payload, AT_SYMLINK_NOFOLLOW) == 0,
        isPrivateDirectory(payload), payload.st_dev == rootDevice,
        fstatat(descriptor, "install.json", &receiptMetadata, AT_SYMLINK_NOFOLLOW) == 0,
        let payloadDevice = UInt64(exactly: payload.st_dev),
        let payloadInode = UInt64(exactly: payload.st_ino)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let existingCandidate = ExtractedStagingTree(
        rootURL: versionURL.appendingPathComponent("payload", isDirectory: true),
        regularFileCount: candidate.regularFileCount,
        totalBytes: candidate.totalBytes,
        artifactSHA256: candidate.artifactSHA256,
        planSHA256: candidate.planSHA256,
        planPolicyVersion: candidate.planPolicyVersion,
        treeSealVersion: candidate.treeSealVersion,
        rootDevice: payloadDevice,
        rootInode: payloadInode,
        entries: candidate.entries,
        treeSHA256: candidate.treeSHA256
      )
      try SafeStagingExtractor.reverify(existingCandidate)
      try verifyWrapper(
        descriptor,
        rootDevice: rootDevice,
        candidate: existingCandidate,
        receipt: receipt,
        receiptIdentity: ReceiptIdentity(metadata: receiptMetadata)
      )
      var completed = stat()
      var currentPath = stat()
      guard fstat(descriptor, &completed) == 0,
        fstatat(prefixDescriptor, installID, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
        isPrivateDirectory(completed), isPrivateDirectory(currentPath),
        sameFile(completed, opened), sameFile(currentPath, opened)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let completedDescriptor = descriptor
      descriptor = -1
      guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
    } catch {
      if descriptor >= 0 { _ = close(descriptor) }
      throw error
    }
  }

  static func readExistingReceipt(
    prefixDescriptor: Int32,
    installID: String,
    rootDevice: dev_t
  ) throws -> Data {
    var pathMetadata = stat()
    guard fstatat(prefixDescriptor, installID, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      isPrivateDirectory(pathMetadata), pathMetadata.st_dev == rootDevice
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    var descriptor = openat(
      prefixDescriptor,
      installID,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      var opened = stat()
      guard fstat(descriptor, &opened) == 0,
        isPrivateDirectory(opened), sameFile(opened, pathMetadata),
        try directoryEntries(descriptor) == ["install.json", "payload"]
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let bounded = try readBoundedFile(
        parentDescriptor: descriptor,
        name: "install.json",
        rootDevice: rootDevice,
        maximumBytes: RuntimeRecordDecoder.maximumInstallBytes
      )
      var completed = stat()
      var currentPath = stat()
      guard fstat(descriptor, &completed) == 0,
        fstatat(prefixDescriptor, installID, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
        isPrivateDirectory(completed), isPrivateDirectory(currentPath),
        sameFile(completed, opened), sameFile(currentPath, opened)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let completedDescriptor = descriptor
      descriptor = -1
      guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
      return bounded.data
    } catch {
      if descriptor >= 0 { _ = close(descriptor) }
      throw error
    }
  }

  static func readBoundedFile(
    parentDescriptor: Int32,
    name: String,
    rootDevice: dev_t,
    maximumBytes: Int
  ) throws -> BoundedFile {
    var pathMetadata = stat()
    guard fstatat(parentDescriptor, name, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
      isPrivateRegularFile(pathMetadata, rootDevice: rootDevice),
      pathMetadata.st_size > 0,
      UInt64(pathMetadata.st_size) <= UInt64(maximumBytes)
    else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    var descriptor = openat(
      parentDescriptor,
      name,
      O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    do {
      var opened = stat()
      guard fstat(descriptor, &opened) == 0,
        isPrivateRegularFile(opened, rootDevice: rootDevice),
        sameFile(opened, pathMetadata), opened.st_size == pathMetadata.st_size
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      var data = Data(count: Int(opened.st_size))
      var offset = 0
      while offset < data.count {
        try Task.checkCancellation()
        let remaining = data.count - offset
        let count = data.withUnsafeMutableBytes {
          read(descriptor, $0.baseAddress?.advanced(by: offset), remaining)
        }
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { throw VersionedRuntimeStoreError.unsafeStoreEntry }
        offset += count
      }
      var extra: UInt8 = 0
      var extraCount: Int
      repeat { extraCount = read(descriptor, &extra, 1) } while extraCount < 0 && errno == EINTR
      guard extraCount == 0 else { throw VersionedRuntimeStoreError.unsafeStoreEntry }
      var completed = stat()
      var currentPath = stat()
      guard fstat(descriptor, &completed) == 0,
        fstatat(parentDescriptor, name, &currentPath, AT_SYMLINK_NOFOLLOW) == 0,
        isPrivateRegularFile(completed, rootDevice: rootDevice),
        isPrivateRegularFile(currentPath, rootDevice: rootDevice),
        sameFile(completed, opened), sameFile(currentPath, opened),
        completed.st_size == opened.st_size, currentPath.st_size == opened.st_size
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      let completedDescriptor = descriptor
      descriptor = -1
      guard close(completedDescriptor) == 0 else { throw currentPOSIXError() }
      return BoundedFile(data: data, identity: ReceiptIdentity(metadata: completed))
    } catch {
      if descriptor >= 0 { _ = close(descriptor) }
      throw error
    }
  }

  static func cleanupWrapper(
    descriptor: inout Int32,
    metadata: stat,
    name: String,
    stagingDescriptor: Int32,
    rootDevice: dev_t
  ) throws {
    guard descriptor >= 0 else { throw VersionedRuntimeStoreError.cleanupFailed }
    try removeTreeContents(descriptor, rootDevice: rootDevice)
    guard
      entryMatches(
        parent: stagingDescriptor,
        name: name,
        metadata: metadata,
        type: S_IFDIR
      )
    else {
      throw VersionedRuntimeStoreError.cleanupFailed
    }
    let completedDescriptor = descriptor
    descriptor = -1
    guard close(completedDescriptor) == 0,
      unlinkat(stagingDescriptor, name, AT_REMOVEDIR) == 0
    else {
      throw currentPOSIXError()
    }
    try sync(stagingDescriptor)
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
          throw VersionedRuntimeStoreError.cleanupFailed
        }
        var child = openat(
          descriptor,
          name,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        )
        guard child >= 0 else { throw currentPOSIXError() }
        do {
          var opened = stat()
          guard fstat(child, &opened) == 0, sameFile(metadata, opened) else {
            throw VersionedRuntimeStoreError.cleanupFailed
          }
          try removeTreeContents(child, rootDevice: rootDevice)
          var current = stat()
          guard fstatat(descriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
            sameFile(opened, current)
          else {
            throw VersionedRuntimeStoreError.cleanupFailed
          }
          let completed = child
          child = -1
          guard close(completed) == 0,
            unlinkat(descriptor, name, AT_REMOVEDIR) == 0
          else {
            throw currentPOSIXError()
          }
        } catch {
          if child >= 0 { _ = close(child) }
          throw error
        }
      } else if type == S_IFLNK {
        guard unlinkat(descriptor, name, 0) == 0 else { throw currentPOSIXError() }
      } else if type == S_IFREG {
        guard metadata.st_dev == rootDevice, metadata.st_uid == geteuid(),
          metadata.st_nlink == 1, unlinkat(descriptor, name, 0) == 0
        else {
          throw VersionedRuntimeStoreError.cleanupFailed
        }
      } else {
        throw VersionedRuntimeStoreError.cleanupFailed
      }
    }
    try sync(descriptor)
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
      guard let name else { throw VersionedRuntimeStoreError.unsafeStoreEntry }
      if name != "." && name != ".." { names.append(name) }
    }
    return names.sorted()
  }

  static func writeAll(_ data: Data, descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        try Task.checkCancellation()
        let count = write(
          descriptor,
          bytes.baseAddress?.advanced(by: offset),
          bytes.count - offset
        )
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { throw currentPOSIXError() }
        offset += count
      }
    }
  }

  private static func readExactly(
    _ descriptor: Int32,
    expected: Data,
    checkCancellation: Bool = true
  ) throws -> Bool {
    var offset = 0
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while offset < expected.count {
      if checkCancellation { try Task.checkCancellation() }
      let requested = min(buffer.count, expected.count - offset)
      let count = buffer.withUnsafeMutableBytes {
        read(descriptor, $0.baseAddress, requested)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw currentPOSIXError()
      }
      guard count > 0 else { return false }
      let matches = expected.withUnsafeBytes { bytes in
        buffer.withUnsafeBytes {
          memcmp(bytes.baseAddress?.advanced(by: offset), $0.baseAddress, count) == 0
        }
      }
      guard matches else { return false }
      offset += count
    }
    var extra: UInt8 = 0
    while true {
      let count = read(descriptor, &extra, 1)
      if count < 0, errno == EINTR { continue }
      if count < 0 { throw currentPOSIXError() }
      return count == 0
    }
  }

  private static func absolutePathComponents(_ path: String) -> [String]? {
    guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
    if path == "/" { return [] }
    let raw = path.split(separator: "/", omittingEmptySubsequences: false)
    guard raw.first?.isEmpty == true else { return nil }
    let components = raw.dropFirst()
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      return nil
    }
    return components.map(String.init)
  }

  static func requireMissingCurrent(_ rootDescriptor: Int32) throws {
    var metadata = stat()
    if fstatat(rootDescriptor, "current.json", &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
      throw VersionedRuntimeStoreError.currentAlreadyExists
    }
    guard errno == ENOENT else { throw currentPOSIXError() }
  }

  static func validExpectedCurrent(_ record: RuntimeActivationRecord) -> Bool {
    record.schemaVersion == RuntimeActivationRecord.currentSchemaVersion
      && record.generation > 0
      && record.planPolicyVersion == SafeArchivePlanner.currentPolicyVersion
      && record.treeSealVersion == SafeStagingTreeSealer.currentVersion
      && [
        record.activationID, record.catalogPayloadSHA256,
        record.profileDefinitionSHA256, record.disclosureSHA256,
        record.gameBuildFingerprint, record.runtimeDefinitionSHA256,
        record.installID, record.artifactSHA256, record.planSHA256,
        record.treeSHA256,
      ].allSatisfy(isHexSHA256)
      && record.acknowledgementSHA256.map(isHexSHA256) != false
  }

  static func rootPathMatches(_ url: URL, metadata: stat) -> Bool {
    var current = stat()
    return lstat(url.path, &current) == 0
      && isPrivateDirectory(current)
      && sameFile(metadata, current)
  }

  static func relocated(
    _ candidate: ExtractedStagingTree,
    to rootURL: URL
  ) -> ExtractedStagingTree {
    ExtractedStagingTree(
      rootURL: rootURL,
      regularFileCount: candidate.regularFileCount,
      totalBytes: candidate.totalBytes,
      artifactSHA256: candidate.artifactSHA256,
      planSHA256: candidate.planSHA256,
      planPolicyVersion: candidate.planPolicyVersion,
      treeSealVersion: candidate.treeSealVersion,
      rootDevice: candidate.rootDevice,
      rootInode: candidate.rootInode,
      entries: candidate.entries,
      treeSHA256: candidate.treeSHA256
    )
  }

  static func candidate(
    from record: RuntimeInstallRecord,
    rootURL: URL
  ) -> ExtractedStagingTree {
    let entries = record.entries.map {
      StagingTreeSealEntry(
        relativePath: $0.relativePath,
        kind: $0.kind,
        size: $0.size,
        mode: $0.mode,
        contentSHA256: $0.contentSHA256
      )
    }
    return ExtractedStagingTree(
      rootURL: rootURL,
      regularFileCount: record.regularFileCount,
      totalBytes: record.totalBytes,
      artifactSHA256: record.artifactSHA256,
      planSHA256: record.planSHA256,
      planPolicyVersion: record.planPolicyVersion,
      treeSealVersion: record.treeSealVersion,
      rootDevice: 0,
      rootInode: 0,
      entries: entries,
      treeSHA256: record.treeSHA256
    )
  }

  private static func isPrivateDirectory(_ metadata: stat) -> Bool {
    metadata.st_mode & S_IFMT == S_IFDIR
      && metadata.st_uid == geteuid()
      && metadata.st_mode & 0o777 == 0o700
  }

  static func isPrivateRegularFile(_ metadata: stat, rootDevice: dev_t) -> Bool {
    metadata.st_mode & S_IFMT == S_IFREG
      && metadata.st_uid == geteuid()
      && metadata.st_dev == rootDevice
      && metadata.st_nlink == 1
      && metadata.st_mode & 0o777 == 0o600
  }

  static func entryMatches(
    parent: Int32,
    name: String,
    metadata: stat,
    type: mode_t
  ) -> Bool {
    var current = stat()
    return fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0
      && current.st_mode & S_IFMT == type
      && sameFile(metadata, current)
  }

  static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
  }

  static func isHexSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      }
  }

  static func isLowercaseSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func catalogTrusts(
    _ record: RuntimeInstallRecord,
    verifiedCatalog: VerifiedCatalog
  ) -> Bool {
    let matching = verifiedCatalog.catalog.runtimes.filter { $0.id == record.runtimeID }
    guard matching.count == 1, let runtime = matching.first,
      runtime.acquisition == .managedDownload,
      runtime.verification != .blocked,
      !verifiedCatalog.catalog.revocations.runtimeIDs.contains(runtime.id),
      runtime.definitionDigest == record.runtimeDefinitionSHA256,
      let artifactSHA256 = runtime.sha256?.lowercased()
    else {
      return false
    }
    return isLowercaseSHA256(record.artifactSHA256)
      && isHexSHA256(artifactSHA256)
      && artifactSHA256 == record.artifactSHA256
  }

  static func sync(_ descriptor: Int32) throws {
    guard fsync(descriptor) == 0 else { throw currentPOSIXError() }
  }

  static func syncAfterRename(destination: Int32, source: Int32) throws {
    var firstError: Int32?
    if fsync(destination) != 0 { firstError = errno }
    if fsync(source) != 0, firstError == nil { firstError = errno }
    if let firstError {
      throw POSIXError(POSIXErrorCode(rawValue: firstError) ?? .EIO)
    }
  }

  static func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
