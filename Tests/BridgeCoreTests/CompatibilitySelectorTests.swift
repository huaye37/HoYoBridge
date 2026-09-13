import Testing

@testable import BridgeCore

struct CompatibilitySelectorTests {
  @Test
  func standardModeSelectsOnlyVerifiedStandardProfile() throws {
    let runtime = CatalogTestFixtures.runtime()
    let profile = CatalogTestFixtures.standardProfile(runtime: runtime)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])

    let decision = try CompatibilitySelector.select(
      from: CatalogTestFixtures.verifiedCatalog(catalog),
      request: CatalogTestFixtures.request(mode: .standard)
    )

    #expect(decision.profile.id == profile.id)
    #expect(!decision.usesExperimentalProfile)
  }

  @Test
  func experimentalCandidateRequiresModeExplicitChoiceAndExactAcknowledgement() throws {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-candidate", verification: .candidate)
    let profile = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    let verified = CatalogTestFixtures.verifiedCatalog(catalog)

    #expect(throws: CompatibilitySelectionError.experimentalModeRequired([profile.id])) {
      try CompatibilitySelector.select(
        from: verified, request: CatalogTestFixtures.request(mode: .standard))
    }
    #expect(throws: CompatibilitySelectionError.explicitExperimentalProfileRequired([profile.id])) {
      try CompatibilitySelector.select(
        from: verified, request: CatalogTestFixtures.request(mode: .experimental))
    }

    let acknowledgement = CompatibilitySelector.acknowledgement(for: profile, in: verified)
    #expect(
      throws: CompatibilitySelectionError.acknowledgementRequired(
        acknowledgement, disclosures: profile.disclosures)
    ) {
      try CompatibilitySelector.select(
        from: verified,
        request: CatalogTestFixtures.request(mode: .experimental, preferredProfileID: profile.id)
      )
    }

    let decision = try CompatibilitySelector.select(
      from: verified,
      request: CatalogTestFixtures.request(
        mode: .experimental,
        preferredProfileID: profile.id,
        acknowledgements: [acknowledgement]
      )
    )
    #expect(decision.profile.id == profile.id)
    #expect(decision.usesExperimentalProfile)
  }

  @Test
  func changedProfileInvalidatesOldAcknowledgement() {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-candidate", verification: .candidate)
    let original = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
    let originalCatalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [original])
    let originalVerified = CatalogTestFixtures.verifiedCatalog(originalCatalog)
    let oldAcknowledgement = CompatibilitySelector.acknowledgement(
      for: original, in: originalVerified)

    let changed = CatalogTestFixtures.experimentalProfile(
      revision: 2,
      runtimeID: runtime.id,
      disclosureImpact: "The updated configuration may corrupt its disposable Wine prefix."
    )
    let changedCatalog = CatalogTestFixtures.catalog(
      revision: 11, runtimes: [runtime], profiles: [changed])
    let changedVerified = CatalogTestFixtures.verifiedCatalog(changedCatalog)
    let required = CompatibilitySelector.acknowledgement(for: changed, in: changedVerified)

    #expect(
      throws: CompatibilitySelectionError.acknowledgementRequired(
        required, disclosures: changed.disclosures)
    ) {
      try CompatibilitySelector.select(
        from: changedVerified,
        request: CatalogTestFixtures.request(
          mode: .experimental,
          preferredProfileID: changed.id,
          acknowledgements: [oldAcknowledgement]
        )
      )
    }
  }

  @Test
  func blockedRuntimeCannotBeSelectedWithExplicitAcknowledgement() {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-blocked", verification: .blocked)
    let profile = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    let verified = CatalogTestFixtures.verifiedCatalog(catalog)
    let acknowledgement = CompatibilitySelector.acknowledgement(for: profile, in: verified)

    #expect(throws: CompatibilitySelectionError.preferredProfileIncompatible(profile.id)) {
      try CompatibilitySelector.select(
        from: verified,
        request: CatalogTestFixtures.request(
          mode: .experimental,
          preferredProfileID: profile.id,
          acknowledgements: [acknowledgement]
        )
      )
    }
  }

  @Test
  func equalPriorityStandardProfilesAreAmbiguous() {
    let runtime = CatalogTestFixtures.runtime()
    let first = CatalogTestFixtures.standardProfile(id: "profile-a", runtime: runtime)
    let second = CatalogTestFixtures.standardProfile(id: "profile-b", runtime: runtime)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [first, second])

    #expect(throws: CompatibilitySelectionError.ambiguousProfiles(["profile-a", "profile-b"])) {
      try CompatibilitySelector.select(
        from: CatalogTestFixtures.verifiedCatalog(catalog),
        request: CatalogTestFixtures.request(mode: .standard)
      )
    }
  }

  @Test
  func changedPayloadAtSameRevisionsInvalidatesOldAcknowledgement() {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-candidate", verification: .candidate)
    let original = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
    let originalCatalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [original])
    let originalVerified = CatalogTestFixtures.verifiedCatalog(originalCatalog)
    let oldAcknowledgement = CompatibilitySelector.acknowledgement(
      for: original,
      in: originalVerified
    )

    let changed = CompatibilityProfile(
      id: original.id,
      revision: original.revision,
      gameID: original.gameID,
      gameVersion: original.gameVersion,
      gameBuildFingerprint: original.gameBuildFingerprint,
      macOS: original.macOS,
      architectures: original.architectures,
      requiredMetalFamilies: original.requiredMetalFamilies,
      requiresRosetta: original.requiresRosetta,
      tier: original.tier,
      verification: original.verification,
      runtimeID: original.runtimeID,
      priority: original.priority,
      launchArguments: ["--changed-without-revision-bump"],
      environment: original.environment,
      disclosures: original.disclosures,
      verificationRecords: original.verificationRecords
    )
    let changedCatalog = CatalogTestFixtures.catalog(
      revision: originalCatalog.revision,
      runtimes: [runtime],
      profiles: [changed]
    )
    let changedVerified = CatalogTestFixtures.verifiedCatalog(changedCatalog)
    let required = CompatibilitySelector.acknowledgement(for: changed, in: changedVerified)

    #expect(oldAcknowledgement.catalogRevision == required.catalogRevision)
    #expect(oldAcknowledgement.profileRevision == required.profileRevision)
    #expect(oldAcknowledgement.disclosureDigest == required.disclosureDigest)
    #expect(oldAcknowledgement.catalogPayloadSHA256 != required.catalogPayloadSHA256)
    #expect(
      throws: CompatibilitySelectionError.acknowledgementRequired(
        required,
        disclosures: changed.disclosures
      )
    ) {
      try CompatibilitySelector.select(
        from: changedVerified,
        request: CatalogTestFixtures.request(
          mode: .experimental,
          preferredProfileID: changed.id,
          acknowledgements: [oldAcknowledgement]
        )
      )
    }
  }
}
