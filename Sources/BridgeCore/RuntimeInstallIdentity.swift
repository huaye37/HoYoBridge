import Foundation

public struct RuntimeInstallEntryRecord: Encodable, Equatable, Sendable {
  public let relativePath: String
  public let kind: ArchiveEntryKind
  public let size: UInt64
  public let mode: UInt16
  public let contentSHA256: String?
}

public struct RuntimeInstallRecord: Encodable, Equatable, Sendable {
  public static let currentSchemaVersion: UInt8 = 1

  public let schemaVersion: UInt8
  public let installID: String
  public let runtimeID: String
  public let runtimeDefinitionSHA256: String
  public let artifactSHA256: String
  public let planPolicyVersion: Int
  public let planSHA256: String
  public let treeSealVersion: UInt8
  public let treeSHA256: String
  public let entryCount: Int
  public let regularFileCount: Int
  public let totalBytes: UInt64
  public let entries: [RuntimeInstallEntryRecord]
}

public enum RuntimeInstallIdentityError: Error, Equatable, Sendable {
  case runtimeIsNotManagedDownload
  case invalidRuntimeIdentity
  case artifactMismatch
  case planMismatch
  case unsupportedPlanPolicyVersion(Int)
  case unsupportedTreeSealVersion(UInt8)
  case invalidCandidate
}

public enum RuntimeInstallIdentityBuilder {
  public static func build(
    runtime: RuntimeDefinition,
    plan: SafeArchivePlan,
    candidate: ExtractedStagingTree
  ) throws -> RuntimeInstallRecord {
    guard runtime.acquisition == .managedDownload else {
      throw RuntimeInstallIdentityError.runtimeIsNotManagedDownload
    }
    let runtimeDefinitionSHA256 = runtime.definitionDigest
    guard !runtime.id.isEmpty,
      runtime.id == runtime.id.trimmingCharacters(in: .whitespacesAndNewlines),
      runtime.id == runtime.id.precomposedStringWithCanonicalMapping,
      !runtime.id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      runtime.id.utf8.count <= 256,
      runtime.redistributable,
      !runtime.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isSHA256(runtimeDefinitionSHA256),
      let rawArtifactSHA256 = runtime.sha256,
      let runtimeByteSize = runtime.byteSize,
      runtimeByteSize > 0
    else {
      throw RuntimeInstallIdentityError.invalidRuntimeIdentity
    }
    let artifactSHA256 = rawArtifactSHA256.lowercased()
    guard isSHA256(artifactSHA256) else { throw RuntimeInstallIdentityError.invalidRuntimeIdentity }
    guard artifactSHA256 == candidate.artifactSHA256 else {
      throw RuntimeInstallIdentityError.artifactMismatch
    }
    guard plan.policyVersion == SafeArchivePlanner.currentPolicyVersion else {
      throw RuntimeInstallIdentityError.unsupportedPlanPolicyVersion(plan.policyVersion)
    }
    guard candidate.planPolicyVersion == plan.policyVersion,
      candidate.planSHA256 == plan.canonicalSHA256,
      runtimeByteSize == plan.archiveByteSize,
      candidate.totalBytes == plan.totalRegularFileBytes
    else {
      throw RuntimeInstallIdentityError.planMismatch
    }
    guard candidate.treeSealVersion == SafeStagingTreeSealer.currentVersion else {
      throw RuntimeInstallIdentityError.unsupportedTreeSealVersion(candidate.treeSealVersion)
    }
    guard isSHA256(candidate.planSHA256), isSHA256(candidate.treeSHA256),
      candidate.regularFileCount >= 0,
      UInt32(exactly: candidate.entries.count) != nil,
      UInt32(exactly: candidate.regularFileCount) != nil,
      UInt32(exactly: candidate.planPolicyVersion) != nil
    else {
      throw RuntimeInstallIdentityError.invalidCandidate
    }

    let entries = try validatedEntries(candidate, plan: plan)
    let installID = makeInstallID(
      runtimeID: runtime.id,
      runtimeDefinitionSHA256: runtimeDefinitionSHA256,
      artifactSHA256: artifactSHA256,
      planPolicyVersion: candidate.planPolicyVersion,
      planSHA256: candidate.planSHA256,
      treeSealVersion: candidate.treeSealVersion,
      treeSHA256: candidate.treeSHA256,
      entryCount: entries.count,
      regularFileCount: candidate.regularFileCount,
      totalBytes: candidate.totalBytes
    )
    return RuntimeInstallRecord(
      schemaVersion: RuntimeInstallRecord.currentSchemaVersion,
      installID: installID,
      runtimeID: runtime.id,
      runtimeDefinitionSHA256: runtimeDefinitionSHA256,
      artifactSHA256: artifactSHA256,
      planPolicyVersion: candidate.planPolicyVersion,
      planSHA256: candidate.planSHA256,
      treeSealVersion: candidate.treeSealVersion,
      treeSHA256: candidate.treeSHA256,
      entryCount: entries.count,
      regularFileCount: candidate.regularFileCount,
      totalBytes: candidate.totalBytes,
      entries: entries
    )
  }

  private static func validatedEntries(
    _ candidate: ExtractedStagingTree,
    plan: SafeArchivePlan
  ) throws -> [RuntimeInstallEntryRecord] {
    var byPath: [String: StagingTreeSealEntry] = [:]
    var previousPath: String?
    var fileCount = 0
    var totalBytes: UInt64 = 0
    for entry in candidate.entries {
      guard entry.relativePath == entry.relativePath.precomposedStringWithCanonicalMapping,
        isSafeRelativePath(entry.relativePath),
        previousPath.map({ utf8Less($0, entry.relativePath) }) != false,
        byPath[entry.relativePath] == nil
      else {
        throw RuntimeInstallIdentityError.invalidCandidate
      }
      switch entry.kind {
      case .directory:
        guard entry.size == 0, entry.mode == 0o700, entry.contentSHA256 == nil else {
          throw RuntimeInstallIdentityError.invalidCandidate
        }
      case .regularFile:
        guard entry.mode == 0o600 || entry.mode == 0o700,
          let contentSHA256 = entry.contentSHA256,
          isSHA256(contentSHA256)
        else {
          throw RuntimeInstallIdentityError.invalidCandidate
        }
        let (newTotal, overflow) = totalBytes.addingReportingOverflow(entry.size)
        guard !overflow else { throw RuntimeInstallIdentityError.invalidCandidate }
        totalBytes = newTotal
        fileCount += 1
      default:
        throw RuntimeInstallIdentityError.invalidCandidate
      }
      byPath[entry.relativePath] = entry
      previousPath = entry.relativePath
    }

    for entry in candidate.entries {
      let components = entry.relativePath.split(separator: "/").map(String.init)
      guard components.count > 1 else { continue }
      for end in 1..<components.count {
        let ancestor = components[..<end].joined(separator: "/")
        guard byPath[ancestor]?.kind == .directory else {
          throw RuntimeInstallIdentityError.invalidCandidate
        }
      }
    }
    guard fileCount == candidate.regularFileCount,
      totalBytes == candidate.totalBytes,
      SafeStagingTreeSealer.canonicalSHA256(for: candidate.entries) == candidate.treeSHA256,
      entriesMatchPlan(candidate.entries, plan: plan)
    else {
      throw RuntimeInstallIdentityError.invalidCandidate
    }
    return candidate.entries.map {
      RuntimeInstallEntryRecord(
        relativePath: $0.relativePath,
        kind: $0.kind,
        size: $0.size,
        mode: $0.mode,
        contentSHA256: $0.contentSHA256
      )
    }
  }

  private static func entriesMatchPlan(
    _ entries: [StagingTreeSealEntry],
    plan: SafeArchivePlan
  ) -> Bool {
    var expected: [String: (ArchiveEntryKind, UInt64, UInt16)] = [:]
    for entry in plan.entries {
      let components = entry.relativePath.split(separator: "/").map(String.init)
      for end in 1..<components.count {
        expected[components[..<end].joined(separator: "/")] = (.directory, 0, 0o700)
      }
      expected[entry.relativePath] = (
        entry.kind, entry.declaredSize, entry.normalizedPermissions
      )
    }
    return expected.count == entries.count
      && entries.allSatisfy {
        guard let value = expected[$0.relativePath] else { return false }
        return value.0 == $0.kind && value.1 == $0.size && value.2 == $0.mode
      }
  }

  static func makeInstallID(
    runtimeID: String,
    runtimeDefinitionSHA256: String,
    artifactSHA256: String,
    planPolicyVersion: Int,
    planSHA256: String,
    treeSealVersion: UInt8,
    treeSHA256: String,
    entryCount: Int,
    regularFileCount: Int,
    totalBytes: UInt64
  ) -> String {
    var digest = CanonicalSHA256Builder(domain: Array("MGBINSTALL".utf8))
    digest.append(RuntimeInstallRecord.currentSchemaVersion)
    digest.appendFramed(runtimeID)
    digest.appendSHA256(runtimeDefinitionSHA256)
    digest.appendSHA256(artifactSHA256)
    digest.append(UInt32(planPolicyVersion))
    digest.appendSHA256(planSHA256)
    digest.append(treeSealVersion)
    digest.appendSHA256(treeSHA256)
    digest.append(UInt32(entryCount))
    digest.append(UInt32(regularFileCount))
    digest.append(totalBytes)
    return digest.finalize()
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.isEmpty
      && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }

  private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}
