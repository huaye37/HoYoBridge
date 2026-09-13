import Foundation

struct UntrustedRuntimeInstallEntry: Decodable {
  let relativePath: String
  let kind: ArchiveEntryKind
  let size: UInt64
  let mode: UInt16
  let contentSHA256: String?
}

struct UntrustedRuntimeInstallRecord: Decodable {
  let schemaVersion: UInt8
  let installID: String
  let runtimeID: String
  let runtimeDefinitionSHA256: String
  let artifactSHA256: String
  let planPolicyVersion: Int
  let planSHA256: String
  let treeSealVersion: UInt8
  let treeSHA256: String
  let entryCount: Int
  let regularFileCount: Int
  let totalBytes: UInt64
  let entries: [UntrustedRuntimeInstallEntry]
}

struct UntrustedRuntimeActivationRecord: Decodable {
  let schemaVersion: UInt8
  let activationID: String
  let generation: UInt64
  let catalogRevision: UInt64
  let catalogPayloadSHA256: String
  let catalogChannel: CatalogChannel
  let selectionMode: CompatibilityMode
  let acknowledgementSHA256: String?
  let profileID: String
  let profileRevision: UInt64
  let profileDefinitionSHA256: String
  let disclosureSHA256: String
  let gameID: String
  let gameVersion: String
  let gameBuildFingerprint: String
  let runtimeID: String
  let runtimeDefinitionSHA256: String
  let installID: String
  let artifactSHA256: String
  let planPolicyVersion: Int
  let planSHA256: String
  let treeSealVersion: UInt8
  let treeSHA256: String
  let compatibilityTier: CompatibilityTier
}

enum RuntimeRecordDecodingError: Error, Equatable, Sendable {
  case oversized
  case malformed
  case invalidRecord
  case nonCanonical
}

/// Self-consistency parser only. It does not authorize selection, installation, or activation.
enum RuntimeRecordDecoder {
  static let maximumInstallBytes = 128 * 1_024 * 1_024
  static let maximumActivationBytes = 64 * 1_024

  static func decodeInstall(_ data: Data) throws -> RuntimeInstallRecord {
    guard !data.isEmpty, data.count <= maximumInstallBytes else {
      throw RuntimeRecordDecodingError.oversized
    }
    guard validJSONDepth(data) else { throw RuntimeRecordDecodingError.malformed }
    let untrusted: UntrustedRuntimeInstallRecord = try decode(data)
    guard untrusted.schemaVersion == RuntimeInstallRecord.currentSchemaVersion,
      untrusted.planPolicyVersion == SafeArchivePlanner.currentPolicyVersion,
      untrusted.treeSealVersion == SafeStagingTreeSealer.currentVersion,
      isText(untrusted.runtimeID),
      untrusted.runtimeID.utf8.count <= 256,
      untrusted.entryCount == untrusted.entries.count,
      untrusted.entryCount <= SafeExtractionLimits.default.maximumEntryCount,
      untrusted.regularFileCount >= 0,
      [
        untrusted.installID, untrusted.runtimeDefinitionSHA256,
        untrusted.artifactSHA256, untrusted.planSHA256,
        untrusted.treeSHA256,
      ].allSatisfy(isSHA256)
    else {
      throw RuntimeRecordDecodingError.invalidRecord
    }

    var entries: [RuntimeInstallEntryRecord] = []
    var sealEntries: [StagingTreeSealEntry] = []
    var byPath: [String: ArchiveEntryKind] = [:]
    var byCanonicalPath: [String: ArchiveEntryKind] = [:]
    var previousPath: String?
    var fileCount = 0
    var totalBytes: UInt64 = 0
    for entry in untrusted.entries {
      guard isPath(entry.relativePath),
        previousPath.map({ utf8Less($0, entry.relativePath) }) != false,
        byPath[entry.relativePath] == nil,
        byCanonicalPath[canonicalPath(entry.relativePath)] == nil
      else { throw RuntimeRecordDecodingError.invalidRecord }
      switch entry.kind {
      case .directory:
        guard entry.size == 0, entry.mode == 0o700, entry.contentSHA256 == nil else {
          throw RuntimeRecordDecodingError.invalidRecord
        }
      case .regularFile:
        guard entry.mode == 0o600 || entry.mode == 0o700,
          entry.size <= SafeExtractionLimits.default.maximumFileBytes,
          let contentSHA256 = entry.contentSHA256, isSHA256(contentSHA256)
        else { throw RuntimeRecordDecodingError.invalidRecord }
        let (next, overflow) = totalBytes.addingReportingOverflow(entry.size)
        guard !overflow, next <= SafeExtractionLimits.default.maximumTotalBytes else {
          throw RuntimeRecordDecodingError.invalidRecord
        }
        totalBytes = next
        fileCount += 1
      default:
        throw RuntimeRecordDecodingError.invalidRecord
      }
      entries.append(
        RuntimeInstallEntryRecord(
          relativePath: entry.relativePath, kind: entry.kind, size: entry.size,
          mode: entry.mode, contentSHA256: entry.contentSHA256))
      sealEntries.append(
        StagingTreeSealEntry(
          relativePath: entry.relativePath, kind: entry.kind, size: entry.size,
          mode: entry.mode, contentSHA256: entry.contentSHA256))
      byPath[entry.relativePath] = entry.kind
      byCanonicalPath[canonicalPath(entry.relativePath)] = entry.kind
      previousPath = entry.relativePath
    }
    for entry in untrusted.entries {
      let components = entry.relativePath.split(separator: "/").map(String.init)
      for end in 1..<components.count {
        let ancestor = components[..<end].joined(separator: "/")
        guard byPath[ancestor] == .directory,
          byCanonicalPath[canonicalPath(ancestor)] == .directory
        else {
          throw RuntimeRecordDecodingError.invalidRecord
        }
      }
    }
    guard fileCount == untrusted.regularFileCount, totalBytes == untrusted.totalBytes,
      SafeStagingTreeSealer.canonicalSHA256(for: sealEntries) == untrusted.treeSHA256,
      RuntimeInstallIdentityBuilder.makeInstallID(
        runtimeID: untrusted.runtimeID,
        runtimeDefinitionSHA256: untrusted.runtimeDefinitionSHA256,
        artifactSHA256: untrusted.artifactSHA256,
        planPolicyVersion: untrusted.planPolicyVersion,
        planSHA256: untrusted.planSHA256,
        treeSealVersion: untrusted.treeSealVersion,
        treeSHA256: untrusted.treeSHA256,
        entryCount: untrusted.entryCount,
        regularFileCount: untrusted.regularFileCount,
        totalBytes: untrusted.totalBytes
      ) == untrusted.installID
    else { throw RuntimeRecordDecodingError.invalidRecord }

    let trusted = RuntimeInstallRecord(
      schemaVersion: untrusted.schemaVersion, installID: untrusted.installID,
      runtimeID: untrusted.runtimeID,
      runtimeDefinitionSHA256: untrusted.runtimeDefinitionSHA256,
      artifactSHA256: untrusted.artifactSHA256,
      planPolicyVersion: untrusted.planPolicyVersion, planSHA256: untrusted.planSHA256,
      treeSealVersion: untrusted.treeSealVersion, treeSHA256: untrusted.treeSHA256,
      entryCount: untrusted.entryCount, regularFileCount: untrusted.regularFileCount,
      totalBytes: untrusted.totalBytes, entries: entries)
    try requireCanonical(trusted, raw: data)
    return trusted
  }

  static func decodeActivation(_ data: Data) throws -> RuntimeActivationRecord {
    guard !data.isEmpty, data.count <= maximumActivationBytes else {
      throw RuntimeRecordDecodingError.oversized
    }
    guard validJSONDepth(data) else { throw RuntimeRecordDecodingError.malformed }
    let value: UntrustedRuntimeActivationRecord = try decode(data)
    let hashes = [
      value.activationID, value.catalogPayloadSHA256,
      value.profileDefinitionSHA256, value.disclosureSHA256,
      value.gameBuildFingerprint, value.runtimeDefinitionSHA256,
      value.installID, value.artifactSHA256, value.planSHA256, value.treeSHA256,
    ]
    guard value.schemaVersion == RuntimeActivationRecord.currentSchemaVersion,
      value.generation > 0, value.catalogRevision > 0, value.profileRevision > 0,
      value.planPolicyVersion == SafeArchivePlanner.currentPolicyVersion,
      value.treeSealVersion == SafeStagingTreeSealer.currentVersion,
      hashes.allSatisfy(isSHA256), isText(value.profileID), isText(value.gameID),
      isText(value.gameVersion), isText(value.runtimeID), validAck(value)
    else { throw RuntimeRecordDecodingError.invalidRecord }

    let trusted = RuntimeActivationRecord(
      schemaVersion: value.schemaVersion, activationID: value.activationID,
      generation: value.generation, catalogRevision: value.catalogRevision,
      catalogPayloadSHA256: value.catalogPayloadSHA256,
      catalogChannel: value.catalogChannel, selectionMode: value.selectionMode,
      acknowledgementSHA256: value.acknowledgementSHA256,
      profileID: value.profileID, profileRevision: value.profileRevision,
      profileDefinitionSHA256: value.profileDefinitionSHA256,
      disclosureSHA256: value.disclosureSHA256, gameID: value.gameID,
      gameVersion: value.gameVersion, gameBuildFingerprint: value.gameBuildFingerprint,
      runtimeID: value.runtimeID, runtimeDefinitionSHA256: value.runtimeDefinitionSHA256,
      installID: value.installID, artifactSHA256: value.artifactSHA256,
      planPolicyVersion: value.planPolicyVersion, planSHA256: value.planSHA256,
      treeSealVersion: value.treeSealVersion, treeSHA256: value.treeSHA256,
      compatibilityTier: value.compatibilityTier)
    guard RuntimeActivationIdentityBuilder.activationID(trusted) == value.activationID else {
      throw RuntimeRecordDecodingError.invalidRecord
    }
    try requireCanonical(trusted, raw: data)
    return trusted
  }

  private static func decode<T: Decodable>(_ data: Data) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: data) } catch {
      throw RuntimeRecordDecodingError.malformed
    }
  }

  private static func requireCanonical<T: Encodable>(_ value: T, raw: Data) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard try encoder.encode(value) == raw else { throw RuntimeRecordDecodingError.nonCanonical }
  }

  private static func validAck(_ value: UntrustedRuntimeActivationRecord) -> Bool {
    switch value.compatibilityTier {
    case .standard: return value.acknowledgementSHA256 == nil
    case .experimental:
      return value.selectionMode == .experimental
        && value.acknowledgementSHA256.map(isSHA256) == true
    }
  }

  private static func isPath(_ path: String) -> Bool {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return isText(path) && !components.isEmpty
      && !path.hasPrefix("~") && !path.contains("\\") && !path.contains(":")
      && path.utf8.count <= SafeExtractionLimits.default.maximumPathBytes
      && components.count <= SafeExtractionLimits.default.maximumPathDepth
      && components.allSatisfy {
        $0.utf8.count <= SafeExtractionLimits.default.maximumComponentBytes
      }
      && components.allSatisfy {
        let component = String($0)
        return !component.isEmpty && component != "." && component != ".."
          && component == component.trimmingCharacters(in: .whitespacesAndNewlines)
          && !component.hasSuffix(".")
      }
  }

  private static func canonicalPath(_ path: String) -> String {
    path.precomposedStringWithCanonicalMapping.folding(
      options: [.caseInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }

  private static func validJSONDepth(_ data: Data) -> Bool {
    var depth = 0
    var inString = false
    var escaped = false
    for byte in data {
      if inString {
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          inString = false
        }
      } else if byte == 34 {
        inString = true
      } else if byte == 123 || byte == 91 {
        depth += 1
        if depth > 64 { return false }
      } else if byte == 125 || byte == 93 {
        depth -= 1
        if depth < 0 { return false }
      }
    }
    return depth == 0 && !inString
  }

  private static func isText(_ value: String) -> Bool {
    !value.isEmpty
      && value == value.precomposedStringWithCanonicalMapping
      && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      && UInt32(exactly: value.utf8.count) != nil
  }

  private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
