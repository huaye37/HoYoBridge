import CryptoKit
import Foundation

package struct ChunkOriginPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let mainBuildPlan: MainBuildShapePlan
  package let buildSemanticPolicyVersion: UInt8
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let originPolicyVersion: UInt8
  package let semanticScopePolicy: String
  package let urlPolicy: String
  package let outputPolicy: String
  package let failurePolicy: String
  package let stopPolicy: String
}

extension ChunkOriginPlan: ManifestSamplingRedactedValue {}

package struct ChunkOriginReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchBodySHA256: String
  package let buildBodySHA256: String
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let chunkSafeOrigin: String
  package let chunkPathComponentCount: UInt16
  package let chunkPathSHA256: String
  package let observedAtUnixSeconds: Int64
  package let requestCount: UInt8
}

extension ChunkOriginReceipt: ManifestSamplingRedactedValue {}

enum ChunkOriginDiscoveryProfile {
  static let profileID = "yaagl-ca78abc-cn-main-chunk-origin-v1"
  static let originPolicyVersion: UInt8 = 1
  static let plan = makePlan()

  static func inspect(
    capability: ValidatedMainBuildChunkOriginReference
  ) throws -> ValidatedManifestOriginCandidate {
    try ManifestOriginDiscoveryProfile.inspect(rawPrefix: capability.urlPrefix.rawValue)
  }

  private static func makePlan() -> ChunkOriginPlan {
    let buildPolicy = MainBuildSemanticPolicy.observedCNV1
    let planWithoutPolicy = ChunkOriginPlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      mainBuildPlan: MainBuildShapeDiscoveryProfile.plan,
      buildSemanticPolicyVersion: buildPolicy.policyVersion,
      buildShapeSHA256: buildPolicy.expectedShapeSHA256,
      buildReportSHA256: buildPolicy.expectedReportSHA256,
      originPolicyVersion: originPolicyVersion,
      semanticScopePolicy: "tagUniqueGameAndChunkURLPrefixOnly",
      urlPolicy: "exactHTTPSLowercaseASCIIDNSNoIPPortCredentialsQueryFragmentOrDotSegments",
      outputPolicy: "safeOriginPathCountAndSHAOnly",
      failurePolicy: "safeChunkOriginStageCodeNoValue",
      stopPolicy: "chunkOriginReceiptOnlyNoManifestOrPayloadRequest"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      ChunkOriginPolicyHasher.hash(planWithoutPolicy)
    )
  }
}

enum ChunkOriginPolicyHasher {
  static func hash(_ plan: ChunkOriginPlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed chunk origin policy")
    }
    var bytes = Data("MGBCHUNKORIGINPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension ChunkOriginPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> ChunkOriginPlan {
    ChunkOriginPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      mainBuildPlan: mainBuildPlan,
      buildSemanticPolicyVersion: buildSemanticPolicyVersion,
      buildShapeSHA256: buildShapeSHA256,
      buildReportSHA256: buildReportSHA256,
      originPolicyVersion: originPolicyVersion,
      semanticScopePolicy: semanticScopePolicy,
      urlPolicy: urlPolicy,
      outputPolicy: outputPolicy,
      failurePolicy: failurePolicy,
      stopPolicy: stopPolicy
    )
  }
}
