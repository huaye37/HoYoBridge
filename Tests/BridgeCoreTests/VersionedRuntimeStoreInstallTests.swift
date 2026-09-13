import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

extension VersionedRuntimeStoreTests {
  @Test
  func freshInstallPublishesVersionReceiptAndPayload() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let result = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime,
        plan: fixture.plan,
        source: fixture.source()
      )

      #expect(result.disposition == .published)
      #expect(result.versionURL.lastPathComponent == result.record.installID)
      #expect(
        result.versionURL.deletingLastPathComponent().lastPathComponent
          == String(result.record.installID.prefix(2)))
      #expect(
        try Data(contentsOf: result.versionURL.appendingPathComponent("payload/bin/tool"))
          == Data("tool".utf8))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      #expect(
        try Data(contentsOf: result.versionURL.appendingPathComponent("install.json"))
          == encoder.encode(result.record))
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
      #expect(try permissions(root.appendingPathComponent(".publish.lock")) == 0o600)
      #expect(
        !FileManager.default.fileExists(atPath: root.appendingPathComponent("current.json").path))

      let rootDevice = try device(root)
      #expect(try device(root.appendingPathComponent(".staging")) == rootDevice)
      #expect(try device(result.versionURL) == rootDevice)
    }
  }

  @Test
  func persistentBusyLockFailsBeforeCreatingTransaction() throws {
    try withPrivateRoot { root in
      let lockURL = root.appendingPathComponent(".publish.lock")
      let lockDescriptor = open(
        lockURL.path,
        O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
      )
      guard lockDescriptor >= 0 else { throw currentStoreTestPOSIXError() }
      defer {
        _ = flock(lockDescriptor, LOCK_UN)
        _ = close(lockDescriptor)
      }
      guard fchmod(lockDescriptor, S_IRUSR | S_IWUSR) == 0,
        flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0
      else {
        throw currentStoreTestPOSIXError()
      }
      let fixture = try makeFixture()

      #expect(throws: VersionedRuntimeStoreError.publisherBusy) {
        try VersionedRuntimeStore(rootURL: root).install(
          runtime: fixture.runtime,
          plan: fixture.plan,
          source: fixture.source()
        )
      }
      #expect(FileManager.default.fileExists(atPath: lockURL.path))
      #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".staging").path))
    }
  }

  @Test
  func rejectsUnsafeAndSymlinkRuntimeRoots() throws {
    let fixture = try makeFixture()
    try withPrivateRoot { root in
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
      #expect(throws: VersionedRuntimeStoreError.unsafeRuntimeRoot) {
        try VersionedRuntimeStore(rootURL: root).install(
          runtime: fixture.runtime,
          plan: fixture.plan,
          source: fixture.source()
        )
      }
    }
    try withPrivateRoot { parent in
      let actual = parent.appendingPathComponent("actual")
      try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: actual.path)
      let link = parent.appendingPathComponent("linked-root")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
      #expect(throws: VersionedRuntimeStoreError.unsafeRuntimeRoot) {
        try VersionedRuntimeStore(rootURL: link).install(
          runtime: fixture.runtime,
          plan: fixture.plan,
          source: fixture.source()
        )
      }
    }
  }

  @Test
  func extractionFailureAndCancellationCleanOnlyTransactionWrapper() async throws {
    try await withPrivateRootAsync { root in
      let fixture = try makeFixture()
      let failing = fixture.source(readerFactory: { StoreThrowingReader() })
      #expect(throws: StoreTestError.readerFailed) {
        try VersionedRuntimeStore(rootURL: root).install(
          runtime: fixture.runtime,
          plan: fixture.plan,
          source: failing
        )
      }
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
      #expect(
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".publish.lock").path))

      let task = Task {
        try VersionedRuntimeStore(rootURL: root).install(
          runtime: fixture.runtime,
          plan: fixture.plan,
          source: fixture.source(readerFactory: { StoreCancellingReader() })
        )
      }
      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }
  }

  @Test
  func exactExistingVersionIsReused() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let first = try store.install(
        runtime: fixture.runtime,
        plan: fixture.plan,
        source: fixture.source()
      )
      let receiptURL = first.versionURL.appendingPathComponent("install.json")
      let originalReceipt = try Data(contentsOf: receiptURL)

      let second = try store.install(
        runtime: fixture.runtime,
        plan: fixture.plan,
        source: fixture.source()
      )
      #expect(second.disposition == .reusedExisting)
      #expect(second.versionURL == first.versionURL)
      #expect(try Data(contentsOf: receiptURL) == originalReceipt)
      #expect(
        try Data(contentsOf: first.versionURL.appendingPathComponent("payload/bin/tool"))
          == Data("tool".utf8))
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }
  }

  @Test
  func sameSizeReceiptAndPayloadTamperingFailClosed() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let first = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let receipt = first.versionURL.appendingPathComponent("install.json")
      var damagedReceipt = try Data(contentsOf: receipt)
      damagedReceipt[0] ^= 1
      try overwriteStoreFile(receipt, with: damagedReceipt)

      try expectCorrupt(store, fixture: fixture, installID: first.record.installID)
      #expect(try Data(contentsOf: receipt) == damagedReceipt)
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let first = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let payload = first.versionURL.appendingPathComponent("payload/bin/tool")
      try overwriteStoreFile(payload, with: Data("evil".utf8))

      try expectCorrupt(store, fixture: fixture, installID: first.record.installID)
      #expect(try Data(contentsOf: payload) == Data("evil".utf8))
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }
  }

  @Test
  func extraEntryAndSymlinkFailClosed() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let first = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let extra = first.versionURL.appendingPathComponent("extra")
      try Data([1]).write(to: extra)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: extra.path)

      try expectCorrupt(store, fixture: fixture, installID: first.record.installID)
      #expect(FileManager.default.fileExists(atPath: extra.path))
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let first = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let receipt = first.versionURL.appendingPathComponent("install.json")
      let outside = root.appendingPathComponent("outside")
      try Data("outside".utf8).write(to: outside)
      guard unlink(receipt.path) == 0 else { throw currentStoreTestPOSIXError() }
      try FileManager.default.createSymbolicLink(at: receipt, withDestinationURL: outside)

      try expectCorrupt(store, fixture: fixture, installID: first.record.installID)
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: receipt.path) == outside.path)
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }
  }

  @Test
  func unsafeExistingTargetFailsClosed() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let first = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: first.versionURL.path
      )

      try expectCorrupt(store, fixture: fixture, installID: first.record.installID)
      #expect(try permissions(first.versionURL) == 0o755)
      #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
    }
  }

  @Test
  func postRenameFailureReportsVisibleVersionAndDoesNotCleanIt() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(
        rootURL: root,
        postRenameHook: {
          throw StoreTestError.postRenameFailed
        })

      do {
        _ = try store.install(
          runtime: fixture.runtime,
          plan: fixture.plan,
          source: fixture.source()
        )
        Issue.record("Expected post-rename failure")
      } catch let error as VersionedRuntimeCommittedError {
        guard case .versionVisible(let installID, let durabilityConfirmed) = error.state else {
          Issue.record("Unexpected commit state")
          return
        }
        #expect(durabilityConfirmed)
        #expect(error.underlyingError as? StoreTestError == .postRenameFailed)
        let version =
          root
          .appendingPathComponent("versions")
          .appendingPathComponent(String(installID.prefix(2)))
          .appendingPathComponent(installID)
        #expect(FileManager.default.fileExists(atPath: version.path))
        #expect(try directoryNames(root.appendingPathComponent(".staging")).isEmpty)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  @Test
  func newStoreReopensExactInstalledRuntime() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime,
        plan: fixture.plan,
        source: fixture.source()
      )
      let catalog = try activationInputs(for: fixture.runtime).catalog

      let reopened = try VersionedRuntimeStore(rootURL: root).reopenInstalled(
        installID: installed.record.installID,
        in: catalog
      )
      #expect(reopened.disposition == .reopenedExisting)
      #expect(reopened.versionURL == installed.versionURL)
      #expect(reopened.record == installed.record)
    }
  }

  @Test
  func reopenRejectsReceiptAndPayloadTampering() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let catalog = try activationInputs(for: fixture.runtime).catalog
      let receipt = installed.versionURL.appendingPathComponent("install.json")
      var damaged = try Data(contentsOf: receipt)
      damaged[damaged.count / 2] ^= 1
      try overwriteStoreFile(receipt, with: damaged)
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installed.record.installID))
      {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(
          installID: installed.record.installID, in: catalog)
      }
      #expect(try Data(contentsOf: receipt) == damaged)
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let catalog = try activationInputs(for: fixture.runtime).catalog
      let payload = installed.versionURL.appendingPathComponent("payload/bin/tool")
      try overwriteStoreFile(payload, with: Data("evil".utf8))
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installed.record.installID))
      {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(
          installID: installed.record.installID, in: catalog)
      }
      #expect(try Data(contentsOf: payload) == Data("evil".utf8))
    }
  }

  @Test
  func reopenRejectsUnknownRevokedAndChangedRuntimeIdentity() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let other = CatalogTestFixtures.runtime(id: "runtime-other")
      let unknown = CatalogTestFixtures.verifiedCatalog(
        CatalogTestFixtures.catalog(runtimes: [other], profiles: []))
      #expect(throws: VersionedRuntimeStoreError.untrustedRuntime(fixture.runtime.id)) {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(
          installID: installed.record.installID, in: unknown)
      }

      let trusted = try activationInputs(for: fixture.runtime).catalog
      let revokedCatalog = copyCatalog(
        trusted.catalog,
        runtimes: trusted.catalog.runtimes,
        revocations: .init(runtimeIDs: [fixture.runtime.id])
      )
      let revoked = VerifiedCatalog(
        catalog: revokedCatalog,
        payloadSHA256: trusted.payloadSHA256
      )
      #expect(throws: VersionedRuntimeStoreError.untrustedRuntime(fixture.runtime.id)) {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(
          installID: installed.record.installID, in: revoked)
      }

      let changed = RuntimeDefinition(
        id: fixture.runtime.id, backend: fixture.runtime.backend,
        version: "changed", verification: fixture.runtime.verification,
        acquisition: fixture.runtime.acquisition, sourceURL: fixture.runtime.sourceURL,
        byteSize: fixture.runtime.byteSize, sha256: fixture.runtime.sha256,
        license: fixture.runtime.license, redistributable: fixture.runtime.redistributable)
      let changedCatalog = CatalogTestFixtures.verifiedCatalog(
        CatalogTestFixtures.catalog(runtimes: [changed], profiles: []))
      #expect(throws: VersionedRuntimeStoreError.untrustedRuntime(fixture.runtime.id)) {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(
          installID: installed.record.installID, in: changedCatalog)
      }
      #expect(FileManager.default.fileExists(atPath: installed.versionURL.path))
    }
  }

  @Test
  func reopenRejectsInvalidIDTargetSymlinkAndNoncanonicalReceipt() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let catalog = try activationInputs(for: fixture.runtime).catalog
      #expect(throws: VersionedRuntimeStoreError.invalidInstallID) {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(installID: "bad", in: catalog)
      }
      #expect(throws: VersionedRuntimeStoreError.invalidInstallID) {
        try VersionedRuntimeStore(rootURL: root).reopenInstalled(
          installID: String(repeating: "A", count: 64), in: catalog)
      }
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let catalog = try activationInputs(for: fixture.runtime).catalog
      let moved = installed.versionURL.deletingLastPathComponent().appendingPathComponent("moved")
      try FileManager.default.moveItem(at: installed.versionURL, to: moved)
      try FileManager.default.createSymbolicLink(
        at: installed.versionURL, withDestinationURL: moved)
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installed.record.installID))
      {
        try store.reopenInstalled(installID: installed.record.installID, in: catalog)
      }
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: installed.versionURL.path)
          == moved.path)
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let catalog = try activationInputs(for: fixture.runtime).catalog
      let receipt = installed.versionURL.appendingPathComponent("install.json")
      var noncanonical = Data([0x20])
      noncanonical.append(try Data(contentsOf: receipt))
      try overwriteStoreFile(receipt, with: noncanonical)
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installed.record.installID))
      {
        try store.reopenInstalled(installID: installed.record.installID, in: catalog)
      }
      #expect(try Data(contentsOf: receipt) == noncanonical)
    }
  }
}
