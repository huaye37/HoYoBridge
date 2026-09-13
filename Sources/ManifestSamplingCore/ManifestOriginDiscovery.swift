import CryptoKit
import Foundation

package struct ManifestOriginPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let mainBuildPlan: MainBuildShapePlan
  package let buildSemanticPolicyVersion: UInt8
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let originPolicyVersion: UInt8
  package let semanticScopePolicy: String
  package let schemePolicy: String
  package let hostPolicy: String
  package let portPolicy: String
  package let credentialPolicy: String
  package let queryPolicy: String
  package let fragmentPolicy: String
  package let pathPolicy: String
  package let maximumPathBytes: UInt64
  package let maximumPathComponents: UInt64
  package let maximumPathComponentBytes: UInt64
  package let outputPolicy: String
  package let failurePolicy: String
  package let stopPolicy: String
}

extension ManifestOriginPlan: ManifestSamplingRedactedValue {}

package struct ManifestOriginReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchBodySHA256: String
  package let branchShapeSHA256: String
  package let branchReportSHA256: String
  package let buildBodySHA256: String
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let manifestSafeOrigin: String
  package let manifestPathComponentCount: UInt16
  package let manifestPathSHA256: String
  package let observedAtUnixSeconds: Int64
  package let requestCount: UInt8
}

extension ManifestOriginReceipt: ManifestSamplingRedactedValue {}

enum ManifestOriginDiscoveryProfile {
  static let profileID = "yaagl-ca78abc-cn-main-manifest-origin-v1"
  static let originPolicyVersion: UInt8 = 3
  static let maximumPathBytes = 2_048
  static let maximumPathComponents = 32
  static let maximumPathComponentBytes = 128
  static let plan = makePlan()

  static func inspect(
    capability: ValidatedMainBuildOriginReference
  ) throws -> ValidatedManifestOriginCandidate {
    try inspect(rawPrefix: capability.urlPrefix.rawValue)
  }

  static func inspect(
    rawPrefix: String
  ) throws -> ValidatedManifestOriginCandidate {
    guard let components = URLComponents(string: rawPrefix),
      components.scheme == "https",
      let host = components.host,
      components.port == nil,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      isSafeDNSHost(host),
      components.percentEncodedPath.utf8.count <= maximumPathBytes,
      components.percentEncodedPath.hasPrefix("/")
    else {
      throw ManifestSamplingError.originRejected
    }
    let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: true)
    guard !pathComponents.isEmpty, pathComponents.count <= maximumPathComponents,
      pathComponents.allSatisfy({ component in
        let value = String(component)
        return value != "." && value != ".."
          && value.utf8.count > 0
          && value.utf8.count <= maximumPathComponentBytes
          && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      })
    else {
      throw ManifestSamplingError.originRejected
    }
    let pathSHA256 = SHA256.hash(data: Data(components.percentEncodedPath.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return ValidatedManifestOriginCandidate(
      safeOrigin: "https://" + host.lowercased(),
      pathComponentCount: UInt16(pathComponents.count),
      pathSHA256: pathSHA256
    )
  }

  private static func makePlan() -> ManifestOriginPlan {
    let buildPolicy = MainBuildSemanticPolicy.observedCNV1
    let planWithoutPolicy = ManifestOriginPlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      mainBuildPlan: MainBuildShapeDiscoveryProfile.plan,
      buildSemanticPolicyVersion: buildPolicy.policyVersion,
      buildShapeSHA256: buildPolicy.expectedShapeSHA256,
      buildReportSHA256: buildPolicy.expectedReportSHA256,
      originPolicyVersion: originPolicyVersion,
      semanticScopePolicy: "tagUniqueGameAndURLPrefixOnly",
      schemePolicy: "exactHTTPS",
      hostPolicy: "lowercaseASCIIDNSNoIPNoTrailingDot",
      portPolicy: "absent",
      credentialPolicy: "noUserInfo",
      queryPolicy: "absent",
      fragmentPolicy: "absent",
      pathPolicy: "absoluteNoDotSegmentsHashOnlyOutput",
      maximumPathBytes: UInt64(maximumPathBytes),
      maximumPathComponents: UInt64(maximumPathComponents),
      maximumPathComponentBytes: UInt64(maximumPathComponentBytes),
      outputPolicy: "safeOriginPathCountAndSHAOnly",
      failurePolicy: "safeOriginStageCodeNoValue",
      stopPolicy: "originReceiptOnlyNoManifestRequest"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      ManifestOriginPolicyHasher.hash(planWithoutPolicy)
    )
  }

  private static func isSafeDNSHost(_ host: String) -> Bool {
    guard host == host.lowercased(), host.utf8.count <= 253,
      host.contains("."), !host.hasSuffix("."), !host.contains(":"),
      host.utf8.allSatisfy({
        (48...57).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46
      })
    else {
      return false
    }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2,
      labels.allSatisfy({ label in
        !label.isEmpty && label.utf8.count <= 63
          && label.first != "-" && label.last != "-"
      })
    else {
      return false
    }
    let looksLikeIPv4 =
      labels.count == 4
      && labels.allSatisfy { label in
        !label.isEmpty && label.allSatisfy(\.isNumber)
      }
    return !looksLikeIPv4
  }
}

struct ValidatedManifestOriginCandidate: Equatable, Sendable {
  let safeOrigin: String
  let pathComponentCount: UInt16
  let pathSHA256: String
}

extension ValidatedManifestOriginCandidate: ManifestSamplingRedactedValue {}

enum ManifestOriginPolicyHasher {
  static func hash(_ plan: ManifestOriginPlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed manifest origin policy")
    }
    var bytes = Data("MGBMANIFESTORIGINPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension ManifestOriginPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> ManifestOriginPlan {
    ManifestOriginPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      mainBuildPlan: mainBuildPlan,
      buildSemanticPolicyVersion: buildSemanticPolicyVersion,
      buildShapeSHA256: buildShapeSHA256,
      buildReportSHA256: buildReportSHA256,
      originPolicyVersion: originPolicyVersion,
      semanticScopePolicy: semanticScopePolicy,
      schemePolicy: schemePolicy,
      hostPolicy: hostPolicy,
      portPolicy: portPolicy,
      credentialPolicy: credentialPolicy,
      queryPolicy: queryPolicy,
      fragmentPolicy: fragmentPolicy,
      pathPolicy: pathPolicy,
      maximumPathBytes: maximumPathBytes,
      maximumPathComponents: maximumPathComponents,
      maximumPathComponentBytes: maximumPathComponentBytes,
      outputPolicy: outputPolicy,
      failurePolicy: failurePolicy,
      stopPolicy: stopPolicy
    )
  }
}
