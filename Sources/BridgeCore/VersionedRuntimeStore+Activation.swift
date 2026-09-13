import Darwin
import Foundation

extension VersionedRuntimeStore {
  public func activateFirst(
    installed: InstalledRuntimeVersion,
    verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest
  ) throws -> RuntimeActivationRecord {
    let activation = try RuntimeActivationIdentityBuilder.build(
      installed: installed,
      verifiedCatalog: verifiedCatalog,
      request: request,
      generation: 1
    )
    let installID = installed.record.installID
    let prefixName = String(installID.prefix(2))
    let expectedVersionURL =
      rootURL
      .appendingPathComponent("versions", isDirectory: true)
      .appendingPathComponent(prefixName, isDirectory: true)
      .appendingPathComponent(installID, isDirectory: true)
    guard installed.versionURL == expectedVersionURL else {
      throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let installReceipt = try encoder.encode(installed.record)
    let activationData = try encoder.encode(activation)
    let expectedCandidate = Self.candidate(
      from: installed.record,
      rootURL: expectedVersionURL.appendingPathComponent("payload", isDirectory: true)
    )
    let rootDescriptor = try Self.openRoot(rootURL)
    defer { _ = close(rootDescriptor) }
    var rootMetadata = stat()
    guard fstat(rootDescriptor, &rootMetadata) == 0,
      Self.rootPathMatches(rootURL, metadata: rootMetadata)
    else {
      throw VersionedRuntimeStoreError.unsafeRuntimeRoot
    }
    let lockDescriptor = try Self.acquirePublishLock(
      rootDescriptor: rootDescriptor,
      rootDevice: rootMetadata.st_dev
    )
    defer {
      _ = flock(lockDescriptor, LOCK_UN)
      _ = close(lockDescriptor)
    }
    let versions = try Self.openExistingDirectory(
      named: "versions", parent: rootDescriptor, rootDevice: rootMetadata.st_dev)
    defer { _ = close(versions.descriptor) }
    let prefix = try Self.openExistingDirectory(
      named: prefixName, parent: versions.descriptor, rootDevice: rootMetadata.st_dev)
    defer { _ = close(prefix.descriptor) }
    do {
      try Self.verifyExistingVersion(
        prefixDescriptor: prefix.descriptor,
        installID: installID,
        versionURL: expectedVersionURL,
        rootDevice: rootMetadata.st_dev,
        candidate: expectedCandidate,
        receipt: installReceipt
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
    }
    try Self.requireMissingCurrent(rootDescriptor)

    let temporaryName = ".current.\(UUID().uuidString.lowercased()).tmp"
    var temporaryDescriptor: Int32 = -1
    var temporaryMetadata = stat()
    var temporaryCreated = false
    var committed = false
    defer { if temporaryDescriptor >= 0 { _ = close(temporaryDescriptor) } }
    do {
      temporaryDescriptor = openat(
        rootDescriptor,
        temporaryName,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
      )
      guard temporaryDescriptor >= 0 else { throw Self.currentPOSIXError() }
      temporaryCreated = true
      guard fchmod(temporaryDescriptor, S_IRUSR | S_IWUSR) == 0,
        fstat(temporaryDescriptor, &temporaryMetadata) == 0,
        Self.isPrivateRegularFile(temporaryMetadata, rootDevice: rootMetadata.st_dev),
        Self.entryMatches(
          parent: rootDescriptor, name: temporaryName,
          metadata: temporaryMetadata, type: S_IFREG)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      try Self.writeAll(activationData, descriptor: temporaryDescriptor)
      var completedMetadata = stat()
      guard fsync(temporaryDescriptor) == 0,
        fstat(temporaryDescriptor, &completedMetadata) == 0,
        Self.isPrivateRegularFile(completedMetadata, rootDevice: rootMetadata.st_dev),
        Self.sameFile(completedMetadata, temporaryMetadata),
        completedMetadata.st_size >= 0,
        UInt64(completedMetadata.st_size) == UInt64(activationData.count),
        Self.entryMatches(
          parent: rootDescriptor, name: temporaryName,
          metadata: completedMetadata, type: S_IFREG)
      else {
        throw Self.currentPOSIXError()
      }
      temporaryMetadata = completedMetadata
      let completedDescriptor = temporaryDescriptor
      temporaryDescriptor = -1
      guard close(completedDescriptor) == 0 else { throw Self.currentPOSIXError() }
      let temporaryIdentity = ReceiptIdentity(metadata: temporaryMetadata)
      try Self.verifyExactFile(
        parentDescriptor: rootDescriptor,
        name: temporaryName,
        expected: activationData,
        identity: temporaryIdentity,
        rootDevice: rootMetadata.st_dev
      )
      try preCurrentCommitHook?()
      try Self.requireMissingCurrent(rootDescriptor)
      do {
        try Self.verifyExistingVersion(
          prefixDescriptor: prefix.descriptor,
          installID: installID,
          versionURL: expectedVersionURL,
          rootDevice: rootMetadata.st_dev,
          candidate: expectedCandidate,
          receipt: installReceipt
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
      }
      try Self.verifyExactFile(
        parentDescriptor: rootDescriptor,
        name: temporaryName,
        expected: activationData,
        identity: temporaryIdentity,
        rootDevice: rootMetadata.st_dev
      )
      guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
        throw VersionedRuntimeStoreError.unsafeRuntimeRoot
      }
      try Task.checkCancellation()
      let renameResult = renameatx_np(
        rootDescriptor, temporaryName, rootDescriptor, "current.json", UInt32(RENAME_EXCL))
      guard renameResult == 0 else {
        if errno == EEXIST { throw VersionedRuntimeStoreError.currentAlreadyExists }
        throw VersionedRuntimeStoreError.publishFailed(errno)
      }
      committed = true
      do { try Self.sync(rootDescriptor) } catch {
        throw VersionedRuntimeCommittedError(
          state: .currentVisible(
            activationID: activation.activationID,
            durabilityConfirmed: false
          ),
          underlyingError: error
        )
      }
      do {
        try Self.verifyExactFile(
          parentDescriptor: rootDescriptor,
          name: "current.json",
          expected: activationData,
          identity: temporaryIdentity,
          rootDevice: rootMetadata.st_dev
        )
        guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
          throw VersionedRuntimeStoreError.unsafeRuntimeRoot
        }
        try postRenameHook?()
      } catch is CancellationError {
        return activation
      } catch {
        throw VersionedRuntimeCommittedError(
          state: .currentVisible(
            activationID: activation.activationID,
            durabilityConfirmed: true
          ),
          underlyingError: error
        )
      }
      return activation
    } catch {
      let activationError = error
      guard temporaryCreated, !committed else { throw activationError }
      do {
        if temporaryDescriptor >= 0 {
          let completedDescriptor = temporaryDescriptor
          temporaryDescriptor = -1
          guard close(completedDescriptor) == 0 else { throw Self.currentPOSIXError() }
        }
        guard
          Self.entryMatches(
            parent: rootDescriptor, name: temporaryName,
            metadata: temporaryMetadata, type: S_IFREG
          ), unlinkat(rootDescriptor, temporaryName, 0) == 0
        else {
          throw VersionedRuntimeStoreError.cleanupFailed
        }
        try Self.sync(rootDescriptor)
      } catch {
        throw VersionedRuntimeInstallAndCleanupError(
          installError: activationError,
          cleanupError: error
        )
      }
      throw activationError
    }
  }

  public func activateReplacingCurrent(
    installed: InstalledRuntimeVersion,
    verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest,
    expectedCurrent: RuntimeActivationRecord
  ) throws -> RuntimeActivationRecord {
    guard Self.validExpectedCurrent(expectedCurrent) else {
      throw VersionedRuntimeStoreError.invalidExpectedCurrent
    }
    let (generation, overflow) = expectedCurrent.generation.addingReportingOverflow(1)
    guard !overflow else { throw VersionedRuntimeStoreError.invalidExpectedCurrent }
    let activation = try RuntimeActivationIdentityBuilder.build(
      installed: installed,
      verifiedCatalog: verifiedCatalog,
      request: request,
      generation: generation
    )
    let installID = installed.record.installID
    let prefixName = String(installID.prefix(2))
    let expectedVersionURL =
      rootURL
      .appendingPathComponent("versions", isDirectory: true)
      .appendingPathComponent(prefixName, isDirectory: true)
      .appendingPathComponent(installID, isDirectory: true)
    guard installed.versionURL == expectedVersionURL else {
      throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let installReceipt = try encoder.encode(installed.record)
    let expectedCurrentData = try encoder.encode(expectedCurrent)
    let activationData = try encoder.encode(activation)
    let expectedCandidate = Self.candidate(
      from: installed.record,
      rootURL: expectedVersionURL.appendingPathComponent("payload", isDirectory: true)
    )

    let rootDescriptor = try Self.openRoot(rootURL)
    defer { _ = close(rootDescriptor) }
    var rootMetadata = stat()
    guard fstat(rootDescriptor, &rootMetadata) == 0,
      Self.rootPathMatches(rootURL, metadata: rootMetadata)
    else {
      throw VersionedRuntimeStoreError.unsafeRuntimeRoot
    }
    let lockDescriptor = try Self.acquirePublishLock(
      rootDescriptor: rootDescriptor,
      rootDevice: rootMetadata.st_dev
    )
    defer {
      _ = flock(lockDescriptor, LOCK_UN)
      _ = close(lockDescriptor)
    }
    let versions = try Self.openExistingDirectory(
      named: "versions", parent: rootDescriptor, rootDevice: rootMetadata.st_dev)
    defer { _ = close(versions.descriptor) }
    let prefix = try Self.openExistingDirectory(
      named: prefixName, parent: versions.descriptor, rootDevice: rootMetadata.st_dev)
    defer { _ = close(prefix.descriptor) }
    do {
      try Self.verifyExistingVersion(
        prefixDescriptor: prefix.descriptor,
        installID: installID,
        versionURL: expectedVersionURL,
        rootDevice: rootMetadata.st_dev,
        candidate: expectedCandidate,
        receipt: installReceipt
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
    }

    var currentMetadata = stat()
    guard fstatat(rootDescriptor, "current.json", &currentMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { throw VersionedRuntimeStoreError.currentChanged }
      throw Self.currentPOSIXError()
    }
    guard Self.isPrivateRegularFile(currentMetadata, rootDevice: rootMetadata.st_dev) else {
      throw VersionedRuntimeStoreError.unsafeStoreEntry
    }
    let currentIdentity = ReceiptIdentity(metadata: currentMetadata)
    do {
      try Self.verifyExactFile(
        parentDescriptor: rootDescriptor,
        name: "current.json",
        expected: expectedCurrentData,
        identity: currentIdentity,
        rootDevice: rootMetadata.st_dev
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.currentChanged
    }

    let temporaryName = ".current.\(UUID().uuidString.lowercased()).tmp"
    var temporaryDescriptor: Int32 = -1
    var temporaryMetadata = stat()
    var temporaryCreated = false
    var committed = false
    defer { if temporaryDescriptor >= 0 { _ = close(temporaryDescriptor) } }
    do {
      temporaryDescriptor = openat(
        rootDescriptor,
        temporaryName,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
      )
      guard temporaryDescriptor >= 0 else { throw Self.currentPOSIXError() }
      temporaryCreated = true
      guard fchmod(temporaryDescriptor, S_IRUSR | S_IWUSR) == 0,
        fstat(temporaryDescriptor, &temporaryMetadata) == 0,
        Self.isPrivateRegularFile(temporaryMetadata, rootDevice: rootMetadata.st_dev),
        Self.entryMatches(
          parent: rootDescriptor, name: temporaryName,
          metadata: temporaryMetadata, type: S_IFREG)
      else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
      try Self.writeAll(activationData, descriptor: temporaryDescriptor)
      var completedMetadata = stat()
      guard fsync(temporaryDescriptor) == 0,
        fstat(temporaryDescriptor, &completedMetadata) == 0,
        Self.isPrivateRegularFile(completedMetadata, rootDevice: rootMetadata.st_dev),
        Self.sameFile(completedMetadata, temporaryMetadata),
        completedMetadata.st_size >= 0,
        UInt64(completedMetadata.st_size) == UInt64(activationData.count),
        Self.entryMatches(
          parent: rootDescriptor, name: temporaryName,
          metadata: completedMetadata, type: S_IFREG)
      else {
        throw Self.currentPOSIXError()
      }
      temporaryMetadata = completedMetadata
      let completedDescriptor = temporaryDescriptor
      temporaryDescriptor = -1
      guard close(completedDescriptor) == 0 else { throw Self.currentPOSIXError() }
      let temporaryIdentity = ReceiptIdentity(metadata: temporaryMetadata)
      try Self.verifyExactFile(
        parentDescriptor: rootDescriptor, name: temporaryName,
        expected: activationData, identity: temporaryIdentity,
        rootDevice: rootMetadata.st_dev
      )

      try preCurrentCommitHook?()
      do {
        try Self.verifyExactFile(
          parentDescriptor: rootDescriptor, name: "current.json",
          expected: expectedCurrentData, identity: currentIdentity,
          rootDevice: rootMetadata.st_dev
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw VersionedRuntimeStoreError.currentChanged
      }
      do {
        try Self.verifyExistingVersion(
          prefixDescriptor: prefix.descriptor,
          installID: installID,
          versionURL: expectedVersionURL,
          rootDevice: rootMetadata.st_dev,
          candidate: expectedCandidate,
          receipt: installReceipt
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
      }
      try Self.verifyExactFile(
        parentDescriptor: rootDescriptor, name: temporaryName,
        expected: activationData, identity: temporaryIdentity,
        rootDevice: rootMetadata.st_dev
      )
      guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
        throw VersionedRuntimeStoreError.unsafeRuntimeRoot
      }
      try Task.checkCancellation()
      let swapResult = renameatx_np(
        rootDescriptor, temporaryName, rootDescriptor, "current.json", UInt32(RENAME_SWAP))
      guard swapResult == 0 else {
        let code = errno
        if code == ENOTSUP || code == EINVAL || code == ENOSYS {
          throw VersionedRuntimeStoreError.currentSwapUnsupported(code)
        }
        throw VersionedRuntimeStoreError.publishFailed(code)
      }
      committed = true
      do { try Self.sync(rootDescriptor) } catch {
        throw VersionedRuntimeCommittedError(
          state: .currentVisible(
            activationID: activation.activationID,
            durabilityConfirmed: false
          ),
          underlyingError: error
        )
      }
      do {
        try Self.verifyExactFile(
          parentDescriptor: rootDescriptor, name: "current.json",
          expected: activationData, identity: temporaryIdentity,
          rootDevice: rootMetadata.st_dev, checkCancellation: false
        )
        try Self.verifyExactFile(
          parentDescriptor: rootDescriptor, name: temporaryName,
          expected: expectedCurrentData, identity: currentIdentity,
          rootDevice: rootMetadata.st_dev, checkCancellation: false
        )
        guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
          throw VersionedRuntimeStoreError.unsafeRuntimeRoot
        }
        try postRenameHook?()
        guard
          Self.entryMatches(
            parent: rootDescriptor, name: temporaryName,
            metadata: currentMetadata, type: S_IFREG
          ), unlinkat(rootDescriptor, temporaryName, 0) == 0
        else {
          throw VersionedRuntimeStoreError.cleanupFailed
        }
        try Self.sync(rootDescriptor)
        try Self.verifyExactFile(
          parentDescriptor: rootDescriptor, name: "current.json",
          expected: activationData, identity: temporaryIdentity,
          rootDevice: rootMetadata.st_dev, checkCancellation: false
        )
        guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
          throw VersionedRuntimeStoreError.unsafeRuntimeRoot
        }
      } catch {
        throw VersionedRuntimeCommittedError(
          state: .currentVisible(
            activationID: activation.activationID,
            durabilityConfirmed: true
          ),
          underlyingError: error
        )
      }
      return activation
    } catch {
      let activationError = error
      guard temporaryCreated, !committed else { throw activationError }
      do {
        if temporaryDescriptor >= 0 {
          let completedDescriptor = temporaryDescriptor
          temporaryDescriptor = -1
          guard close(completedDescriptor) == 0 else { throw Self.currentPOSIXError() }
        }
        guard
          Self.entryMatches(
            parent: rootDescriptor, name: temporaryName,
            metadata: temporaryMetadata, type: S_IFREG
          ), unlinkat(rootDescriptor, temporaryName, 0) == 0
        else {
          throw VersionedRuntimeStoreError.cleanupFailed
        }
        try Self.sync(rootDescriptor)
      } catch {
        throw VersionedRuntimeInstallAndCleanupError(
          installError: activationError,
          cleanupError: error
        )
      }
      throw activationError
    }
  }

  public func rollbackCurrent(
    to installed: InstalledRuntimeVersion,
    verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest,
    replacing expectedCurrent: RuntimeActivationRecord
  ) throws -> RuntimeActivationRecord {
    try activateReplacingCurrent(
      installed: installed,
      verifiedCatalog: verifiedCatalog,
      request: request,
      expectedCurrent: expectedCurrent
    )
  }

  public func resolveCurrent(
    in verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest
  ) throws -> ResolvedRuntimeCurrent {
    let rootDescriptor = try Self.openRoot(rootURL)
    defer { _ = close(rootDescriptor) }
    var rootMetadata = stat()
    guard fstat(rootDescriptor, &rootMetadata) == 0,
      Self.rootPathMatches(rootURL, metadata: rootMetadata)
    else {
      throw VersionedRuntimeStoreError.unsafeRuntimeRoot
    }
    let lockDescriptor = try Self.acquirePublishLock(
      rootDescriptor: rootDescriptor,
      rootDevice: rootMetadata.st_dev
    )
    defer {
      _ = flock(lockDescriptor, LOCK_UN)
      _ = close(lockDescriptor)
    }
    var currentPath = stat()
    guard fstatat(rootDescriptor, "current.json", &currentPath, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { throw VersionedRuntimeStoreError.currentMissing }
      throw Self.currentPOSIXError()
    }
    guard Self.isPrivateRegularFile(currentPath, rootDevice: rootMetadata.st_dev) else {
      throw VersionedRuntimeStoreError.currentInvalid
    }
    let currentFile: BoundedFile
    let current: RuntimeActivationRecord
    do {
      currentFile = try Self.readBoundedFile(
        parentDescriptor: rootDescriptor,
        name: "current.json",
        rootDevice: rootMetadata.st_dev,
        maximumBytes: RuntimeRecordDecoder.maximumActivationBytes
      )
      current = try RuntimeRecordDecoder.decodeActivation(currentFile.data)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.currentInvalid
    }
    let installed = try reopenInstalledLocked(
      installID: current.installID,
      verifiedCatalog: verifiedCatalog,
      rootDescriptor: rootDescriptor,
      rootMetadata: rootMetadata
    )
    let decision = try CompatibilitySelector.select(from: verifiedCatalog, request: request)
    let rebuilt: RuntimeActivationRecord
    do {
      rebuilt = try RuntimeActivationIdentityBuilder.build(
        installed: installed,
        verifiedCatalog: verifiedCatalog,
        request: request,
        generation: current.generation
      )
    } catch let error as CompatibilitySelectionError {
      throw error
    } catch {
      throw VersionedRuntimeStoreError.currentNotAuthorized
    }
    guard rebuilt == current,
      decision.profile.id == current.profileID,
      decision.profile.revision == current.profileRevision,
      decision.runtime.id == current.runtimeID,
      decision.runtime.definitionDigest == current.runtimeDefinitionSHA256
    else {
      throw VersionedRuntimeStoreError.currentNotAuthorized
    }
    let finalInstalled = try reopenInstalledLocked(
      installID: current.installID,
      verifiedCatalog: verifiedCatalog,
      rootDescriptor: rootDescriptor,
      rootMetadata: rootMetadata
    )
    guard finalInstalled.record == installed.record,
      finalInstalled.versionURL == installed.versionURL
    else {
      throw VersionedRuntimeStoreError.corruptExistingVersion(current.installID)
    }
    do {
      try Self.verifyExactFile(
        parentDescriptor: rootDescriptor,
        name: "current.json",
        expected: currentFile.data,
        identity: currentFile.identity,
        rootDevice: rootMetadata.st_dev
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.currentInvalid
    }
    guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
      throw VersionedRuntimeStoreError.unsafeRuntimeRoot
    }
    return ResolvedRuntimeCurrent(
      current: current,
      installed: finalInstalled,
      decision: decision
    )
  }

}
