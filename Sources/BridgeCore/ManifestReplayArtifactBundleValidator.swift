import CryptoKit
import Foundation

struct ManifestReplayArtifactData: Sendable {
  let kind: ManifestEvidenceArtifactKind
  let data: Data
}

extension ManifestReplayArtifactData: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  var description: String { "<redacted>" }
  var debugDescription: String { "<redacted>" }
  var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

struct ManifestReplayArtifactBundleLimits: Equatable, Sendable {
  static let `default` = ManifestReplayArtifactBundleLimits(
    branchResponseBytes: 1 * 1_024 * 1_024,
    buildResponseBytes: 8 * 1_024 * 1_024,
    patchResponseBytes: 8 * 1_024 * 1_024,
    chunkManifestBytes: 64 * 1_024 * 1_024,
    diffManifestBytes: 64 * 1_024 * 1_024,
    totalBytes: 128 * 1_024 * 1_024
  )

  let branchResponseBytes: UInt64
  let buildResponseBytes: UInt64
  let patchResponseBytes: UInt64
  let chunkManifestBytes: UInt64
  let diffManifestBytes: UInt64
  let totalBytes: UInt64

  init(
    branchResponseBytes: UInt64,
    buildResponseBytes: UInt64,
    patchResponseBytes: UInt64,
    chunkManifestBytes: UInt64,
    diffManifestBytes: UInt64,
    totalBytes: UInt64
  ) {
    self.branchResponseBytes = branchResponseBytes
    self.buildResponseBytes = buildResponseBytes
    self.patchResponseBytes = patchResponseBytes
    self.chunkManifestBytes = chunkManifestBytes
    self.diffManifestBytes = diffManifestBytes
    self.totalBytes = totalBytes
  }

  func maximumBytes(for kind: ManifestEvidenceArtifactKind) -> UInt64? {
    switch kind {
    case .branchResponse: branchResponseBytes
    case .buildResponse: buildResponseBytes
    case .patchResponse: patchResponseBytes
    case .chunkManifest: chunkManifestBytes
    case .diffManifest: diffManifestBytes
    case .fixtureDescriptor: nil
    }
  }

  fileprivate var doesNotExceedDefault: Bool {
    let defaults = Self.default
    return branchResponseBytes <= defaults.branchResponseBytes
      && buildResponseBytes <= defaults.buildResponseBytes
      && patchResponseBytes <= defaults.patchResponseBytes
      && chunkManifestBytes <= defaults.chunkManifestBytes
      && diffManifestBytes <= defaults.diffManifestBytes
      && totalBytes <= defaults.totalBytes
  }
}

struct ValidatedReplayArtifactData: Equatable, Sendable {
  let kind: ManifestEvidenceArtifactKind
  let data: Data
  let sha256: ManifestSHA256
  let byteSize: UInt64
  let manifestReferenceSHA256: ManifestReferenceDigest?

}

extension ValidatedReplayArtifactData: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  var description: String { "<redacted>" }
  var debugDescription: String { "<redacted>" }
  var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

/// Actual byte identity only. It does not prove semantic derivation or authorize replay.
struct ValidatedReplayArtifactBundle: Equatable, Sendable {
  let descriptor: ValidatedReplayDescriptor
  let externalArtifacts: [ValidatedReplayArtifactData]
  let byteEvidence: ManifestEvidence
  let totalByteSize: UInt64

  fileprivate init(
    descriptor: ValidatedReplayDescriptor,
    externalArtifacts: [ValidatedReplayArtifactData],
    byteEvidence: ManifestEvidence,
    totalByteSize: UInt64
  ) {
    self.descriptor = descriptor
    self.externalArtifacts = externalArtifacts
    self.byteEvidence = byteEvidence
    self.totalByteSize = totalByteSize
  }
}

extension ValidatedReplayArtifactBundle: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  var description: String { "<redacted>" }
  var debugDescription: String { "<redacted>" }
  var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

enum ManifestReplayArtifactBundleValidationError: Error, Equatable, Sendable {
  case invalidBundle
  case artifactMismatch
  case oversized
}

enum ManifestReplayArtifactBundleValidator {
  private static let hashChunkBytes = 64 * 1_024

  static func validate(
    descriptor: ValidatedReplayDescriptor,
    artifacts: [ManifestReplayArtifactData],
    limits: ManifestReplayArtifactBundleLimits = .default
  ) throws -> ValidatedReplayArtifactBundle {
    try Task.checkCancellation()
    let preflight = try preflight(
      descriptor: descriptor,
      artifacts: artifacts,
      limits: limits
    )
    var validated: [ValidatedReplayArtifactData] = []
    var evidenceArtifacts: [ManifestEvidenceArtifact] = []
    validated.reserveCapacity(preflight.ordered.count)
    evidenceArtifacts.reserveCapacity(preflight.ordered.count + 1)
    for item in preflight.ordered {
      try Task.checkCancellation()
      let snapshot = try ownedSnapshotAndSHA256(
        item.artifact.data,
        expectedCount: item.byteCount
      )
      guard snapshot.sha256 == item.binding.sha256.lowercaseHex else {
        throw ManifestReplayArtifactBundleValidationError.artifactMismatch
      }
      let evidence = try ManifestInspectionFactory.makeEvidenceArtifact(
        kind: item.artifact.kind,
        sha256: snapshot.sha256,
        byteSize: item.byteSize
      )
      validated.append(
        ValidatedReplayArtifactData(
          kind: item.artifact.kind,
          data: snapshot.data,
          sha256: evidence.sha256,
          byteSize: item.byteSize,
          manifestReferenceSHA256: item.binding.manifestReferenceSHA256
        ))
      evidenceArtifacts.append(evidence)
    }
    try Task.checkCancellation()
    evidenceArtifacts.append(
      try ManifestInspectionFactory.makeEvidenceArtifact(
        kind: .fixtureDescriptor,
        sha256: descriptor.fixtureDescriptorSHA256,
        byteSize: descriptor.fixtureDescriptorByteSize
      ))
    let byteEvidence = try ManifestInspectionFactory.makeEvidence(
      release: descriptor.expectedRequest.release,
      profileRevision: descriptor.profileRevision,
      observedAt: descriptor.observedAt,
      expiresAt: descriptor.expiresAt,
      schemaBaseline: descriptor.schemaBaseline.value,
      artifacts: evidenceArtifacts
    )
    try Task.checkCancellation()
    return ValidatedReplayArtifactBundle(
      descriptor: descriptor,
      externalArtifacts: validated,
      byteEvidence: byteEvidence,
      totalByteSize: preflight.totalByteSize
    )
  }

  private static func preflight(
    descriptor: ValidatedReplayDescriptor,
    artifacts: [ManifestReplayArtifactData],
    limits: ManifestReplayArtifactBundleLimits
  ) throws -> BundlePreflight {
    guard limits.doesNotExceedDefault,
      descriptor.fixtureDescriptorByteSize > 0,
      descriptor.fixtureDescriptorByteSize <= UInt64(ManifestReplayDescriptorDecoder.maximumBytes)
    else {
      throw ManifestReplayArtifactBundleValidationError.invalidBundle
    }
    let expectedKinds = ManifestInspectionFactory.expectedEvidenceArtifactKinds(
      availability: descriptor.availability,
      target: descriptor.target,
      selectedLdiff: descriptor.selectedLdiff,
      includesFixtureDescriptor: false
    )
    let bindings = descriptor.externalArtifactBindings
    guard bindings.map(\.kind) == expectedKinds,
      !expectedKinds.contains(.fixtureDescriptor),
      Set(expectedKinds).count == expectedKinds.count,
      artifacts.count == expectedKinds.count
    else {
      throw ManifestReplayArtifactBundleValidationError.invalidBundle
    }
    var byKind: [ManifestEvidenceArtifactKind: ManifestReplayArtifactData] = [:]
    var total = descriptor.fixtureDescriptorByteSize
    for artifact in artifacts {
      guard artifact.kind != .fixtureDescriptor, byKind[artifact.kind] == nil,
        expectedKinds.contains(artifact.kind), !artifact.data.isEmpty,
        UInt64(exactly: artifact.data.count) != nil
      else {
        throw ManifestReplayArtifactBundleValidationError.invalidBundle
      }
      byKind[artifact.kind] = artifact
    }
    let ordered = try bindings.map { binding -> PreflightArtifact in
      guard let artifact = byKind[binding.kind],
        let byteSize = UInt64(exactly: artifact.data.count)
      else {
        throw ManifestReplayArtifactBundleValidationError.invalidBundle
      }
      guard byteSize == binding.byteSize else {
        throw ManifestReplayArtifactBundleValidationError.artifactMismatch
      }
      guard let maximumBytes = limits.maximumBytes(for: binding.kind),
        byteSize <= maximumBytes
      else {
        throw ManifestReplayArtifactBundleValidationError.oversized
      }
      let (nextTotal, overflow) = total.addingReportingOverflow(byteSize)
      guard !overflow, nextTotal <= limits.totalBytes else {
        throw ManifestReplayArtifactBundleValidationError.oversized
      }
      total = nextTotal
      return PreflightArtifact(
        artifact: artifact,
        binding: binding,
        byteCount: artifact.data.count,
        byteSize: byteSize
      )
    }
    return BundlePreflight(ordered: ordered, totalByteSize: total)
  }

  private static func ownedSnapshotAndSHA256(
    _ source: Data,
    expectedCount: Int
  ) throws -> (data: Data, sha256: String) {
    guard source.count == expectedCount else {
      throw ManifestReplayArtifactBundleValidationError.artifactMismatch
    }
    var snapshot = Data()
    snapshot.reserveCapacity(expectedCount)
    var hasher = SHA256()
    var offset = 0
    while offset < expectedCount {
      try Task.checkCancellation()
      let end = min(offset + hashChunkBytes, expectedCount)
      let startIndex = source.index(source.startIndex, offsetBy: offset)
      let endIndex = source.index(source.startIndex, offsetBy: end)
      let ownedChunk = source.subdata(in: startIndex..<endIndex)
      snapshot.append(ownedChunk)
      hasher.update(data: ownedChunk)
      offset = end
    }
    guard snapshot.count == expectedCount else {
      throw ManifestReplayArtifactBundleValidationError.artifactMismatch
    }
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return (snapshot, digest)
  }
}

private struct PreflightArtifact {
  let artifact: ManifestReplayArtifactData
  let binding: ValidatedReplayExternalArtifactBinding
  let byteCount: Int
  let byteSize: UInt64
}

private struct BundlePreflight {
  let ordered: [PreflightArtifact]
  let totalByteSize: UInt64
}
