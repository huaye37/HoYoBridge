import Foundation

public struct CatalogIssue: Codable, Equatable, Sendable {
  public let code: String
  public let path: String
  public let message: String

  public init(code: String, path: String, message: String) {
    self.code = code
    self.path = path
    self.message = message
  }
}

public enum CatalogValidator {
  private static let validMacOSMajorVersions = 1...100
  private static let maximumMacOSMajorSpan = 10

  public static func issues(in catalog: CompatibilityCatalog, at date: Date? = nil)
    -> [CatalogIssue]
  {
    var issues: [CatalogIssue] = []

    if catalog.schemaVersion != CatalogSchema.currentVersion {
      issues.append(
        .init(
          code: "unsupported-schema", path: "schemaVersion",
          message: "Expected schema version \(CatalogSchema.currentVersion)."))
    }
    if catalog.revision == 0 {
      issues.append(
        .init(
          code: "invalid-revision", path: "revision",
          message: "Catalog revision must be greater than zero."))
    }
    if catalog.catalogVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        .init(
          code: "empty-catalog-version", path: "catalogVersion",
          message: "Catalog version is required."))
    }
    if !isCanonicalNumericVersion(catalog.minimumClientVersion) {
      issues.append(
        .init(
          code: "invalid-client-version", path: "minimumClientVersion",
          message: "Minimum client version must use canonical ASCII numeric components."))
    }
    if catalog.expiresAt <= catalog.issuedAt {
      issues.append(
        .init(
          code: "invalid-validity-window", path: "expiresAt",
          message: "Catalog expiration must be later than its issue date."))
    }
    if let date, date >= catalog.expiresAt {
      issues.append(
        .init(code: "expired-catalog", path: "expiresAt", message: "Catalog has expired."))
    }
    if let date, date < catalog.issuedAt {
      issues.append(
        .init(
          code: "not-yet-valid-catalog", path: "issuedAt",
          message: "Catalog issue date is in the future."))
    }

    issues.append(contentsOf: duplicateIDIssues(catalog.games.map(\.id), collection: "games"))
    issues.append(contentsOf: duplicateIDIssues(catalog.runtimes.map(\.id), collection: "runtimes"))
    issues.append(contentsOf: duplicateIDIssues(catalog.profiles.map(\.id), collection: "profiles"))

    let gameIDs = Set(catalog.games.map(\.id))
    var runtimes: [String: RuntimeDefinition] = [:]
    for runtime in catalog.runtimes where runtimes[runtime.id] == nil {
      runtimes[runtime.id] = runtime
    }

    for (index, game) in catalog.games.enumerated() {
      validate(game: game, path: "games[\(index)]", issues: &issues)
    }
    for (index, runtime) in catalog.runtimes.enumerated() {
      validate(runtime: runtime, path: "runtimes[\(index)]", issues: &issues)
    }
    for (index, profile) in catalog.profiles.enumerated() {
      validate(
        profile: profile,
        path: "profiles[\(index)]",
        gameIDs: gameIDs,
        runtimes: runtimes,
        revocations: catalog.revocations,
        catalogIssuedAt: catalog.issuedAt,
        issues: &issues
      )
    }

    return issues
  }

  private static func validate(game: GameDefinition, path: String, issues: inout [CatalogIssue]) {
    if !isSafeIdentifier(game.id) {
      issues.append(
        .init(
          code: "invalid-game-id", path: "\(path).id",
          message: "Game ID must use only letters, numbers, dots, underscores and hyphens."))
    }
    if game.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        .init(
          code: "empty-game-name", path: "\(path).displayName", message: "Display name is required."
        ))
    }
    if game.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        .init(code: "empty-game-region", path: "\(path).region", message: "Region is required."))
    }
  }

  private static func validate(
    runtime: RuntimeDefinition, path: String, issues: inout [CatalogIssue]
  ) {
    if !isSafeIdentifier(runtime.id) {
      issues.append(
        .init(
          code: "invalid-runtime-id", path: "\(path).id",
          message: "Runtime ID must use only letters, numbers, dots, underscores and hyphens."))
    }
    let normalizedVersion = runtime.version.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if normalizedVersion.isEmpty {
      issues.append(
        .init(
          code: "empty-runtime-version", path: "\(path).version",
          message: "Runtime version is required."))
    } else if ["latest", "main", "master", "nightly"].contains(normalizedVersion) {
      issues.append(
        .init(
          code: "floating-runtime-version", path: "\(path).version",
          message: "Runtime versions must be pinned."))
    }
    if runtime.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(
        .init(
          code: "empty-runtime-license", path: "\(path).license",
          message: "Runtime license is required."))
    }

    if let source = runtime.sourceURL {
      if let url = URL(string: source),
        url.scheme?.lowercased() == "https",
        url.host != nil,
        url.user == nil,
        url.password == nil
      {
        let pathComponents = url.pathComponents.map { $0.lowercased() }
        if pathComponents.contains(where: { ["latest", "main", "master", "nightly"].contains($0) })
        {
          issues.append(
            .init(
              code: "floating-source-url", path: "\(path).sourceURL",
              message: "Runtime source URLs must resolve to a pinned artifact."))
        }
      } else {
        issues.append(
          .init(
            code: "invalid-source-url", path: "\(path).sourceURL",
            message: "Runtime sources must use HTTPS without embedded credentials."))
      }
    }

    if let sha256 = runtime.sha256, !isSHA256(sha256) {
      issues.append(
        .init(
          code: "invalid-sha256", path: "\(path).sha256",
          message: "SHA-256 must contain exactly 64 hexadecimal characters."))
    }

    if runtime.acquisition == .managedDownload {
      if runtime.sourceURL == nil {
        issues.append(
          .init(
            code: "missing-download-url", path: "\(path).sourceURL",
            message: "Managed downloads require a source URL."))
      }
      if runtime.byteSize == nil || runtime.byteSize == 0 {
        issues.append(
          .init(
            code: "missing-download-size", path: "\(path).byteSize",
            message: "Managed downloads require an expected byte size."))
      }
      if runtime.sha256 == nil {
        issues.append(
          .init(
            code: "missing-download-hash", path: "\(path).sha256",
            message: "Managed downloads require a SHA-256 hash."))
      }
      if !runtime.redistributable {
        issues.append(
          .init(
            code: "download-not-redistributable", path: "\(path).redistributable",
            message: "Managed downloads require confirmed redistribution permission."))
      }
    }

    if runtime.verification == .verified, runtime.acquisition != .managedDownload {
      guard let requirement = runtime.installedRequirement,
        isTeamIdentifier(requirement.teamIdentifier),
        isPinnedInstalledVersion(requirement.exactVersion),
        !requirement.requiredPaths.isEmpty,
        requirement.bundleIdentifier.map(isBundleIdentifier) != false,
        requirement.requiredPaths.allSatisfy(isSafeRequiredPath)
      else {
        issues.append(
          .init(
            code: "missing-installed-runtime-identity", path: "\(path).installedRequirement",
            message:
              "Verified installed runtimes require a team ID, exact version and required paths."))
        return
      }
    }
  }

  private static func validate(
    profile: CompatibilityProfile,
    path: String,
    gameIDs: Set<String>,
    runtimes: [String: RuntimeDefinition],
    revocations: RevocationList,
    catalogIssuedAt: Date,
    issues: inout [CatalogIssue]
  ) {
    if !isSafeIdentifier(profile.id) {
      issues.append(
        .init(
          code: "invalid-profile-id", path: "\(path).id",
          message: "Profile ID must use only letters, numbers, dots, underscores and hyphens."))
    }
    if profile.revision == 0 {
      issues.append(
        .init(
          code: "invalid-profile-revision", path: "\(path).revision",
          message: "Profile revision must be greater than zero."))
    }
    if !gameIDs.contains(profile.gameID) {
      issues.append(
        .init(
          code: "unknown-game", path: "\(path).gameID",
          message: "Profile references an unknown game."))
    }
    guard let runtime = runtimes[profile.runtimeID] else {
      issues.append(
        .init(
          code: "unknown-runtime", path: "\(path).runtimeID",
          message: "Profile references an unknown runtime."))
      return
    }
    if !isNumericVersion(profile.gameVersion) {
      issues.append(
        .init(
          code: "invalid-game-version", path: "\(path).gameVersion",
          message: "Game version must contain two to four numeric components."))
    }
    if !isSHA256(profile.gameBuildFingerprint) {
      issues.append(
        .init(
          code: "invalid-game-fingerprint", path: "\(path).gameBuildFingerprint",
          message: "Game build fingerprint must be a SHA-256 digest."))
    }
    if !validMacOSMajorVersions.contains(profile.macOS.minimumMajor) {
      issues.append(
        .init(
          code: "invalid-minimum-macos", path: "\(path).macOS.minimumMajor",
          message: "Minimum macOS major version must be between 1 and 100."))
    }
    if let maximum = profile.macOS.maximumMajor,
      !isValidClosedMacOSRange(minimum: profile.macOS.minimumMajor, maximum: maximum)
    {
      issues.append(
        .init(
          code: "invalid-macos-range", path: "\(path).macOS",
          message:
            "macOS ranges must be ordered, bounded at 100, and span no more than 10 major versions."
        ))
    }
    if profile.architectures.isEmpty
      || profile.architectures.contains(where: {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    {
      issues.append(
        .init(
          code: "invalid-architectures", path: "\(path).architectures",
          message: "At least one non-empty architecture is required."))
    }
    if !(0...1_000).contains(profile.priority) {
      issues.append(
        .init(
          code: "invalid-priority", path: "\(path).priority",
          message: "Priority must be between 0 and 1000."))
    }
    if profile.launchArguments.contains(where: { $0.isEmpty }) {
      issues.append(
        .init(
          code: "empty-launch-argument", path: "\(path).launchArguments",
          message: "Launch arguments cannot be empty strings."))
    }
    if profile.environment.keys.contains(where: {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) {
      issues.append(
        .init(
          code: "empty-environment-key", path: "\(path).environment",
          message: "Environment variable names cannot be empty."))
    }

    if profile.tier == .standard {
      if profile.verification != .verified {
        issues.append(
          .init(
            code: "unverified-standard-profile", path: "\(path).verification",
            message: "Standard profiles must be verified."))
      }
      if runtime.verification != .verified {
        issues.append(
          .init(
            code: "unverified-standard-runtime", path: "\(path).runtimeID",
            message: "Standard profiles require a verified runtime."))
      }
      if runtime.verification == .blocked {
        issues.append(
          .init(
            code: "blocked-runtime-reference", path: "\(path).runtimeID",
            message: "Profiles cannot reference a blocked runtime."))
      }
      if revocations.profileIDs.contains(profile.id) || revocations.runtimeIDs.contains(runtime.id)
      {
        issues.append(
          .init(
            code: "revoked-standard-profile", path: path,
            message: "Standard profiles cannot reference revoked entries."))
      }
      validateVerificationRecords(
        profile: profile,
        runtime: runtime,
        catalogIssuedAt: catalogIssuedAt,
        path: path,
        issues: &issues
      )
    } else if profile.disclosures.isEmpty {
      issues.append(
        .init(
          code: "missing-experimental-disclosure", path: "\(path).disclosures",
          message: "Experimental profiles require concrete impact and recovery disclosures."))
    }

    if runtime.verification == .blocked, profile.tier != .standard {
      issues.append(
        .init(
          code: "blocked-runtime-reference", path: "\(path).runtimeID",
          message: "Profiles cannot reference a blocked runtime."))
    }

    for (index, disclosure) in profile.disclosures.enumerated() {
      let disclosurePath = "\(path).disclosures[\(index)]"
      if disclosure.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || disclosure.impact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || disclosure.recovery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        issues.append(
          .init(
            code: "incomplete-disclosure", path: disclosurePath,
            message: "Each disclosure requires an ID, impact and recovery instruction."))
      }
    }
    let duplicateDisclosureIDs = Dictionary(grouping: profile.disclosures.map(\.id), by: { $0 })
      .filter { !$0.key.isEmpty && $0.value.count > 1 }
      .keys
      .sorted()
    for id in duplicateDisclosureIDs {
      issues.append(
        .init(
          code: "duplicate-disclosure-id", path: "\(path).disclosures",
          message: "Duplicate disclosure ID: \(id)"))
    }
  }

  private static func validateVerificationRecords(
    profile: CompatibilityProfile,
    runtime: RuntimeDefinition,
    catalogIssuedAt: Date,
    path: String,
    issues: inout [CatalogIssue]
  ) {
    guard let maximum = profile.macOS.maximumMajor else {
      issues.append(
        .init(
          code: "open-ended-standard-macos", path: "\(path).macOS.maximumMajor",
          message: "Standard profiles require a finite tested macOS range."))
      return
    }
    guard
      isValidClosedMacOSRange(minimum: profile.macOS.minimumMajor, maximum: maximum)
    else {
      return
    }
    let requiredGates = Set(VerificationGate.allCases)
    for major in profile.macOS.minimumMajor...maximum {
      for architecture in profile.architectures {
        let hasRecord = profile.verificationRecords.contains { record in
          record.macOSMajorVersion == major
            && record.architecture == architecture
            && Set(profile.requiredMetalFamilies).isSubset(of: Set(record.metalFamilies))
            && record.gameBuildFingerprint == profile.gameBuildFingerprint
            && record.runtimeDefinitionDigest == runtime.definitionDigest
            && record.profileDefinitionDigest == profile.definitionDigest
            && record.verifiedAt <= catalogIssuedAt
            && isSHA256(record.reportDigest)
            && requiredGates.isSubset(of: Set(record.passedGates))
        }
        if !hasRecord {
          issues.append(
            .init(
              code: "missing-verification-record",
              path: "\(path).verificationRecords",
              message:
                "No complete verification record exists for macOS \(major) on \(architecture)."
            ))
        }
      }
    }
  }

  private static func duplicateIDIssues(_ ids: [String], collection: String) -> [CatalogIssue] {
    Dictionary(grouping: ids, by: { $0 })
      .filter { !$0.key.isEmpty && $0.value.count > 1 }
      .keys
      .sorted()
      .map { CatalogIssue(code: "duplicate-id", path: collection, message: "Duplicate ID: \($0)") }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64
      && value.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
      }
  }

  private static func isSafeIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value != ".", value != "..", value.utf8.count <= 128 else { return false }
    return value.utf8.allSatisfy { byte in
      (48...57).contains(byte)
        || (65...90).contains(byte)
        || (97...122).contains(byte)
        || byte == 45
        || byte == 46
        || byte == 95
    }
  }

  private static func isNumericVersion(_ value: String) -> Bool {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    return (2...4).contains(components.count)
      && components.allSatisfy { component in
        !component.isEmpty
          && component.utf8.allSatisfy { (48...57).contains($0) }
          && Int(component) != nil
      }
  }

  private static func isCanonicalNumericVersion(_ value: String) -> Bool {
    guard isNumericVersion(value) else { return false }
    return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
      $0 == "0" || $0.utf8.first != 48
    }
  }

  private static func isValidClosedMacOSRange(minimum: Int, maximum: Int) -> Bool {
    guard validMacOSMajorVersions.contains(minimum), maximum >= minimum,
      validMacOSMajorVersions.contains(maximum)
    else {
      return false
    }
    return maximum <= minimum + maximumMacOSMajorSpan
  }

  private static func isSafeRequiredPath(_ value: String) -> Bool {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      value.hasPrefix("/"), value != "/", value.utf8.count <= 1_024,
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      return false
    }
    let components = value.split(separator: "/", omittingEmptySubsequences: false)
    guard components.first?.isEmpty == true else { return false }
    return components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }

  private static func isTeamIdentifier(_ value: String) -> Bool {
    value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.utf8.count == 10
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...90).contains(byte)
      }
  }

  private static func isPinnedInstalledVersion(_ value: String) -> Bool {
    guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty,
      value.utf8.count <= 64,
      value.utf8.allSatisfy({ byte in
        (48...57).contains(byte)
          || (65...90).contains(byte)
          || (97...122).contains(byte)
          || byte == 43
          || byte == 45
          || byte == 46
          || byte == 95
      }),
      value.utf8.first.map(isASCIIAlphanumeric) == true,
      value.utf8.last.map(isASCIIAlphanumeric) == true,
      !zip(value.utf8, value.utf8.dropFirst()).contains(where: {
        !isASCIIAlphanumeric($0.0) && !isASCIIAlphanumeric($0.1)
      }),
      !["latest", "main", "master", "nightly"].contains(value.lowercased())
    else {
      return false
    }
    return true
  }

  private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
  }

  private static func isBundleIdentifier(_ value: String) -> Bool {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    return components.count >= 2 && components.allSatisfy { !$0.isEmpty }
      && value.utf8.count <= 255
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte)
          || (65...90).contains(byte)
          || (97...122).contains(byte)
          || byte == 45
          || byte == 46
      }
  }
}
