import CryptoKit
import Foundation

public enum ArchiveEntryKind: String, CaseIterable, Codable, Equatable, Sendable {
  case regularFile
  case directory
  case symbolicLink
  case hardLink
  case fifo
  case socket
  case blockDevice
  case characterDevice
  case unknown
}

public struct ArchiveEntryDescriptor: Codable, Equatable, Sendable {
  public let path: String
  public let kind: ArchiveEntryKind
  public let declaredSize: UInt64
  /// Permission bits only. File-type bits are not accepted here.
  public let permissions: UInt32
  public let linkTarget: String?

  public init(
    path: String,
    kind: ArchiveEntryKind,
    declaredSize: UInt64,
    permissions: UInt32,
    linkTarget: String? = nil
  ) {
    self.path = path
    self.kind = kind
    self.declaredSize = declaredSize
    self.permissions = permissions
    self.linkTarget = linkTarget
  }
}

public struct SafeExtractionLimits: Codable, Equatable, Sendable {
  public static let `default` = SafeExtractionLimits(
    maximumEntryCount: 100_000,
    maximumFileBytes: 32 * 1_024 * 1_024 * 1_024,
    maximumTotalBytes: 256 * 1_024 * 1_024 * 1_024,
    maximumPathBytes: 1_024,
    maximumComponentBytes: 255,
    maximumPathDepth: 32,
    maximumExpansionRatio: 200
  )

  public let maximumEntryCount: Int
  public let maximumFileBytes: UInt64
  public let maximumTotalBytes: UInt64
  public let maximumPathBytes: Int
  public let maximumComponentBytes: Int
  public let maximumPathDepth: Int
  public let maximumExpansionRatio: UInt64

  public init(
    maximumEntryCount: Int,
    maximumFileBytes: UInt64,
    maximumTotalBytes: UInt64,
    maximumPathBytes: Int,
    maximumComponentBytes: Int,
    maximumPathDepth: Int,
    maximumExpansionRatio: UInt64
  ) {
    self.maximumEntryCount = max(0, maximumEntryCount)
    self.maximumFileBytes = maximumFileBytes
    self.maximumTotalBytes = maximumTotalBytes
    self.maximumPathBytes = max(0, maximumPathBytes)
    self.maximumComponentBytes = max(0, maximumComponentBytes)
    self.maximumPathDepth = max(0, maximumPathDepth)
    self.maximumExpansionRatio = maximumExpansionRatio
  }
}

public enum ArchivePathViolation: String, Codable, Equatable, Sendable {
  case empty
  case absolute
  case homeRelative
  case windowsSyntax
  case controlCharacter
  case emptyComponent
  case traversalComponent
  case surroundingWhitespace
  case trailingDot
  case fileHasTrailingSlash
}

public enum SafeArchivePlanError: Error, Equatable, Sendable {
  case invalidArchiveByteSize
  case entryLimitExceeded(limit: Int, actual: Int)
  case unsupportedEntryKind(ArchiveEntryKind)
  case invalidPath(ArchivePathViolation)
  case pathByteLimitExceeded(limit: Int, actual: Int)
  case componentByteLimitExceeded(limit: Int, actual: Int)
  case pathDepthLimitExceeded(limit: Int, actual: Int)
  case canonicalPathCollision
  case fileAncestorConflict
  case unexpectedLinkTarget
  case directoryHasPayload(UInt64)
  case unsafePermissions
  case fileSizeLimitExceeded(limit: UInt64, actual: UInt64)
  case totalSizeLimitExceeded(limit: UInt64, actual: UInt64)
  case expansionRatioExceeded(limit: UInt64, archiveBytes: UInt64, expandedBytes: UInt64)
  case arithmeticOverflow
}

public struct PlannedArchiveEntry: Encodable, Equatable, Sendable {
  public let relativePath: String
  public let sourcePathSHA256: String
  public let kind: ArchiveEntryKind
  public let declaredSize: UInt64
  public let sourcePermissions: UInt32
  public let normalizedPermissions: UInt16
}

public struct SafeArchivePlan: Encodable, Equatable, Sendable {
  public static let canonicalDigestSchemaVersion: UInt8 = 1

  public let policyVersion: Int
  public let entries: [PlannedArchiveEntry]
  public let archiveByteSize: UInt64
  public let totalRegularFileBytes: UInt64

  /// Stable across JSON encoders and input descriptor permutations.
  public var canonicalSHA256: String {
    var digest = CanonicalSHA256Builder(domain: Array("MGBPLAN".utf8))
    digest.append(Self.canonicalDigestSchemaVersion)
    digest.append(UInt32(policyVersion))
    digest.append(archiveByteSize)
    digest.append(totalRegularFileBytes)
    digest.append(UInt32(entries.count))
    for entry in entries.sorted(by: { utf8Less($0.relativePath, $1.relativePath) }) {
      digest.append(entry.kind.sealTag)
      digest.appendFramed(entry.relativePath.precomposedStringWithCanonicalMapping)
      digest.appendSHA256(entry.sourcePathSHA256)
      digest.append(entry.declaredSize)
      digest.append(entry.sourcePermissions)
      digest.append(entry.normalizedPermissions)
    }
    return digest.finalize()
  }
}

struct CanonicalSHA256Builder {
  private var hasher = SHA256()

  init(domain: [UInt8]) {
    hasher.update(data: Data(domain))
  }

  mutating func appendFramed(_ value: String) {
    let bytes = Data(value.utf8)
    append(UInt32(bytes.count))
    hasher.update(data: bytes)
  }

  mutating func appendSHA256(_ value: String) {
    precondition(
      value.utf8.count == 64
        && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    )
    var bytes: [UInt8] = []
    bytes.reserveCapacity(32)
    let characters = Array(value.utf8)
    for index in stride(from: 0, to: characters.count, by: 2) {
      bytes.append(hexNibble(characters[index]) << 4 | hexNibble(characters[index + 1]))
    }
    hasher.update(data: Data(bytes))
  }

  mutating func append(_ value: UInt8) {
    var encoded = value
    withUnsafeBytes(of: &encoded) { hasher.update(bufferPointer: $0) }
  }

  mutating func append(_ value: UInt16) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { hasher.update(bufferPointer: $0) }
  }

  mutating func append(_ value: UInt32) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { hasher.update(bufferPointer: $0) }
  }

  mutating func append(_ value: UInt64) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { hasher.update(bufferPointer: $0) }
  }

  mutating func finalize() -> String {
    hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func hexNibble(_ byte: UInt8) -> UInt8 {
    byte <= 57 ? byte - 48 : byte - 87
  }
}

private func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
  lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

extension ArchiveEntryKind {
  var sealTag: UInt8 {
    switch self {
    case .directory: 1
    case .regularFile: 2
    default: preconditionFailure("Only planned directory and regular-file kinds can be sealed")
    }
  }
}

public enum SafeArchivePlanner {
  public static let currentPolicyVersion = 1

  public static func plan(
    entries: [ArchiveEntryDescriptor],
    archiveByteSize: UInt64,
    limits: SafeExtractionLimits = .default
  ) throws -> SafeArchivePlan {
    guard archiveByteSize > 0 else { throw SafeArchivePlanError.invalidArchiveByteSize }
    guard entries.count <= limits.maximumEntryCount else {
      throw SafeArchivePlanError.entryLimitExceeded(
        limit: limits.maximumEntryCount,
        actual: entries.count
      )
    }

    let ordered =
      entries
      .map { (entry: $0, pathDigest: sha256($0.path)) }
      .sorted {
        if $0.pathDigest != $1.pathDigest { return $0.pathDigest < $1.pathDigest }
        if $0.entry.path != $1.entry.path { return $0.entry.path < $1.entry.path }
        if $0.entry.kind != $1.entry.kind {
          return $0.entry.kind.rawValue < $1.entry.kind.rawValue
        }
        if $0.entry.declaredSize != $1.entry.declaredSize {
          return $0.entry.declaredSize < $1.entry.declaredSize
        }
        if $0.entry.permissions != $1.entry.permissions {
          return $0.entry.permissions < $1.entry.permissions
        }
        switch ($0.entry.linkTarget, $1.entry.linkTarget) {
        case (nil, .some): return true
        case (.some, nil): return false
        case (.some(let left), .some(let right)): return left < right
        case (nil, nil): return false
        }
      }

    var candidates: [Candidate] = []
    var seenCanonicalPaths = Set<String>()
    var totalBytes: UInt64 = 0
    for item in ordered {
      let entry = item.entry
      guard entry.kind == .regularFile || entry.kind == .directory else {
        throw SafeArchivePlanError.unsupportedEntryKind(entry.kind)
      }
      guard entry.linkTarget == nil else {
        throw SafeArchivePlanError.unexpectedLinkTarget
      }
      guard entry.permissions & ~UInt32(0o7777) == 0,
        entry.permissions & UInt32(0o7000) == 0
      else {
        throw SafeArchivePlanError.unsafePermissions
      }

      let normalizedPath = try normalize(
        entry.path,
        kind: entry.kind,
        limits: limits
      )
      let canonicalKey = canonicalKey(for: normalizedPath)
      guard seenCanonicalPaths.insert(canonicalKey).inserted else {
        throw SafeArchivePlanError.canonicalPathCollision
      }

      let normalizedPermissions: UInt16
      switch entry.kind {
      case .directory:
        guard entry.declaredSize == 0 else {
          throw SafeArchivePlanError.directoryHasPayload(entry.declaredSize)
        }
        normalizedPermissions = 0o700
      case .regularFile:
        guard entry.declaredSize <= limits.maximumFileBytes else {
          throw SafeArchivePlanError.fileSizeLimitExceeded(
            limit: limits.maximumFileBytes,
            actual: entry.declaredSize
          )
        }
        let (newTotal, overflow) = totalBytes.addingReportingOverflow(entry.declaredSize)
        guard !overflow else { throw SafeArchivePlanError.arithmeticOverflow }
        guard newTotal <= limits.maximumTotalBytes else {
          throw SafeArchivePlanError.totalSizeLimitExceeded(
            limit: limits.maximumTotalBytes,
            actual: newTotal
          )
        }
        totalBytes = newTotal
        normalizedPermissions = entry.permissions & 0o111 == 0 ? 0o600 : 0o700
      default:
        preconditionFailure("Unsupported kinds were rejected above")
      }

      candidates.append(
        Candidate(
          canonicalKey: canonicalKey,
          planned: PlannedArchiveEntry(
            relativePath: normalizedPath,
            sourcePathSHA256: item.pathDigest,
            kind: entry.kind,
            declaredSize: entry.declaredSize,
            sourcePermissions: entry.permissions,
            normalizedPermissions: normalizedPermissions
          )
        )
      )
    }

    try validateAncestors(candidates)
    let (maximumExpandedBytes, ratioOverflow) = archiveByteSize.multipliedReportingOverflow(
      by: limits.maximumExpansionRatio
    )
    guard !ratioOverflow else { throw SafeArchivePlanError.arithmeticOverflow }
    guard totalBytes <= maximumExpandedBytes else {
      throw SafeArchivePlanError.expansionRatioExceeded(
        limit: limits.maximumExpansionRatio,
        archiveBytes: archiveByteSize,
        expandedBytes: totalBytes
      )
    }

    return SafeArchivePlan(
      policyVersion: currentPolicyVersion,
      entries: candidates.sorted { $0.canonicalKey < $1.canonicalKey }.map(\.planned),
      archiveByteSize: archiveByteSize,
      totalRegularFileBytes: totalBytes
    )
  }

  private struct Candidate {
    let canonicalKey: String
    let planned: PlannedArchiveEntry
  }

  private static func normalize(
    _ rawPath: String,
    kind: ArchiveEntryKind,
    limits: SafeExtractionLimits
  ) throws -> String {
    guard !rawPath.isEmpty else { throw SafeArchivePlanError.invalidPath(.empty) }
    guard rawPath == rawPath.trimmingCharacters(in: .whitespacesAndNewlines) else {
      throw SafeArchivePlanError.invalidPath(.surroundingWhitespace)
    }
    guard !rawPath.hasPrefix("/") else {
      throw SafeArchivePlanError.invalidPath(.absolute)
    }
    guard !rawPath.hasPrefix("~") else {
      throw SafeArchivePlanError.invalidPath(.homeRelative)
    }
    guard !rawPath.contains("\\"), !rawPath.contains(":") else {
      throw SafeArchivePlanError.invalidPath(.windowsSyntax)
    }
    guard !rawPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw SafeArchivePlanError.invalidPath(.controlCharacter)
    }

    var path = rawPath
    if path.hasSuffix("/") {
      guard kind == .directory else {
        throw SafeArchivePlanError.invalidPath(.fileHasTrailingSlash)
      }
      path.removeLast()
    }
    guard !path.isEmpty else { throw SafeArchivePlanError.invalidPath(.empty) }

    let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !rawComponents.contains(where: { $0.isEmpty }) else {
      throw SafeArchivePlanError.invalidPath(.emptyComponent)
    }
    guard rawComponents.count <= limits.maximumPathDepth else {
      throw SafeArchivePlanError.pathDepthLimitExceeded(
        limit: limits.maximumPathDepth,
        actual: rawComponents.count
      )
    }

    var components: [String] = []
    components.reserveCapacity(rawComponents.count)
    for rawComponent in rawComponents {
      guard rawComponent != ".", rawComponent != ".." else {
        throw SafeArchivePlanError.invalidPath(.traversalComponent)
      }
      let component = String(rawComponent)
      guard component == component.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw SafeArchivePlanError.invalidPath(.surroundingWhitespace)
      }
      guard !component.hasSuffix(".") else {
        throw SafeArchivePlanError.invalidPath(.trailingDot)
      }
      let normalized = component.precomposedStringWithCanonicalMapping
      guard normalized.utf8.count <= limits.maximumComponentBytes else {
        throw SafeArchivePlanError.componentByteLimitExceeded(
          limit: limits.maximumComponentBytes,
          actual: normalized.utf8.count
        )
      }
      components.append(normalized)
    }

    let normalizedPath = components.joined(separator: "/")
    guard normalizedPath.utf8.count <= limits.maximumPathBytes else {
      throw SafeArchivePlanError.pathByteLimitExceeded(
        limit: limits.maximumPathBytes,
        actual: normalizedPath.utf8.count
      )
    }
    return normalizedPath
  }

  private static func canonicalKey(for path: String) -> String {
    path.precomposedStringWithCanonicalMapping.folding(
      options: [.caseInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }

  private static func validateAncestors(_ candidates: [Candidate]) throws {
    let kinds = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.canonicalKey, $0.planned.kind) })
    for candidate in candidates {
      let components = candidate.canonicalKey.split(separator: "/")
      guard components.count > 1 else { continue }
      for end in 1..<components.count {
        let ancestor = components[..<end].joined(separator: "/")
        if kinds[ancestor] == .regularFile {
          throw SafeArchivePlanError.fileAncestorConflict
        }
      }
    }
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
