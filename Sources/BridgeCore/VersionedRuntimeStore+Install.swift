import Darwin
import Foundation

extension VersionedRuntimeStore {
  public func install(
    runtime: RuntimeDefinition,
    plan: SafeArchivePlan,
    source: any ArchivePlannedContentSource
  ) throws -> InstalledRuntimeVersion {
    try Task.checkCancellation()
    guard runtime.acquisition == .managedDownload else {
      throw RuntimeInstallIdentityError.runtimeIsNotManagedDownload
    }
    guard runtime.redistributable,
      !runtime.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let rawArtifactSHA256 = runtime.sha256,
      Self.isHexSHA256(rawArtifactSHA256),
      let runtimeByteSize = runtime.byteSize,
      runtimeByteSize > 0
    else {
      throw RuntimeInstallIdentityError.invalidRuntimeIdentity
    }
    guard plan.policyVersion == SafeArchivePlanner.currentPolicyVersion else {
      throw RuntimeInstallIdentityError.unsupportedPlanPolicyVersion(plan.policyVersion)
    }
    guard runtimeByteSize == plan.archiveByteSize else {
      throw RuntimeInstallIdentityError.planMismatch
    }
    let artifactSHA256 = rawArtifactSHA256.lowercased()
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
    let staging = try Self.openOrCreateDirectory(
      named: ".staging",
      parent: rootDescriptor,
      rootDevice: rootMetadata.st_dev
    )
    defer { _ = close(staging.descriptor) }
    let versions = try Self.openOrCreateDirectory(
      named: "versions",
      parent: rootDescriptor,
      rootDevice: rootMetadata.st_dev
    )
    defer { _ = close(versions.descriptor) }

    let wrapperName = UUID().uuidString.lowercased()
    var wrapperDescriptor: Int32 = -1
    var wrapperMetadata = stat()
    var wrapperCreated = false
    var committed = false
    defer { if wrapperDescriptor >= 0 { _ = close(wrapperDescriptor) } }
    do {
      (wrapperDescriptor, wrapperMetadata) = try Self.createUniqueDirectory(
        named: wrapperName,
        parent: staging.descriptor,
        rootDevice: rootMetadata.st_dev
      )
      wrapperCreated = true
      let wrapperURL =
        rootURL
        .appendingPathComponent(".staging", isDirectory: true)
        .appendingPathComponent(wrapperName, isDirectory: true)
      let payloadURL = wrapperURL.appendingPathComponent("payload", isDirectory: true)
      let candidate = try SafeStagingExtractor.extract(
        plan: plan,
        expectedArtifactSHA256: artifactSHA256,
        toNewRoot: payloadURL,
        source: source
      )
      let record = try RuntimeInstallIdentityBuilder.build(
        runtime: runtime,
        plan: plan,
        candidate: candidate
      )
      try SafeStagingExtractor.reverify(candidate)

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let receipt = try encoder.encode(record)
      let receiptIdentity = try Self.writeReceipt(
        receipt,
        wrapperDescriptor: wrapperDescriptor,
        rootDevice: rootMetadata.st_dev
      )
      try Self.verifyWrapper(
        wrapperDescriptor,
        rootDevice: rootMetadata.st_dev,
        candidate: candidate,
        receipt: receipt,
        receiptIdentity: receiptIdentity
      )

      let prefixName = String(record.installID.prefix(2))
      let prefix = try Self.openOrCreateDirectory(
        named: prefixName,
        parent: versions.descriptor,
        rootDevice: rootMetadata.st_dev
      )
      defer { _ = close(prefix.descriptor) }
      guard staging.metadata.st_dev == prefix.metadata.st_dev,
        wrapperMetadata.st_dev == prefix.metadata.st_dev
      else {
        throw VersionedRuntimeStoreError.stagingCrossVolume
      }
      try SafeStagingExtractor.reverify(candidate)
      try Self.verifyWrapper(
        wrapperDescriptor,
        rootDevice: rootMetadata.st_dev,
        candidate: candidate,
        receipt: receipt,
        receiptIdentity: receiptIdentity
      )
      guard Self.rootPathMatches(rootURL, metadata: rootMetadata),
        Self.entryMatches(
          parent: staging.descriptor,
          name: wrapperName,
          metadata: wrapperMetadata,
          type: S_IFDIR
        )
      else {
        throw VersionedRuntimeStoreError.unsafeRuntimeRoot
      }
      try Task.checkCancellation()
      let versionURL =
        rootURL
        .appendingPathComponent("versions", isDirectory: true)
        .appendingPathComponent(prefixName, isDirectory: true)
        .appendingPathComponent(record.installID, isDirectory: true)
      let renameResult = renameatx_np(
        staging.descriptor,
        wrapperName,
        prefix.descriptor,
        record.installID,
        UInt32(RENAME_EXCL)
      )
      if renameResult != 0 {
        let code = errno
        if code == EEXIST {
          do {
            try Self.verifyExistingVersion(
              prefixDescriptor: prefix.descriptor,
              installID: record.installID,
              versionURL: versionURL,
              rootDevice: rootMetadata.st_dev,
              candidate: candidate,
              receipt: receipt
            )
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            throw VersionedRuntimeStoreError.corruptExistingVersion(record.installID)
          }
          do {
            try Self.cleanupWrapper(
              descriptor: &wrapperDescriptor,
              metadata: wrapperMetadata,
              name: wrapperName,
              stagingDescriptor: staging.descriptor,
              rootDevice: rootMetadata.st_dev
            )
          } catch {
            wrapperCreated = false
            throw VersionedRuntimeInstallAndCleanupError(
              installError: VersionedRuntimeStoreError.versionAlreadyExists(record.installID),
              cleanupError: error
            )
          }
          wrapperCreated = false
          guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
            throw VersionedRuntimeStoreError.unsafeRuntimeRoot
          }
          return InstalledRuntimeVersion(
            versionURL: versionURL,
            record: record,
            disposition: .reusedExisting
          )
        }
        if code == EXDEV { throw VersionedRuntimeStoreError.stagingCrossVolume }
        throw VersionedRuntimeStoreError.publishFailed(code)
      }
      committed = true
      do {
        try Self.syncAfterRename(
          destination: prefix.descriptor,
          source: staging.descriptor
        )
      } catch {
        throw VersionedRuntimeCommittedError(
          state: .versionVisible(installID: record.installID, durabilityConfirmed: false),
          underlyingError: error
        )
      }
      do {
        guard
          Self.entryMatches(
            parent: prefix.descriptor,
            name: record.installID,
            metadata: wrapperMetadata,
            type: S_IFDIR
          )
        else {
          throw VersionedRuntimeStoreError.unsafeStoreEntry
        }
        let relocatedCandidate = Self.relocated(
          candidate,
          to: versionURL.appendingPathComponent("payload", isDirectory: true)
        )
        try SafeStagingExtractor.reverify(relocatedCandidate)
        try Self.verifyWrapper(
          wrapperDescriptor,
          rootDevice: rootMetadata.st_dev,
          candidate: relocatedCandidate,
          receipt: receipt,
          receiptIdentity: receiptIdentity
        )
        guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
          throw VersionedRuntimeStoreError.unsafeRuntimeRoot
        }
        try postRenameHook?()
      } catch is CancellationError {
        return InstalledRuntimeVersion(
          versionURL: versionURL,
          record: record,
          disposition: .published
        )
      } catch {
        throw VersionedRuntimeCommittedError(
          state: .versionVisible(installID: record.installID, durabilityConfirmed: true),
          underlyingError: error
        )
      }
      return InstalledRuntimeVersion(
        versionURL: versionURL,
        record: record,
        disposition: .published
      )
    } catch {
      let installError = error
      guard wrapperCreated, !committed else { throw installError }
      do {
        try Self.cleanupWrapper(
          descriptor: &wrapperDescriptor,
          metadata: wrapperMetadata,
          name: wrapperName,
          stagingDescriptor: staging.descriptor,
          rootDevice: rootMetadata.st_dev
        )
      } catch {
        throw VersionedRuntimeInstallAndCleanupError(
          installError: installError,
          cleanupError: error
        )
      }
      throw installError
    }
  }

  public func reopenInstalled(
    installID: String,
    in verifiedCatalog: VerifiedCatalog
  ) throws -> InstalledRuntimeVersion {
    guard Self.isLowercaseSHA256(installID) else {
      throw VersionedRuntimeStoreError.invalidInstallID
    }
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
    return try reopenInstalledLocked(
      installID: installID,
      verifiedCatalog: verifiedCatalog,
      rootDescriptor: rootDescriptor,
      rootMetadata: rootMetadata
    )
  }
  func reopenInstalledLocked(
    installID: String,
    verifiedCatalog: VerifiedCatalog,
    rootDescriptor: Int32,
    rootMetadata: stat
  ) throws -> InstalledRuntimeVersion {
    let versions = try Self.openExistingDirectory(
      named: "versions", parent: rootDescriptor, rootDevice: rootMetadata.st_dev)
    defer { _ = close(versions.descriptor) }
    let prefixName = String(installID.prefix(2))
    let prefix = try Self.openExistingDirectory(
      named: prefixName, parent: versions.descriptor, rootDevice: rootMetadata.st_dev)
    defer { _ = close(prefix.descriptor) }
    let versionURL =
      rootURL
      .appendingPathComponent("versions", isDirectory: true)
      .appendingPathComponent(prefixName, isDirectory: true)
      .appendingPathComponent(installID, isDirectory: true)
    let receipt: Data
    let record: RuntimeInstallRecord
    do {
      receipt = try Self.readExistingReceipt(
        prefixDescriptor: prefix.descriptor,
        installID: installID,
        rootDevice: rootMetadata.st_dev
      )
      record = try RuntimeRecordDecoder.decodeInstall(receipt)
      guard record.installID == installID else {
        throw VersionedRuntimeStoreError.unsafeStoreEntry
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
    }
    guard Self.catalogTrusts(record, verifiedCatalog: verifiedCatalog) else {
      throw VersionedRuntimeStoreError.untrustedRuntime(record.runtimeID)
    }
    let expectedCandidate = Self.candidate(
      from: record,
      rootURL: versionURL.appendingPathComponent("payload", isDirectory: true)
    )
    do {
      try Self.verifyExistingVersion(
        prefixDescriptor: prefix.descriptor,
        installID: installID,
        versionURL: versionURL,
        rootDevice: rootMetadata.st_dev,
        candidate: expectedCandidate,
        receipt: receipt
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VersionedRuntimeStoreError.corruptExistingVersion(installID)
    }
    guard Self.rootPathMatches(rootURL, metadata: rootMetadata) else {
      throw VersionedRuntimeStoreError.unsafeRuntimeRoot
    }
    return InstalledRuntimeVersion(
      versionURL: versionURL,
      record: record,
      disposition: .reopenedExisting
    )
  }
}
