import Foundation

public enum GameRelease: String, Equatable, Hashable, Sendable {
  case genshinOfficialCN
}

public struct GameVersion: Equatable, Hashable, Sendable {
  public let value: String

  public init(_ value: String) throws {
    guard !value.isEmpty, value.utf8.count <= 128,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      value.utf8.elementsEqual(value.precomposedStringWithCanonicalMapping.utf8),
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw ManifestAdapterError.invalidRequest
    }
    self.value = value
  }
}

public enum ResourceCategory: String, Equatable, Hashable, Sendable {
  case game
}

public enum ManifestIntent: Equatable, Sendable {
  case full
  case update(from: GameVersion)
  case preDownload(from: GameVersion?)
}

public struct ManifestFixtureID: Equatable, Hashable, Sendable {
  public let value: String

  public init(_ value: String) throws {
    guard value != ".", value != "..", !value.isEmpty, value.utf8.count <= 128,
      value.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 46 || $0 == 95
      })
    else {
      throw ManifestAdapterError.invalidRequest
    }
    self.value = value
  }
}

public enum ManifestCachePolicy: Equatable, Sendable {
  case fixtureOnly(id: ManifestFixtureID)
  case freshCache(maxAgeSeconds: UInt64)
  case reloadIgnoringCache
}

public struct ManifestInspectionRequest: Equatable, Sendable {
  public let release: GameRelease
  public let intent: ManifestIntent
  public let categories: Set<ResourceCategory>
  public let cachePolicy: ManifestCachePolicy

  public init(
    release: GameRelease,
    intent: ManifestIntent,
    categories: Set<ResourceCategory>,
    cachePolicy: ManifestCachePolicy
  ) throws {
    guard categories == [.game] else { throw ManifestAdapterError.invalidRequest }
    if case .freshCache(let maxAgeSeconds) = cachePolicy, maxAgeSeconds == 0 {
      throw ManifestAdapterError.invalidRequest
    }
    self.release = release
    self.intent = intent
    self.categories = categories
    self.cachePolicy = cachePolicy
  }
}

public enum ManifestAvailability: String, Equatable, Sendable {
  case available
  case upToDate
  case preDownloadNotPublished
  case directLdiffUnavailable
}

public struct ChunkSizeSummary: Equatable, Sendable {
  public let targetInstalledBytes: UInt64
  public let referencedChunkCompressedBytes: UInt64
  public let uniqueChunkObjectBytes: UInt64
}

public struct ChunkManifest: Equatable, Sendable {
  public let fileCount: UInt64
  public let directoryCount: UInt64
  public let chunkReferenceCount: UInt64
  public let uniqueChunkObjectCount: UInt64
  public let sizes: ChunkSizeSummary
}

public struct LdiffSelectionSummary: Equatable, Sendable {
  public let manifestFileRecordCount: UInt64
  public let selectedPatchFileCount: UInt64
  public let fileRecordsWithoutSelectedPatchCount: UInt64
  public let selectedDeletionCount: UInt64
  public let uniquePatchObjectCount: UInt64
  public let selectedPatchObjectBytes: UInt64
}

public struct BuildManifest: Equatable, Sendable {
  public let targetVersion: GameVersion
  public let categories: [ResourceCategory: ChunkManifest]
}

public struct LdiffSelection: Equatable, Sendable {
  public let sourceVersion: GameVersion
  public let targetVersion: GameVersion
  public let categories: [ResourceCategory: LdiffSelectionSummary]

}

public struct BranchSummary: Equatable, Sendable {
  public let officialVersion: GameVersion
  public let preDownloadVersion: GameVersion?

}

public enum ManifestDataOrigin: Equatable, Sendable {
  case live
  case freshCache(ageSeconds: UInt64)
  case fixture(ManifestFixtureID)
}

public struct ManifestSHA256: Equatable, Hashable, Sendable {
  public let lowercaseHex: String

  init(_ value: String) throws {
    guard value.utf8.count == 64,
      value.utf8.allSatisfy({
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      })
    else {
      throw ManifestAdapterError.invalidManifest
    }
    lowercaseHex = value.lowercased()
  }
}

public struct ManifestSchemaBaseline: Equatable, Hashable, Sendable {
  public let value: String

  init(_ value: String) throws {
    guard ManifestInspectionFactory.isSafeASCII(value) else {
      throw ManifestAdapterError.invalidManifest
    }
    self.value = value
  }
}

public enum ManifestEvidenceArtifactKind: String, Equatable, Hashable, Sendable {
  case branchResponse
  case buildResponse
  case patchResponse
  case chunkManifest
  case diffManifest
  case fixtureDescriptor
}

public struct ManifestEvidenceArtifact: Equatable, Sendable {
  public let kind: ManifestEvidenceArtifactKind
  public let sha256: ManifestSHA256
  public let byteSize: UInt64

}

public struct ManifestEvidence: Equatable, Sendable {
  public let release: GameRelease
  public let profileRevision: UInt64
  public let observedAt: Date
  public let expiresAt: Date?
  public let schemaBaseline: ManifestSchemaBaseline
  public let artifacts: [ManifestEvidenceArtifact]

}

public enum ManifestObservationSeverity: String, Equatable, Sendable {
  case info
  case warning
  case error
}

public struct ManifestObservation: Equatable, Sendable {
  public let code: String
  public let severity: ManifestObservationSeverity
}

public struct ManifestInspection: Equatable, Sendable {
  public let release: GameRelease
  public let intent: ManifestIntent
  public let availability: ManifestAvailability
  public let branches: BranchSummary
  public let target: BuildManifest?
  public let selectedLdiff: LdiffSelection?
  public let origin: ManifestDataOrigin
  public let evidence: ManifestEvidence
  public let observations: [ManifestObservation]

}

public enum ManifestAdapterError: Error, Equatable, Sendable {
  case invalidRequest
  case missingEndpointEvidence
  case schemaDrift
  case invalidManifest
  case fixtureUnavailable(ManifestFixtureID)
}

public protocol ManifestAdapter: Sendable {
  func inspect(_ request: ManifestInspectionRequest) async throws -> ManifestInspection
}

public struct EvidenceGatedManifestAdapter: ManifestAdapter, Sendable {
  public init() {}

  public func inspect(_ request: ManifestInspectionRequest) async throws -> ManifestInspection {
    switch request.cachePolicy {
    case .fixtureOnly(let id): throw ManifestAdapterError.fixtureUnavailable(id)
    case .freshCache, .reloadIgnoringCache:
      throw ManifestAdapterError.missingEndpointEvidence
    }
  }
}
