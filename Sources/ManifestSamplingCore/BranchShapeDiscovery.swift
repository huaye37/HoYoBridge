import CryptoKit
import Foundation

package struct BranchShapeReportPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let requestIdentitySHA256: String
  package let policySHA256: String
  package let method: String
  package let safeOrigin: String
  package let path: String
  package let maximumResponseBytes: UInt64
  package let tlsPolicy: String
  package let authenticationPolicy: String
  package let finalURLPolicy: String
  package let statusPolicy: String
  package let contentTypePolicy: String
  package let contentEncodingPolicy: String
  package let retryPolicy: String
  package let cachePolicy: String
  package let cookiePolicy: String
  package let redirectPolicy: String
  package let persistencePolicy: String
  package let requestTimeoutSeconds: UInt16
  package let resourceTimeoutSeconds: UInt16
  package let reportPolicyVersion: UInt8
  package let knownKeyNames: [String]
  package let unknownKeyPolicy: String
  package let scalarPolicy: String
  package let objectPolicy: String
  package let arrayPolicy: String
  package let maximumReportNodeCount: UInt64
  package let maximumArrayElementShapes: UInt64
  package let maximumUnknownKeyCount: UInt64
  package let maximumCanonicalReportBytes: UInt64
  package let maximumCanonicalReceiptBytes: UInt64
  package let priorShapePolicyVersion: UInt8
  package let priorShapeSHA256: String
  package let priorGameBranchEntryCount: UInt64
  package let stopPolicy: String
}

extension BranchShapeReportPlan: ManifestSamplingRedactedValue {}

package struct BranchShapeReportReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let requestIdentitySHA256: String
  package let policySHA256: String
  package let statusCode: UInt16
  package let observedAtUnixSeconds: Int64
  package let bodySHA256: String
  package let byteSize: UInt64
  package let valueFreeShapePolicyVersion: UInt8
  package let valueFreeShapeSHA256: String
  package let gameBranchEntryCount: UInt64
  package let reportPolicyVersion: UInt8
  package let reportSHA256: String
  package let canonicalReportByteSize: UInt64
  package let matchesPriorShape: Bool
  package let shape: SafeJSONShapeNode
}

extension BranchShapeReportReceipt: ManifestSamplingRedactedValue {}

enum BranchShapeDiscoveryProfile {
  static let maximumCanonicalReceiptBytes = 320 * 1_024
  static let priorShapePolicyVersion: UInt8 = 1
  static let priorShapeSHA256 = "a45e5b73aa00286cd3b054b11902a21db83b003f6f360ddb5446c82a82c22633"
  static let priorGameBranchEntryCount: UInt64 = 1
  static let profileID = "yaagl-ca78abc-cn-getGameBranches-a1b-shape-v1"
  static let plan: BranchShapeReportPlan = makePlan()

  static func matchesPriorShape(
    policyVersion: UInt8,
    sha256: String,
    gameBranchEntryCount: UInt64
  ) -> Bool {
    policyVersion == priorShapePolicyVersion
      && sha256 == priorShapeSHA256
      && gameBranchEntryCount == priorGameBranchEntryCount
  }

  private static func makePlan() -> BranchShapeReportPlan {
    let base = BranchDiscoveryProfile.cn
    let limits = SafeJSONShapeReportLimits.standard
    let planWithoutPolicy = BranchShapeReportPlan(
      schemaVersion: 1,
      profileID: profileID,
      requestIdentitySHA256: base.requestIdentitySHA256,
      policySHA256: "",
      method: "GET",
      safeOrigin: "https://hyp-api.mihoyo.com",
      path: "/hyp/hyp-connect/api/getGameBranches",
      maximumResponseBytes: BranchDiscoveryClient.maximumResponseBytes,
      tlsPolicy: "systemTrustMinimumTLS12",
      authenticationPolicy: "serverTrustExactHost",
      finalURLPolicy: "exact",
      statusPolicy: "exact200",
      contentTypePolicy: "applicationJSONUTF8",
      contentEncodingPolicy: "identity",
      retryPolicy: "singleTaskNoApplicationRetry",
      cachePolicy: "none",
      cookiePolicy: "noSendNoStoreIgnoreResponseSetCookie",
      redirectPolicy: "reject",
      persistencePolicy: "responseBodyMemoryOnlyNoExplicitFileWrite",
      requestTimeoutSeconds: 15,
      resourceTimeoutSeconds: 20,
      reportPolicyVersion: SafeJSONShapeReportPolicyV1.policyVersion,
      knownKeyNames: SafeJSONShapeReportPolicyV1.knownKeyNames,
      unknownKeyPolicy: SafeJSONShapeReportPolicyV1.unknownKeyPolicy,
      scalarPolicy: SafeJSONShapeReportPolicyV1.scalarPolicy,
      objectPolicy: SafeJSONShapeReportPolicyV1.objectPolicy,
      arrayPolicy: SafeJSONShapeReportPolicyV1.arrayPolicy,
      maximumReportNodeCount: UInt64(limits.maximumNodeCount),
      maximumArrayElementShapes: UInt64(limits.maximumArrayElementShapes),
      maximumUnknownKeyCount: UInt64(limits.maximumUnknownKeyCount),
      maximumCanonicalReportBytes: UInt64(limits.maximumCanonicalBytes),
      maximumCanonicalReceiptBytes: UInt64(maximumCanonicalReceiptBytes),
      priorShapePolicyVersion: priorShapePolicyVersion,
      priorShapeSHA256: priorShapeSHA256,
      priorGameBranchEntryCount: priorGameBranchEntryCount,
      stopPolicy: "receiptOnlyNoCapabilityNoFollowup"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      BranchShapeReportPolicyHasher.hash(planWithoutPolicy)
    )
  }
}

enum BranchShapeReportPolicyHasher {
  static func hash(_ plan: BranchShapeReportPlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        BranchShapeReportPolicyMaterial(plan)
      )
    else {
      preconditionFailure("Invalid fixed branch shape report policy")
    }
    var bytes = Data("MGBMANIFESTSAMPLESHAPEPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

private struct BranchShapeReportPolicyMaterial: Encodable {
  let plan: BranchShapeReportPlan

  init(_ plan: BranchShapeReportPlan) {
    self.plan = plan.replacingPolicySHA256("")
  }

  func encode(to encoder: any Encoder) throws {
    try plan.encode(to: encoder)
  }
}

extension BranchShapeReportPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> BranchShapeReportPlan {
    BranchShapeReportPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      requestIdentitySHA256: requestIdentitySHA256,
      policySHA256: value,
      method: method,
      safeOrigin: safeOrigin,
      path: path,
      maximumResponseBytes: maximumResponseBytes,
      tlsPolicy: tlsPolicy,
      authenticationPolicy: authenticationPolicy,
      finalURLPolicy: finalURLPolicy,
      statusPolicy: statusPolicy,
      contentTypePolicy: contentTypePolicy,
      contentEncodingPolicy: contentEncodingPolicy,
      retryPolicy: retryPolicy,
      cachePolicy: cachePolicy,
      cookiePolicy: cookiePolicy,
      redirectPolicy: redirectPolicy,
      persistencePolicy: persistencePolicy,
      requestTimeoutSeconds: requestTimeoutSeconds,
      resourceTimeoutSeconds: resourceTimeoutSeconds,
      reportPolicyVersion: reportPolicyVersion,
      knownKeyNames: knownKeyNames,
      unknownKeyPolicy: unknownKeyPolicy,
      scalarPolicy: scalarPolicy,
      objectPolicy: objectPolicy,
      arrayPolicy: arrayPolicy,
      maximumReportNodeCount: maximumReportNodeCount,
      maximumArrayElementShapes: maximumArrayElementShapes,
      maximumUnknownKeyCount: maximumUnknownKeyCount,
      maximumCanonicalReportBytes: maximumCanonicalReportBytes,
      maximumCanonicalReceiptBytes: maximumCanonicalReceiptBytes,
      priorShapePolicyVersion: priorShapePolicyVersion,
      priorShapeSHA256: priorShapeSHA256,
      priorGameBranchEntryCount: priorGameBranchEntryCount,
      stopPolicy: stopPolicy
    )
  }
}
