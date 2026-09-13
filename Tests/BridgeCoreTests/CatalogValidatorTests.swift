import Foundation
import Testing

@testable import BridgeCore

struct CatalogValidatorTests {
  @Test
  func acceptsCompleteStandardProfile() {
    let runtime = CatalogTestFixtures.runtime()
    let profile = CatalogTestFixtures.standardProfile(runtime: runtime)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])

    #expect(CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).isEmpty)
  }

  @Test
  func rejectsUnpinnedOrUnverifiableManagedDownload() {
    let runtime = RuntimeDefinition(
      id: "floating-runtime",
      backend: .dxmt,
      version: "latest",
      verification: .candidate,
      acquisition: .managedDownload,
      sourceURL: "http://downloads.example.invalid/latest/runtime.zip",
      license: "MIT",
      redistributable: false
    )
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [])
    let codes = Set(CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).map(\.code))

    #expect(codes.contains("floating-runtime-version"))
    #expect(codes.contains("invalid-source-url"))
    #expect(codes.contains("missing-download-size"))
    #expect(codes.contains("missing-download-hash"))
    #expect(codes.contains("download-not-redistributable"))
  }

  @Test
  func rejectsExperimentalProfileWithoutDisclosure() {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-candidate", verification: .candidate)
    let base = CatalogTestFixtures.experimentalProfile()
    let profile = CompatibilityProfile(
      id: base.id,
      revision: base.revision,
      gameID: base.gameID,
      gameVersion: base.gameVersion,
      gameBuildFingerprint: base.gameBuildFingerprint,
      macOS: base.macOS,
      architectures: base.architectures,
      requiredMetalFamilies: base.requiredMetalFamilies,
      requiresRosetta: base.requiresRosetta,
      tier: base.tier,
      verification: base.verification,
      runtimeID: base.runtimeID,
      disclosures: []
    )
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])

    #expect(
      CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).contains {
        $0.code == "missing-experimental-disclosure"
      })
  }

  @Test
  func rejectsExpiredCatalog() {
    let catalog = CatalogTestFixtures.catalog(
      expiresAt: Date(timeIntervalSince1970: 1_750_000_000),
      runtimes: [],
      profiles: []
    )

    #expect(
      CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).contains {
        $0.code == "expired-catalog"
      })
  }

  @Test
  func rejectsCatalogAtExactExpirationBoundary() {
    let catalog = CatalogTestFixtures.catalog(runtimes: [], profiles: [])

    #expect(
      CatalogValidator.issues(in: catalog, at: catalog.expiresAt).contains {
        $0.code == "expired-catalog"
      })
  }

  @Test
  func rejectsReverseMacOSRangeWithoutCrashing() {
    let runtime = CatalogTestFixtures.runtime()
    let base = CatalogTestFixtures.standardProfile(runtime: runtime)
    let profile = CompatibilityProfile(
      id: base.id,
      revision: base.revision,
      gameID: base.gameID,
      gameVersion: base.gameVersion,
      gameBuildFingerprint: base.gameBuildFingerprint,
      macOS: .init(minimumMajor: 27, maximumMajor: 26),
      architectures: base.architectures,
      requiredMetalFamilies: base.requiredMetalFamilies,
      requiresRosetta: base.requiresRosetta,
      tier: base.tier,
      verification: base.verification,
      runtimeID: base.runtimeID,
      priority: base.priority,
      verificationRecords: base.verificationRecords
    )
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])

    #expect(
      CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).contains {
        $0.code == "invalid-macos-range"
      })
  }

  @Test
  func rejectsOverflowingOrExcessivelyWideMacOSRangesWithoutEnumerating() {
    let runtime = CatalogTestFixtures.runtime()
    let ranges = [
      MacOSVersionRange(minimumMajor: Int.min, maximumMajor: 100),
      MacOSVersionRange(minimumMajor: 1, maximumMajor: 100),
      MacOSVersionRange(minimumMajor: 100, maximumMajor: Int.max),
    ]

    for (index, range) in ranges.enumerated() {
      let profile = CatalogTestFixtures.standardProfile(
        id: "profile-range-\(index)", runtime: runtime, macOS: range)
      let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])

      #expect(
        CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).contains {
          $0.code == "invalid-macos-range"
        })
    }
  }

  @Test
  func rejectsBlockedRuntimeAndWhitespaceDisclosure() {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-candidate", verification: .blocked)
    let base = CatalogTestFixtures.experimentalProfile(runtimeID: runtime.id)
    let profile = CompatibilityProfile(
      id: base.id,
      revision: base.revision,
      gameID: base.gameID,
      gameVersion: base.gameVersion,
      gameBuildFingerprint: base.gameBuildFingerprint,
      macOS: base.macOS,
      architectures: base.architectures,
      requiredMetalFamilies: base.requiredMetalFamilies,
      requiresRosetta: base.requiresRosetta,
      tier: base.tier,
      verification: base.verification,
      runtimeID: base.runtimeID,
      disclosures: [.init(id: "risk", impact: "   ", recovery: "\n")]
    )
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    let codes = Set(CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).map(\.code))

    #expect(codes.contains("blocked-runtime-reference"))
    #expect(codes.contains("incomplete-disclosure"))
  }

  @Test
  func rejectsBlankOrDuplicateDisclosureIDs() {
    let runtime = CatalogTestFixtures.runtime(id: "runtime-candidate", verification: .candidate)
    let profile = CatalogTestFixtures.experimentalProfile(
      runtimeID: runtime.id,
      disclosures: [
        .init(id: "risk", impact: "First impact", recovery: "First recovery"),
        .init(id: "risk", impact: "Second impact", recovery: "Second recovery"),
        .init(id: " \n ", impact: "Third impact", recovery: "Third recovery"),
      ])
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    let codes = Set(CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).map(\.code))

    #expect(codes.contains("duplicate-disclosure-id"))
    #expect(codes.contains("incomplete-disclosure"))
  }

  @Test
  func rejectsBlankInstalledRuntimeIdentity() {
    let runtime = RuntimeDefinition(
      id: "installed-runtime",
      backend: .gptkD3DMetal,
      version: "4.0",
      verification: .verified,
      acquisition: .detectOnly,
      installedRequirement: .init(
        teamIdentifier: "          ",
        exactVersion: " ",
        requiredPaths: [""]
      ),
      license: "Vendor license",
      redistributable: false
    )
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [])

    #expect(
      CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).contains {
        $0.code == "missing-installed-runtime-identity"
      })
  }

  @Test
  func acceptsCanonicalVerifiedInstalledRuntimeIdentity() {
    let requirement = InstalledRuntimeRequirement(
      teamIdentifier: "ABCDE12345",
      exactVersion: "4.0.0-beta.1",
      requiredPaths: [
        "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
      ])
    let runtime = installedRuntime(id: "installed-runtime", requirement: requirement)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [])

    #expect(CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).isEmpty)
  }

  @Test
  func rejectsNonCanonicalVerifiedInstalledRuntimeIdentity() {
    let validPath = "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
    let requirements = [
      InstalledRuntimeRequirement(
        teamIdentifier: " ABCDE12345", exactVersion: "4.0.0", requiredPaths: [validPath]),
      InstalledRuntimeRequirement(
        teamIdentifier: "abcde12345", exactVersion: "4.0.0", requiredPaths: [validPath]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: " 4.0.0", requiredPaths: [validPath]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: "4..0", requiredPaths: [validPath]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0", requiredPaths: ["relative/wine"]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0",
        requiredPaths: ["/Applications/Toolkit.app/Contents/../wine"]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0",
        requiredPaths: ["/Applications//Toolkit.app/Contents/wine"]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0",
        requiredPaths: ["/Applications/Toolkit.app/Contents/wine\u{0000}"]),
      InstalledRuntimeRequirement(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0",
        requiredPaths: ["\(validPath) "]),
    ]
    let runtimes = requirements.enumerated().map { index, requirement in
      installedRuntime(
        id: "installed-runtime-\(index)",
        acquisition: index.isMultiple(of: 2) ? .detectOnly : .userProvided,
        requirement: requirement)
    }
    let catalog = CatalogTestFixtures.catalog(runtimes: runtimes, profiles: [])
    let identityIssues = CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now)
      .filter { $0.code == "missing-installed-runtime-identity" }

    #expect(identityIssues.count == requirements.count)
  }

  @Test
  func runtimeDefinitionDigestSeparatesRequiredPathElements() {
    let splitPaths = installedRuntime(
      id: "installed-runtime",
      requirement: .init(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0",
        requiredPaths: ["/Applications/A", "/Applications/B"]))
    let delimiterInPath = installedRuntime(
      id: "installed-runtime",
      requirement: .init(
        teamIdentifier: "ABCDE12345", exactVersion: "4.0.0",
        requiredPaths: ["/Applications/A\nrequired-path:/Applications/B"]))

    #expect(splitPaths.definitionDigest != delimiterInPath.definitionDigest)
  }

  @Test
  func rejectsNonCanonicalOrOverflowingClientVersions() {
    let fullWidth = CatalogTestFixtures.catalog(
      minimumClientVersion: "１.０.０",
      runtimes: [],
      profiles: []
    )
    let leadingZero = CatalogTestFixtures.catalog(
      minimumClientVersion: "01.0.0",
      runtimes: [],
      profiles: []
    )
    let overflowing = CatalogTestFixtures.catalog(
      minimumClientVersion: "999999999999999999999.0",
      runtimes: [],
      profiles: []
    )

    #expect(
      CatalogValidator.issues(in: fullWidth, at: CatalogTestFixtures.now).contains {
        $0.code == "invalid-client-version"
      })
    #expect(
      CatalogValidator.issues(in: leadingZero, at: CatalogTestFixtures.now).contains {
        $0.code == "invalid-client-version"
      })
    #expect(
      CatalogValidator.issues(in: overflowing, at: CatalogTestFixtures.now).contains {
        $0.code == "invalid-client-version"
      })
  }

  @Test
  func changedStandardConfigurationInvalidatesVerificationRecord() {
    let runtime = CatalogTestFixtures.runtime()
    let base = CatalogTestFixtures.standardProfile(runtime: runtime)
    func changedProfile(
      launchArguments: [String] = [], environment: [String: String] = [:]
    ) -> CompatibilityProfile {
      CompatibilityProfile(
        id: base.id,
        revision: base.revision,
        gameID: base.gameID,
        gameVersion: base.gameVersion,
        gameBuildFingerprint: base.gameBuildFingerprint,
        macOS: base.macOS,
        architectures: base.architectures,
        requiredMetalFamilies: base.requiredMetalFamilies,
        requiresRosetta: base.requiresRosetta,
        tier: base.tier,
        verification: base.verification,
        runtimeID: base.runtimeID,
        priority: base.priority,
        launchArguments: launchArguments,
        environment: environment,
        verificationRecords: base.verificationRecords
      )
    }

    for changed in [
      changedProfile(launchArguments: ["--changed"]),
      changedProfile(environment: ["DXMT_LOG_LEVEL": "debug"]),
    ] {
      let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [changed])
      #expect(
        CatalogValidator.issues(in: catalog, at: CatalogTestFixtures.now).contains {
          $0.code == "missing-verification-record"
        })
    }
  }

  private func installedRuntime(
    id: String,
    acquisition: RuntimeAcquisition = .detectOnly,
    requirement: InstalledRuntimeRequirement
  ) -> RuntimeDefinition {
    RuntimeDefinition(
      id: id,
      backend: .gptkD3DMetal,
      version: "4.0.0",
      verification: .verified,
      acquisition: acquisition,
      installedRequirement: requirement,
      license: "Vendor license",
      redistributable: false
    )
  }
}
