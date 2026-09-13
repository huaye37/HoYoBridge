import CryptoKit
import Foundation

package struct ManifestStructurePlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let bodyPlan: ManifestBodyPlan
  package let expectedCompressedBodySHA256: String
  package let profileRevision: UInt64
  package let release: String
  package let category: String
  package let schemaBaseline: String
  package let maximumZstdWindowLog: UInt32
  package let manifestContentTypePolicy: String
  package let chunkInfoField7Policy: String
  package let inspectionPolicy: String
  package let failurePolicy: String
  package let outputPolicy: String
  package let stopPolicy: String
}

extension ManifestStructurePlan: ManifestSamplingRedactedValue {}

package struct ManifestStructureReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchBodySHA256: String
  package let buildBodySHA256: String
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let compressedBodySHA256: String
  package let compressedByteSize: UInt64
  package let decompressedBodySHA256: String
  package let decompressedByteSize: UInt64
  package let wirePolicyVersion: UInt8
  package let fileCount: UInt64
  package let directoryCount: UInt64
  package let chunkReferenceCount: UInt64
  package let uniqueChunkObjectCount: UInt64
  package let targetInstalledBytes: UInt64
  package let referencedChunkCompressedBytes: UInt64
  package let uniqueChunkObjectBytes: UInt64
  package let wireNodeCount: UInt64
  package let wireStringBytes: UInt64
  package let observedAtUnixSeconds: Int64
  package let requestCount: UInt8
}

extension ManifestStructureReceipt: ManifestSamplingRedactedValue {}

package struct ManifestLiveBodyInspectionInput: Sendable {
  package let data: Data
  package let compressedSHA256: String
  package let byteSize: UInt64
  package let manifestID: String
  package let profileRevision: UInt64
  package let release: String
  package let category: String
  package let schemaBaseline: String

  init(
    data: Data,
    compressedSHA256: String,
    byteSize: UInt64,
    manifestID: String,
    plan: ManifestStructurePlan
  ) {
    self.data = data
    self.compressedSHA256 = compressedSHA256
    self.byteSize = byteSize
    self.manifestID = manifestID
    profileRevision = plan.profileRevision
    release = plan.release
    category = plan.category
    schemaBaseline = plan.schemaBaseline
  }
}

extension ManifestLiveBodyInspectionInput: ManifestSamplingRedactedValue {}

package struct ManifestChunkStructuralEvidence: Equatable, Sendable {
  package let decompressedBodySHA256: String
  package let decompressedByteSize: UInt64
  package let wirePolicyVersion: UInt8
  package let fileCount: UInt64
  package let directoryCount: UInt64
  package let chunkReferenceCount: UInt64
  package let uniqueChunkObjectCount: UInt64
  package let targetInstalledBytes: UInt64
  package let referencedChunkCompressedBytes: UInt64
  package let uniqueChunkObjectBytes: UInt64
  package let wireNodeCount: UInt64
  package let wireStringBytes: UInt64
  package let payloadCandidate: ManifestChunkPayloadCandidate?

  package init(
    decompressedBodySHA256: String,
    decompressedByteSize: UInt64,
    wirePolicyVersion: UInt8,
    fileCount: UInt64,
    directoryCount: UInt64,
    chunkReferenceCount: UInt64,
    uniqueChunkObjectCount: UInt64,
    targetInstalledBytes: UInt64,
    referencedChunkCompressedBytes: UInt64,
    uniqueChunkObjectBytes: UInt64,
    wireNodeCount: UInt64,
    wireStringBytes: UInt64,
    payloadCandidate: ManifestChunkPayloadCandidate? = nil
  ) {
    self.decompressedBodySHA256 = decompressedBodySHA256
    self.decompressedByteSize = decompressedByteSize
    self.wirePolicyVersion = wirePolicyVersion
    self.fileCount = fileCount
    self.directoryCount = directoryCount
    self.chunkReferenceCount = chunkReferenceCount
    self.uniqueChunkObjectCount = uniqueChunkObjectCount
    self.targetInstalledBytes = targetInstalledBytes
    self.referencedChunkCompressedBytes = referencedChunkCompressedBytes
    self.uniqueChunkObjectBytes = uniqueChunkObjectBytes
    self.wireNodeCount = wireNodeCount
    self.wireStringBytes = wireStringBytes
    self.payloadCandidate = payloadCandidate
  }
}

extension ManifestChunkStructuralEvidence: ManifestSamplingRedactedValue {}

package struct ManifestChunkPayloadCandidate: Equatable, Sendable {
  package let objectID: String
  package let compressedBytes: UInt64
  package let uncompressedBytes: UInt64
  package let uncompressedMD5: String
  package let compressedXXHash: UInt64
  package let wireField7OpaqueHash: String

  package init(
    objectID: String,
    compressedBytes: UInt64,
    uncompressedBytes: UInt64,
    uncompressedMD5: String,
    compressedXXHash: UInt64,
    wireField7OpaqueHash: String
  ) {
    self.objectID = objectID
    self.compressedBytes = compressedBytes
    self.uncompressedBytes = uncompressedBytes
    self.uncompressedMD5 = uncompressedMD5
    self.compressedXXHash = compressedXXHash
    self.wireField7OpaqueHash = wireField7OpaqueHash
  }
}

extension ManifestChunkPayloadCandidate: ManifestSamplingRedactedValue {}

package protocol ManifestBodyStructurallyInspecting: Sendable {
  func inspect(
    _ input: ManifestLiveBodyInspectionInput
  ) throws -> ManifestChunkStructuralEvidence
}

enum ManifestStructureDiscoveryProfile {
  static let profileID = "yaagl-ca78abc-cn-main-manifest-structure-v1"
  static let expectedCompressedBodySHA256 =
    "ca70fab422a2324aaece888534b9f013d4daf6e2c4430c6edf4da30a3e204c82"
  static let plan = makePlan()

  private static func makePlan() -> ManifestStructurePlan {
    let planWithoutPolicy = ManifestStructurePlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      bodyPlan: ManifestBodyDiscoveryProfile.plan,
      expectedCompressedBodySHA256: expectedCompressedBodySHA256,
      profileRevision: 2,
      release: "genshinOfficialCN",
      category: "game",
      schemaBaseline: "mgb-observed-cn-sophon-protobuf-structural-v2",
      maximumZstdWindowLog: 24,
      manifestContentTypePolicy: "applicationOctetStreamWithAtMostFourBoundedASCIIParameters",
      chunkInfoField7Policy: "requiredLowercaseHex32OpaqueNoIntegrityClaim",
      inspectionPolicy: "boundedZstdThenWireBudgetThenFixedStructuralMapper",
      failurePolicy: "branchBuildManifestHeaderZstdWireAndStructuralCodeNoValue",
      outputPolicy: "aggregateCountsAndBytesOnlyNoPathsObjectsOrRawData",
      stopPolicy: "structureReceiptOnlyNoRegistryNoPayload"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      ManifestStructurePolicyHasher.hash(planWithoutPolicy)
    )
  }
}

enum ManifestStructurePolicyHasher {
  static func hash(_ plan: ManifestStructurePlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed manifest structure policy")
    }
    var bytes = Data("MGBMANIFESTSTRUCTUREPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension ManifestStructurePlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> ManifestStructurePlan {
    ManifestStructurePlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      bodyPlan: bodyPlan,
      expectedCompressedBodySHA256: expectedCompressedBodySHA256,
      profileRevision: profileRevision,
      release: release,
      category: category,
      schemaBaseline: schemaBaseline,
      maximumZstdWindowLog: maximumZstdWindowLog,
      manifestContentTypePolicy: manifestContentTypePolicy,
      chunkInfoField7Policy: chunkInfoField7Policy,
      inspectionPolicy: inspectionPolicy,
      failurePolicy: failurePolicy,
      outputPolicy: outputPolicy,
      stopPolicy: stopPolicy
    )
  }
}
