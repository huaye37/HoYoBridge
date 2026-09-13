import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct RuntimeActivationIdentityTests {
  @Test
  func buildsStandardKnownVector() throws {
    let fixture = try makeStandardFixture()
    let record = try RuntimeActivationIdentityBuilder.build(
      installed: fixture.installed,
      verifiedCatalog: fixture.verifiedCatalog,
      request: fixture.request,
      generation: 7
    )

    #expect(record.schemaVersion == 1)
    #expect(record.generation == 7)
    #expect(record.compatibilityTier == .standard)
    #expect(record.selectionMode == .standard)
    #expect(record.acknowledgementSHA256 == nil)
    #expect(
      record.activationID == "7ea11fd2e406bf076d5bfb90f10956a26388e7fee124d69e87fb53e99b478f39")
  }

  @Test
  func experimentalSelectionRequiresExactAcknowledgement() throws {
    let runtime = CatalogTestFixtures.runtime(
      id: "runtime-candidate",
      verification: .candidate
    )
    let profile = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    let verified = VerifiedCatalog(
      catalog: catalog,
      payloadSHA256: String(repeating: "e", count: 64)
    )
    let installed = try makeInstalled(runtime: runtime)
    let required = CompatibilitySelector.acknowledgement(for: profile, in: verified)
    let missing = CatalogTestFixtures.request(
      mode: .experimental,
      preferredProfileID: profile.id
    )
    #expect(
      throws: CompatibilitySelectionError.acknowledgementRequired(
        required,
        disclosures: profile.disclosures
      )
    ) {
      try RuntimeActivationIdentityBuilder.build(
        installed: installed,
        verifiedCatalog: verified,
        request: missing,
        generation: 1
      )
    }

    let accepted = try RuntimeActivationIdentityBuilder.build(
      installed: installed,
      verifiedCatalog: verified,
      request: CatalogTestFixtures.request(
        mode: .experimental,
        preferredProfileID: profile.id,
        acknowledgements: [required]
      ),
      generation: 1
    )
    #expect(accepted.compatibilityTier == .experimental)
    #expect(accepted.acknowledgementSHA256 != nil)

    let changedPayload = VerifiedCatalog(
      catalog: catalog,
      payloadSHA256: String(repeating: "f", count: 64)
    )
    #expect(throws: CompatibilitySelectionError.self) {
      try RuntimeActivationIdentityBuilder.build(
        installed: installed,
        verifiedCatalog: changedPayload,
        request: CatalogTestFixtures.request(
          mode: .experimental,
          preferredProfileID: profile.id,
          acknowledgements: [required]
        ),
        generation: 2
      )
    }

    let changedProfile = CatalogTestFixtures.experimentalProfile(
      revision: 2,
      runtimeID: runtime.id,
      disclosureImpact: "Changed risk requires a new acknowledgement."
    )
    let changedCatalog = CatalogTestFixtures.catalog(
      revision: 11,
      runtimes: [runtime],
      profiles: [changedProfile]
    )
    let changedVerified = VerifiedCatalog(
      catalog: changedCatalog,
      payloadSHA256: verified.payloadSHA256
    )
    let changedRequired = CompatibilitySelector.acknowledgement(
      for: changedProfile,
      in: changedVerified
    )
    #expect(
      throws: CompatibilitySelectionError.acknowledgementRequired(
        changedRequired,
        disclosures: changedProfile.disclosures
      )
    ) {
      try RuntimeActivationIdentityBuilder.build(
        installed: installed,
        verifiedCatalog: changedVerified,
        request: CatalogTestFixtures.request(
          mode: .experimental,
          preferredProfileID: changedProfile.id,
          acknowledgements: [required]
        ),
        generation: 2
      )
    }
  }

  @Test
  func rejectsGenerationAndInstalledRuntimeMismatch() throws {
    let fixture = try makeStandardFixture()
    #expect(throws: RuntimeActivationIdentityError.invalidGeneration) {
      try RuntimeActivationIdentityBuilder.build(
        installed: fixture.installed,
        verifiedCatalog: fixture.verifiedCatalog,
        request: fixture.request,
        generation: 0
      )
    }

    let otherRuntime = CatalogTestFixtures.runtime(id: "runtime-other")
    let otherProfile = CatalogTestFixtures.standardProfile(runtime: otherRuntime)
    let otherCatalog = CatalogTestFixtures.catalog(
      runtimes: [otherRuntime],
      profiles: [otherProfile]
    )
    #expect(throws: RuntimeActivationIdentityError.installedRuntimeMismatch) {
      try RuntimeActivationIdentityBuilder.build(
        installed: fixture.installed,
        verifiedCatalog: VerifiedCatalog(
          catalog: otherCatalog,
          payloadSHA256: String(repeating: "d", count: 64)
        ),
        request: fixture.request,
        generation: 1
      )
    }
  }

  @Test
  func activationIDChangesWithGenerationModeAndEveryBoundDigestFamily() throws {
    let fixture = try makeStandardFixture()
    let base = try build(fixture, generation: 1)
    let generation = try build(fixture, generation: 2)
    let mode = try RuntimeActivationIdentityBuilder.build(
      installed: fixture.installed,
      verifiedCatalog: fixture.verifiedCatalog,
      request: CatalogTestFixtures.request(mode: .experimental),
      generation: 1
    )
    let payload = try RuntimeActivationIdentityBuilder.build(
      installed: fixture.installed,
      verifiedCatalog: VerifiedCatalog(
        catalog: fixture.verifiedCatalog.catalog,
        payloadSHA256: String(repeating: "e", count: 64)
      ),
      request: fixture.request,
      generation: 1
    )
    let changedTree = try makeInstalled(
      runtime: fixture.runtime,
      content: Data("fool".utf8)
    )
    let tree = try RuntimeActivationIdentityBuilder.build(
      installed: changedTree,
      verifiedCatalog: fixture.verifiedCatalog,
      request: fixture.request,
      generation: 1
    )
    let uppercaseProfile = copiedProfile(
      fixture.profile,
      gameBuildFingerprint: fixture.profile.gameBuildFingerprint.uppercased()
    )
    let uppercaseCatalog = CatalogTestFixtures.catalog(
      runtimes: [fixture.runtime],
      profiles: [uppercaseProfile]
    )
    let uppercase = try RuntimeActivationIdentityBuilder.build(
      installed: fixture.installed,
      verifiedCatalog: VerifiedCatalog(
        catalog: uppercaseCatalog,
        payloadSHA256: fixture.verifiedCatalog.payloadSHA256
      ),
      request: request(for: uppercaseProfile, mode: .standard),
      generation: 1
    )
    #expect(uppercase.gameBuildFingerprint == fixture.profile.gameBuildFingerprint)

    let values = [base, generation, mode, payload, tree, uppercase].map(\.activationID)
    #expect(Set(values).count == values.count)
  }

  private struct StandardFixture {
    let runtime: RuntimeDefinition
    let profile: CompatibilityProfile
    let verifiedCatalog: VerifiedCatalog
    let request: CompatibilityRequest
    let installed: InstalledRuntimeVersion
  }

  private func makeStandardFixture() throws -> StandardFixture {
    let runtime = CatalogTestFixtures.runtime()
    let profile = CatalogTestFixtures.standardProfile(runtime: runtime)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    return StandardFixture(
      runtime: runtime,
      profile: profile,
      verifiedCatalog: VerifiedCatalog(
        catalog: catalog,
        payloadSHA256: String(repeating: "d", count: 64)
      ),
      request: CatalogTestFixtures.request(mode: .standard),
      installed: try makeInstalled(runtime: runtime)
    )
  }

  private func build(
    _ fixture: StandardFixture,
    generation: UInt64
  ) throws -> RuntimeActivationRecord {
    try RuntimeActivationIdentityBuilder.build(
      installed: fixture.installed,
      verifiedCatalog: fixture.verifiedCatalog,
      request: fixture.request,
      generation: generation
    )
  }

  private func makeInstalled(
    runtime: RuntimeDefinition,
    content: Data = Data("tool".utf8)
  ) throws -> InstalledRuntimeVersion {
    let descriptors = [
      ArchiveEntryDescriptor(
        path: "Bin/", kind: .directory, declaredSize: 0, permissions: 0o755),
      ArchiveEntryDescriptor(
        path: "Bin/Tool", kind: .regularFile, declaredSize: 4, permissions: 0o755),
    ]
    let plan = try SafeArchivePlanner.plan(
      entries: descriptors,
      archiveByteSize: try #require(runtime.byteSize)
    )
    let entries = [
      StagingTreeSealEntry(
        relativePath: "Bin", kind: .directory, size: 0, mode: 0o700,
        contentSHA256: nil),
      StagingTreeSealEntry(
        relativePath: "Bin/Tool", kind: .regularFile, size: 4, mode: 0o700,
        contentSHA256: sha256(content)),
    ]
    let candidate = ExtractedStagingTree(
      rootURL: URL(fileURLWithPath: "/private/tmp/unused"),
      regularFileCount: 1,
      totalBytes: 4,
      artifactSHA256: try #require(runtime.sha256?.lowercased()),
      planSHA256: plan.canonicalSHA256,
      planPolicyVersion: plan.policyVersion,
      treeSealVersion: SafeStagingTreeSealer.currentVersion,
      rootDevice: 1,
      rootInode: 2,
      entries: entries,
      treeSHA256: SafeStagingTreeSealer.canonicalSHA256(for: entries)
    )
    let record = try RuntimeInstallIdentityBuilder.build(
      runtime: runtime,
      plan: plan,
      candidate: candidate
    )
    let url = URL(fileURLWithPath: "/versions/\(record.installID.prefix(2))/\(record.installID)")
    return InstalledRuntimeVersion(versionURL: url, record: record, disposition: .published)
  }

  private func copiedProfile(
    _ profile: CompatibilityProfile,
    gameBuildFingerprint: String
  ) -> CompatibilityProfile {
    CompatibilityProfile(
      id: profile.id, revision: profile.revision, gameID: profile.gameID,
      gameVersion: profile.gameVersion, gameBuildFingerprint: gameBuildFingerprint,
      macOS: profile.macOS, architectures: profile.architectures,
      requiredMetalFamilies: profile.requiredMetalFamilies,
      requiresRosetta: profile.requiresRosetta, tier: profile.tier,
      verification: profile.verification, runtimeID: profile.runtimeID,
      priority: profile.priority, launchArguments: profile.launchArguments,
      environment: profile.environment, disclosures: profile.disclosures,
      verificationRecords: profile.verificationRecords
    )
  }

  private func request(
    for profile: CompatibilityProfile,
    mode: CompatibilityMode
  ) -> CompatibilityRequest {
    CompatibilityRequest(
      gameID: profile.gameID, gameVersion: profile.gameVersion,
      gameBuildFingerprint: profile.gameBuildFingerprint,
      macOSMajorVersion: 27, architecture: "arm64", metalFamilies: ["apple10"],
      rosettaAvailable: true, mode: mode
    )
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
