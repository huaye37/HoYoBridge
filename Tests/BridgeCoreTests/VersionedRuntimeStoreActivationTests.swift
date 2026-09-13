import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

extension VersionedRuntimeStoreTests {
  @Test
  func firstActivationPublishesExactCurrentRecord() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)

      let record = try store.activateFirst(
        installed: installed,
        verifiedCatalog: activation.catalog,
        request: activation.request
      )
      let current = root.appendingPathComponent("current.json")
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      #expect(record.generation == 1)
      #expect(record.selectionMode == .standard)
      #expect(try Data(contentsOf: current) == encoder.encode(record))
      #expect(try permissions(current) == 0o600)
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }
  }

  @Test
  func activationRejectsTamperedOrArbitraryInstalledVersion() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      try overwriteStoreFile(
        installed.versionURL.appendingPathComponent("payload/bin/tool"),
        with: Data("evil".utf8)
      )
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installed.record.installID))
      {
        try store.activateFirst(
          installed: installed,
          verifiedCatalog: activation.catalog,
          request: activation.request
        )
      }
      #expect(
        !FileManager.default.fileExists(atPath: root.appendingPathComponent("current.json").path))
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let arbitrary = InstalledRuntimeVersion(
        versionURL:
          root
          .appendingPathComponent("elsewhere")
          .appendingPathComponent(installed.record.installID),
        record: installed.record,
        disposition: installed.disposition
      )
      let activation = try activationInputs(for: fixture.runtime)
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installed.record.installID))
      {
        try store.activateFirst(
          installed: arbitrary,
          verifiedCatalog: activation.catalog,
          request: activation.request
        )
      }
    }
  }

  @Test
  func existingCurrentFileSymlinkOrDirectoryIsNeverReplaced() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      let current = root.appendingPathComponent("current.json")
      try Data("keep".utf8).write(to: current)
      #expect(throws: VersionedRuntimeStoreError.currentAlreadyExists) {
        try store.activateFirst(
          installed: installed, verifiedCatalog: activation.catalog, request: activation.request)
      }
      #expect(try Data(contentsOf: current) == Data("keep".utf8))
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      let outside = root.appendingPathComponent("outside")
      try Data("keep".utf8).write(to: outside)
      let current = root.appendingPathComponent("current.json")
      try FileManager.default.createSymbolicLink(at: current, withDestinationURL: outside)
      #expect(throws: VersionedRuntimeStoreError.currentAlreadyExists) {
        try store.activateFirst(
          installed: installed, verifiedCatalog: activation.catalog, request: activation.request)
      }
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: current.path) == outside.path)
    }

    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      let current = root.appendingPathComponent("current.json")
      try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
      #expect(throws: VersionedRuntimeStoreError.currentAlreadyExists) {
        try store.activateFirst(
          installed: installed, verifiedCatalog: activation.catalog, request: activation.request)
      }
      #expect(
        try FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType
          == .typeDirectory)
    }
  }

  @Test
  func cancelledFirstActivationCleansTemporaryFile() async throws {
    try await withPrivateRootAsync { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      let store = VersionedRuntimeStore(
        rootURL: root,
        preCurrentCommitHook: {
          withUnsafeCurrentTask { $0?.cancel() }
        })
      let task = Task {
        try store.activateFirst(
          installed: installed,
          verifiedCatalog: activation.catalog,
          request: activation.request
        )
      }
      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(
        !FileManager.default.fileExists(atPath: root.appendingPathComponent("current.json").path))
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }
  }

  @Test
  func postCommitActivationFailureReportsDurableCurrent() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      let store = VersionedRuntimeStore(
        rootURL: root,
        postRenameHook: {
          throw StoreTestError.postRenameFailed
        })
      do {
        _ = try store.activateFirst(
          installed: installed,
          verifiedCatalog: activation.catalog,
          request: activation.request
        )
        Issue.record("Expected committed activation error")
      } catch let error as VersionedRuntimeCommittedError {
        guard case .currentVisible(let activationID, let durable) = error.state else {
          Issue.record("Unexpected state")
          return
        }
        #expect(durable)
        #expect(
          FileManager.default.fileExists(atPath: root.appendingPathComponent("current.json").path))
        #expect(activationID.count == 64)
      }
    }
  }

  @Test
  func replacingCurrentAdvancesGenerationAndRemovesOldTemporary() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let second = try active.store.activateReplacingCurrent(
        installed: active.installed,
        verifiedCatalog: active.activation.catalog,
        request: active.activation.request,
        expectedCurrent: active.current
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      #expect(second.generation == 2)
      #expect(
        try Data(contentsOf: root.appendingPathComponent("current.json")) == encoder.encode(second))
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }
  }

  @Test
  func staleExpectedAndSameSizeCurrentTamperFailCAS() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let second = try active.store.activateReplacingCurrent(
        installed: active.installed,
        verifiedCatalog: active.activation.catalog,
        request: active.activation.request,
        expectedCurrent: active.current
      )
      let currentURL = root.appendingPathComponent("current.json")
      let unchanged = try Data(contentsOf: currentURL)
      #expect(throws: VersionedRuntimeStoreError.currentChanged) {
        try active.store.activateReplacingCurrent(
          installed: active.installed,
          verifiedCatalog: active.activation.catalog,
          request: active.activation.request,
          expectedCurrent: active.current
        )
      }
      #expect(second.generation == 2)
      #expect(try Data(contentsOf: currentURL) == unchanged)
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }

    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let currentURL = root.appendingPathComponent("current.json")
      var damaged = try Data(contentsOf: currentURL)
      damaged[damaged.count / 2] ^= 1
      try overwriteStoreFile(currentURL, with: damaged)
      #expect(throws: VersionedRuntimeStoreError.currentChanged) {
        try active.store.activateReplacingCurrent(
          installed: active.installed,
          verifiedCatalog: active.activation.catalog,
          request: active.activation.request,
          expectedCurrent: active.current
        )
      }
      #expect(try Data(contentsOf: currentURL) == damaged)
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }
  }

  @Test
  func abnormalCurrentEntryFailsClosedDuringReplace() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let currentURL = root.appendingPathComponent("current.json")
      let outside = root.appendingPathComponent("outside-current")
      try Data("keep".utf8).write(to: outside)
      guard unlink(currentURL.path) == 0 else { throw currentStoreTestPOSIXError() }
      try FileManager.default.createSymbolicLink(at: currentURL, withDestinationURL: outside)
      #expect(throws: VersionedRuntimeStoreError.unsafeStoreEntry) {
        try active.store.activateReplacingCurrent(
          installed: active.installed,
          verifiedCatalog: active.activation.catalog,
          request: active.activation.request,
          expectedCurrent: active.current
        )
      }
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: currentURL.path) == outside.path)
    }
  }

  @Test
  func cancelledReplaceCleansNewTemporaryAndKeepsCurrent() async throws {
    try await withPrivateRootAsync { root in
      let active = try prepareFirstActivation(in: root)
      let currentURL = root.appendingPathComponent("current.json")
      let before = try Data(contentsOf: currentURL)
      let store = VersionedRuntimeStore(
        rootURL: root,
        preCurrentCommitHook: {
          withUnsafeCurrentTask { $0?.cancel() }
        })
      let task = Task {
        try store.activateReplacingCurrent(
          installed: active.installed,
          verifiedCatalog: active.activation.catalog,
          request: active.activation.request,
          expectedCurrent: active.current
        )
      }
      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(try Data(contentsOf: currentURL) == before)
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }
  }

  @Test
  func postSwapFailureReportsDurableCurrentAndPreservesOldTemporary() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let store = VersionedRuntimeStore(
        rootURL: root,
        postRenameHook: {
          throw StoreTestError.postRenameFailed
        })
      do {
        _ = try store.activateReplacingCurrent(
          installed: active.installed,
          verifiedCatalog: active.activation.catalog,
          request: active.activation.request,
          expectedCurrent: active.current
        )
        Issue.record("Expected post-swap failure")
      } catch let error as VersionedRuntimeCommittedError {
        guard case .currentVisible(_, let durable) = error.state else {
          Issue.record("Unexpected state")
          return
        }
        #expect(durable)
        #expect(
          FileManager.default.fileExists(atPath: root.appendingPathComponent("current.json").path))
        #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.count == 1)
      }
    }
  }

  @Test
  func explicitRollbackReactivatesPriorProfileWithMonotonicGeneration() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: fixture.runtime,
        plan: fixture.plan,
        source: fixture.source()
      )
      let profileA = CatalogTestFixtures.standardProfile(
        id: "profile-a",
        runtime: fixture.runtime
      )
      let profileB = CatalogTestFixtures.standardProfile(
        id: "profile-b",
        runtime: fixture.runtime
      )
      let catalog = CatalogTestFixtures.verifiedCatalog(
        CatalogTestFixtures.catalog(
          runtimes: [fixture.runtime],
          profiles: [profileA, profileB]
        )
      )
      let requestA = CatalogTestFixtures.request(
        mode: .standard,
        preferredProfileID: profileA.id
      )
      let requestB = CatalogTestFixtures.request(
        mode: .standard,
        preferredProfileID: profileB.id
      )

      let first = try store.activateFirst(
        installed: installed,
        verifiedCatalog: catalog,
        request: requestA
      )
      let second = try store.activateReplacingCurrent(
        installed: installed,
        verifiedCatalog: catalog,
        request: requestB,
        expectedCurrent: first
      )
      let rolledBack = try store.rollbackCurrent(
        to: installed,
        verifiedCatalog: catalog,
        request: requestA,
        replacing: second
      )

      #expect(first.generation == 1)
      #expect(second.generation == 2)
      #expect(rolledBack.generation == 3)
      #expect(first.profileID == profileA.id)
      #expect(second.profileID == profileB.id)
      #expect(rolledBack.profileID == profileA.id)
      #expect(first.activationID != second.activationID)
      #expect(first.activationID != rolledBack.activationID)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      #expect(
        try Data(contentsOf: root.appendingPathComponent("current.json"))
          == encoder.encode(rolledBack)
      )
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
      #expect(FileManager.default.fileExists(atPath: installed.versionURL.path))

      #expect(throws: VersionedRuntimeStoreError.currentChanged) {
        try store.rollbackCurrent(
          to: installed,
          verifiedCatalog: catalog,
          request: requestA,
          replacing: second
        )
      }
    }
  }

  @Test
  func newStoreResolvesCurrentThroughLatestCatalog() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let resolved = try VersionedRuntimeStore(rootURL: root).resolveCurrent(
        in: active.activation.catalog,
        request: active.activation.request
      )
      #expect(resolved.current == active.current)
      #expect(resolved.installed.record == active.installed.record)
      #expect(resolved.installed.disposition == .reopenedExisting)
      #expect(resolved.decision.profile.id == active.current.profileID)
      #expect(resolved.decision.runtime.id == active.current.runtimeID)
    }
  }

  @Test
  func resolvedCapabilitiesDriveNextCASAfterRestart() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let reopenedStore = VersionedRuntimeStore(rootURL: root)
      let resolved = try reopenedStore.resolveCurrent(
        in: active.activation.catalog,
        request: active.activation.request
      )
      let second = try reopenedStore.activateReplacingCurrent(
        installed: resolved.installed,
        verifiedCatalog: active.activation.catalog,
        request: active.activation.request,
        expectedCurrent: resolved.current
      )
      let resolvedAgain = try VersionedRuntimeStore(rootURL: root).resolveCurrent(
        in: active.activation.catalog,
        request: active.activation.request
      )

      #expect(second.generation == 2)
      #expect(resolvedAgain.current == second)
      #expect(resolvedAgain.installed.record == resolved.installed.record)
      #expect(try directoryNames(root).filter { $0.hasPrefix(".current.") }.isEmpty)
    }
  }

  @Test
  func resolveRejectsMissingNoncanonicalTamperedAndSymlinkCurrent() throws {
    try withPrivateRoot { root in
      let fixture = try makeFixture()
      let installed = try VersionedRuntimeStore(rootURL: root).install(
        runtime: fixture.runtime, plan: fixture.plan, source: fixture.source())
      let activation = try activationInputs(for: fixture.runtime)
      #expect(throws: VersionedRuntimeStoreError.currentMissing) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: activation.catalog, request: activation.request)
      }
      #expect(FileManager.default.fileExists(atPath: installed.versionURL.path))
    }

    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let current = root.appendingPathComponent("current.json")
      var noncanonical = Data([0x20])
      noncanonical.append(try Data(contentsOf: current))
      try overwriteStoreFile(current, with: noncanonical)
      #expect(throws: VersionedRuntimeStoreError.currentInvalid) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: active.activation.catalog, request: active.activation.request)
      }
    }

    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let current = root.appendingPathComponent("current.json")
      var damaged = try Data(contentsOf: current)
      damaged[damaged.count / 2] ^= 1
      try overwriteStoreFile(current, with: damaged)
      #expect(throws: VersionedRuntimeStoreError.currentInvalid) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: active.activation.catalog, request: active.activation.request)
      }
    }

    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let current = root.appendingPathComponent("current.json")
      let outside = root.appendingPathComponent("outside-resolve")
      try Data("outside".utf8).write(to: outside)
      guard unlink(current.path) == 0 else { throw currentStoreTestPOSIXError() }
      try FileManager.default.createSymbolicLink(at: current, withDestinationURL: outside)
      #expect(throws: VersionedRuntimeStoreError.currentInvalid) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: active.activation.catalog, request: active.activation.request)
      }
    }
  }

  @Test
  func resolveRejectsChangedCatalogProfileAndRevokedRuntime() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let changedPayload = VerifiedCatalog(
        catalog: active.activation.catalog.catalog,
        payloadSHA256: String(repeating: "f", count: 64)
      )
      #expect(throws: VersionedRuntimeStoreError.currentNotAuthorized) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: changedPayload, request: active.activation.request)
      }

      let originalProfile = try #require(active.activation.catalog.catalog.profiles.first)
      let changedProfile = CompatibilityProfile(
        id: originalProfile.id, revision: originalProfile.revision + 1,
        gameID: originalProfile.gameID, gameVersion: originalProfile.gameVersion,
        gameBuildFingerprint: originalProfile.gameBuildFingerprint,
        macOS: originalProfile.macOS, architectures: originalProfile.architectures,
        requiredMetalFamilies: originalProfile.requiredMetalFamilies,
        requiresRosetta: originalProfile.requiresRosetta, tier: originalProfile.tier,
        verification: originalProfile.verification, runtimeID: originalProfile.runtimeID,
        priority: originalProfile.priority, launchArguments: ["--changed"],
        environment: originalProfile.environment, disclosures: originalProfile.disclosures,
        verificationRecords: originalProfile.verificationRecords
      )
      let changedCatalog = copyCatalog(
        active.activation.catalog.catalog,
        runtimes: active.activation.catalog.catalog.runtimes,
        profiles: [changedProfile]
      )
      #expect(throws: VersionedRuntimeStoreError.currentNotAuthorized) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: VerifiedCatalog(
            catalog: changedCatalog,
            payloadSHA256: active.activation.catalog.payloadSHA256
          ),
          request: active.activation.request
        )
      }

      let revoked = copyCatalog(
        active.activation.catalog.catalog,
        runtimes: active.activation.catalog.catalog.runtimes,
        profiles: active.activation.catalog.catalog.profiles,
        revocations: .init(runtimeIDs: [active.installed.record.runtimeID])
      )
      #expect(
        throws: VersionedRuntimeStoreError.untrustedRuntime(active.installed.record.runtimeID)
      ) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: VerifiedCatalog(
            catalog: revoked,
            payloadSHA256: active.activation.catalog.payloadSHA256
          ),
          request: active.activation.request
        )
      }
    }
  }

  @Test
  func resolveExperimentalCurrentRequiresAcknowledgementAgain() throws {
    try withPrivateRoot { root in
      let runtime = RuntimeDefinition(
        id: "runtime-experimental", backend: .dxmt, version: "1.0.0",
        verification: .candidate, acquisition: .managedDownload,
        sourceURL: "https://example.invalid/runtime.zip", byteSize: 20,
        sha256: artifactSHA256, license: "MIT", redistributable: true)
      let fixture = try makeFixture(runtime: runtime)
      let store = VersionedRuntimeStore(rootURL: root)
      let installed = try store.install(
        runtime: runtime, plan: fixture.plan, source: fixture.source())
      let profile = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
      let catalog = CatalogTestFixtures.verifiedCatalog(
        CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile]))
      let acknowledgement = CompatibilitySelector.acknowledgement(for: profile, in: catalog)
      let accepted = CatalogTestFixtures.request(
        mode: .experimental, preferredProfileID: profile.id,
        acknowledgements: [acknowledgement])
      _ = try store.activateFirst(
        installed: installed, verifiedCatalog: catalog, request: accepted)

      #expect(
        throws: CompatibilitySelectionError.acknowledgementRequired(
          acknowledgement, disclosures: profile.disclosures)
      ) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: catalog,
          request: CatalogTestFixtures.request(
            mode: .experimental, preferredProfileID: profile.id)
        )
      }
    }
  }

  @Test
  func resolveRejectsTamperedPayloadAndWrongInstallReference() throws {
    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      try overwriteStoreFile(
        active.installed.versionURL.appendingPathComponent("payload/bin/tool"),
        with: Data("evil".utf8))
      #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(active.current.installID)) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: active.activation.catalog, request: active.activation.request)
      }
    }

    try withPrivateRoot { root in
      let active = try prepareFirstActivation(in: root)
      let wrong = activationReplacingInstallID(
        active.current,
        installID: String(repeating: "0", count: 64)
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try overwriteStoreFile(
        root.appendingPathComponent("current.json"),
        with: encoder.encode(wrong)
      )
      #expect(throws: (any Error).self) {
        try VersionedRuntimeStore(rootURL: root).resolveCurrent(
          in: active.activation.catalog, request: active.activation.request)
      }
    }
  }

}
