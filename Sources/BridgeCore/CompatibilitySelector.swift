import Foundation

public struct ProfileAcknowledgement: Codable, Equatable, Hashable, Sendable {
  public let catalogRevision: UInt64
  public let catalogPayloadSHA256: String
  public let profileID: String
  public let profileRevision: UInt64
  public let disclosureDigest: String

  public init(
    catalogRevision: UInt64,
    catalogPayloadSHA256: String,
    profileID: String,
    profileRevision: UInt64,
    disclosureDigest: String
  ) {
    self.catalogRevision = catalogRevision
    self.catalogPayloadSHA256 = catalogPayloadSHA256
    self.profileID = profileID
    self.profileRevision = profileRevision
    self.disclosureDigest = disclosureDigest
  }
}

public struct CompatibilityRequest: Equatable, Sendable {
  public let gameID: String
  public let gameVersion: String
  public let gameBuildFingerprint: String
  public let macOSMajorVersion: Int
  public let architecture: String
  public let metalFamilies: Set<String>
  public let rosettaAvailable: Bool
  public let mode: CompatibilityMode
  public let preferredProfileID: String?
  public let acknowledgements: Set<ProfileAcknowledgement>

  public init(
    gameID: String,
    gameVersion: String,
    gameBuildFingerprint: String,
    macOSMajorVersion: Int,
    architecture: String,
    metalFamilies: Set<String>,
    rosettaAvailable: Bool,
    mode: CompatibilityMode,
    preferredProfileID: String? = nil,
    acknowledgements: Set<ProfileAcknowledgement> = []
  ) {
    self.gameID = gameID
    self.gameVersion = gameVersion
    self.gameBuildFingerprint = gameBuildFingerprint
    self.macOSMajorVersion = macOSMajorVersion
    self.architecture = architecture
    self.metalFamilies = metalFamilies
    self.rosettaAvailable = rosettaAvailable
    self.mode = mode
    self.preferredProfileID = preferredProfileID
    self.acknowledgements = acknowledgements
  }
}

public struct CompatibilityDecision: Equatable, Sendable {
  public let profile: CompatibilityProfile
  public let runtime: RuntimeDefinition
  public let usesExperimentalProfile: Bool

  public init(profile: CompatibilityProfile, runtime: RuntimeDefinition) {
    self.profile = profile
    self.runtime = runtime
    usesExperimentalProfile = profile.tier == .experimental
  }
}

public enum CompatibilitySelectionError: Error, Equatable, Sendable {
  case noCompatibleProfile
  case preferredProfileNotFound(String)
  case preferredProfileIncompatible(String)
  case experimentalModeRequired([String])
  case explicitExperimentalProfileRequired([String])
  case acknowledgementRequired(ProfileAcknowledgement, disclosures: [RiskDisclosure])
  case ambiguousProfiles([String])
}

public enum CompatibilitySelector {
  public static func select(
    from verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest
  ) throws -> CompatibilityDecision {
    let catalog = verifiedCatalog.catalog
    let revokedProfiles = Set(catalog.revocations.profileIDs)
    let revokedRuntimes = Set(catalog.revocations.runtimeIDs)
    let runtimes = Dictionary(uniqueKeysWithValues: catalog.runtimes.map { ($0.id, $0) })
    let matching = catalog.profiles.filter { profile in
      profile.gameID == request.gameID
        && profile.gameVersion == request.gameVersion
        && profile.gameBuildFingerprint == request.gameBuildFingerprint
        && profile.macOS.contains(majorVersion: request.macOSMajorVersion)
        && profile.architectures.contains(request.architecture)
        && Set(profile.requiredMetalFamilies).isSubset(of: request.metalFamilies)
        && (!profile.requiresRosetta || request.rosettaAvailable)
        && profile.verification != .blocked
        && runtimes[profile.runtimeID]?.verification != .blocked
        && !revokedProfiles.contains(profile.id)
        && !revokedRuntimes.contains(profile.runtimeID)
    }

    let selected: CompatibilityProfile
    if let preferredProfileID = request.preferredProfileID {
      guard catalog.profiles.contains(where: { $0.id == preferredProfileID }) else {
        throw CompatibilitySelectionError.preferredProfileNotFound(preferredProfileID)
      }
      guard let preferred = matching.first(where: { $0.id == preferredProfileID }) else {
        throw CompatibilitySelectionError.preferredProfileIncompatible(preferredProfileID)
      }
      selected = try authorize(
        profile: preferred,
        verifiedCatalog: verifiedCatalog,
        request: request
      )
    } else {
      let standard = matching.filter { $0.tier == .standard && $0.verification == .verified }
      if let safe = try uniqueHighestPriority(standard) {
        selected = safe
      } else {
        let experimental = matching.filter { $0.tier == .experimental }
        guard !experimental.isEmpty else {
          throw CompatibilitySelectionError.noCompatibleProfile
        }
        guard request.mode == .experimental else {
          throw CompatibilitySelectionError.experimentalModeRequired(
            experimental.map(\.id).sorted())
        }
        throw CompatibilitySelectionError.explicitExperimentalProfileRequired(
          experimental.map(\.id).sorted())
      }
    }

    guard let runtime = catalog.runtimes.first(where: { $0.id == selected.runtimeID }) else {
      throw CompatibilitySelectionError.preferredProfileIncompatible(selected.id)
    }
    return CompatibilityDecision(profile: selected, runtime: runtime)
  }

  public static func acknowledgement(
    for profile: CompatibilityProfile,
    in verifiedCatalog: VerifiedCatalog
  ) -> ProfileAcknowledgement {
    .init(
      catalogRevision: verifiedCatalog.catalog.revision,
      catalogPayloadSHA256: verifiedCatalog.payloadSHA256,
      profileID: profile.id,
      profileRevision: profile.revision,
      disclosureDigest: profile.disclosureDigest
    )
  }

  private static func authorize(
    profile: CompatibilityProfile,
    verifiedCatalog: VerifiedCatalog,
    request: CompatibilityRequest
  ) throws -> CompatibilityProfile {
    guard profile.tier == .experimental else { return profile }
    guard request.mode == .experimental else {
      throw CompatibilitySelectionError.experimentalModeRequired([profile.id])
    }
    let requiredAcknowledgement = acknowledgement(for: profile, in: verifiedCatalog)
    guard request.acknowledgements.contains(requiredAcknowledgement) else {
      throw CompatibilitySelectionError.acknowledgementRequired(
        requiredAcknowledgement,
        disclosures: profile.disclosures
      )
    }
    return profile
  }

  private static func uniqueHighestPriority(_ profiles: [CompatibilityProfile]) throws
    -> CompatibilityProfile?
  {
    guard let highestPriority = profiles.map(\.priority).max() else { return nil }
    let highest = profiles.filter { $0.priority == highestPriority }
    guard highest.count == 1 else {
      throw CompatibilitySelectionError.ambiguousProfiles(highest.map(\.id).sorted())
    }
    return highest[0]
  }
}
