import CryptoKit
import Foundation

package struct MainBuildShapePlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchRequestIdentitySHA256: String
  package let branchSafeOrigin: String
  package let branchPath: String
  package let buildSafeOrigin: String
  package let buildPath: String
  package let branchMethod: String
  package let buildMethod: String
  package let buildQueryNames: [String]
  package let buildRequestTemplateSHA256: String
  package let maximumBranchResponseBytes: UInt64
  package let maximumBuildResponseBytes: UInt64
  package let maximumTotalResponseBytes: UInt64
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
  package let branchSemanticPolicyVersion: UInt8
  package let branchShapePolicyVersion: UInt8
  package let branchShapeSHA256: String
  package let branchGameBranchEntryCount: UInt64
  package let branchReportPolicyVersion: UInt8
  package let branchReportSHA256: String
  package let branchCanonicalReportByteSize: UInt64
  package let buildShapePolicyVersion: UInt8
  package let buildReportPolicyVersion: UInt8
  package let buildKnownKeyNames: [String]
  package let buildUnknownKeyPolicy: String
  package let buildScalarPolicy: String
  package let buildObjectPolicy: String
  package let buildArrayPolicy: String
  package let maximumCanonicalReportBytes: UInt64
  package let maximumCanonicalReceiptBytes: UInt64
  package let stopPolicy: String
}

extension MainBuildShapePlan: ManifestSamplingRedactedValue {}

package struct MainBuildShapeReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchRequestIdentitySHA256: String
  package let buildRequestTemplateSHA256: String
  package let branchObservedAtUnixSeconds: Int64
  package let branchBodySHA256: String
  package let branchByteSize: UInt64
  package let branchShapeSHA256: String
  package let branchReportSHA256: String
  package let buildObservedAtUnixSeconds: Int64
  package let buildStatusCode: UInt16
  package let buildBodySHA256: String
  package let buildByteSize: UInt64
  package let buildShapePolicyVersion: UInt8
  package let buildShapeSHA256: String
  package let buildReportPolicyVersion: UInt8
  package let buildReportSHA256: String
  package let canonicalBuildReportByteSize: UInt64
  package let requestCount: UInt8
  package let shape: SafeJSONShapeNode
}

extension MainBuildShapeReceipt: ManifestSamplingRedactedValue {}

enum MainBuildShapeDiscoveryProfile {
  static let profileID = "yaagl-ca78abc-cn-main-getBuild-shape-v1"
  static let maximumBuildResponseBytes: UInt64 = 8 * 1_024 * 1_024
  static let maximumTotalResponseBytes: UInt64 = 9 * 1_024 * 1_024
  static let maximumCanonicalReceiptBytes = 320 * 1_024
  static let buildOrigin = "https://api-takumi.mihoyo.com"
  static let buildPath = "/downloader/sophon_chunk/api/getBuild"
  static let buildQueryNames = ["branch", "package_id", "password"]
  static let buildRequestTemplateSHA256 = makeBuildRequestTemplateSHA256()
  static let plan = makePlan()

  static func makeBuildRequest(
    capability: ValidatedCNBranchCapability
  ) throws -> MainBuildRequest {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api-takumi.mihoyo.com"
    components.path = buildPath
    components.queryItems = [
      URLQueryItem(name: "branch", value: capability.main.branch.rawValue),
      URLQueryItem(name: "package_id", value: capability.main.packageID.rawValue),
      URLQueryItem(name: "password", value: capability.main.password.rawValue),
    ]
    guard components.scheme == "https", components.host == "api-takumi.mihoyo.com",
      components.port == nil, components.user == nil, components.password == nil,
      components.fragment == nil, components.path == buildPath,
      components.queryItems?.map(\.name) == buildQueryNames,
      let url = components.url
    else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.httpBody = nil
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let requestIdentitySHA256 = BranchDiscoveryProfile.requestIdentity(for: request)
    guard requestIdentitySHA256.count == 64 else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    return MainBuildRequest(url: url, requestIdentitySHA256: requestIdentitySHA256)
  }

  private static func makePlan() -> MainBuildShapePlan {
    let branchPolicy = BranchSemanticPolicy.observedCNV1
    let planWithoutPolicy = MainBuildShapePlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      branchRequestIdentitySHA256: branchPolicy.expectedRequestIdentitySHA256,
      branchSafeOrigin: "https://hyp-api.mihoyo.com",
      branchPath: "/hyp/hyp-connect/api/getGameBranches",
      buildSafeOrigin: buildOrigin,
      buildPath: buildPath,
      branchMethod: "GET",
      buildMethod: "GET",
      buildQueryNames: buildQueryNames,
      buildRequestTemplateSHA256: buildRequestTemplateSHA256,
      maximumBranchResponseBytes: BranchDiscoveryClient.maximumResponseBytes,
      maximumBuildResponseBytes: maximumBuildResponseBytes,
      maximumTotalResponseBytes: maximumTotalResponseBytes,
      tlsPolicy: "systemTrustMinimumTLS12",
      authenticationPolicy: "serverTrustExactOperationHost",
      finalURLPolicy: "exactPerOperation",
      statusPolicy: "exact200PerOperation",
      contentTypePolicy: "applicationJSONUTF8",
      contentEncodingPolicy: "identity",
      retryPolicy: "twoSequentialTasksNoApplicationRetry",
      cachePolicy: "none",
      cookiePolicy: "noSendNoStoreIgnoreResponseSetCookie",
      redirectPolicy: "reject",
      persistencePolicy: "responseBodiesMemoryOnlyNoExplicitFileWrite",
      branchSemanticPolicyVersion: branchPolicy.policyVersion,
      branchShapePolicyVersion: branchPolicy.expectedShapePolicyVersion,
      branchShapeSHA256: branchPolicy.expectedShapeSHA256,
      branchGameBranchEntryCount: branchPolicy.expectedGameBranchEntryCount,
      branchReportPolicyVersion: branchPolicy.expectedReportPolicyVersion,
      branchReportSHA256: branchPolicy.expectedReportSHA256,
      branchCanonicalReportByteSize: branchPolicy.expectedCanonicalReportByteSize,
      buildShapePolicyVersion: 1,
      buildReportPolicyVersion: SafeJSONShapeReportPolicyV1.policyVersion,
      buildKnownKeyNames: SafeJSONShapeReportPolicyV1.knownKeyNames,
      buildUnknownKeyPolicy: SafeJSONShapeReportPolicyV1.unknownKeyPolicy,
      buildScalarPolicy: SafeJSONShapeReportPolicyV1.scalarPolicy,
      buildObjectPolicy: SafeJSONShapeReportPolicyV1.objectPolicy,
      buildArrayPolicy: SafeJSONShapeReportPolicyV1.arrayPolicy,
      maximumCanonicalReportBytes: UInt64(
        SafeJSONShapeReportLimits.standard.maximumCanonicalBytes
      ),
      maximumCanonicalReceiptBytes: UInt64(maximumCanonicalReceiptBytes),
      stopPolicy: "buildReceiptOnlyNoManifestNoPayload"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      MainBuildShapePolicyHasher.hash(planWithoutPolicy)
    )
  }

  private static func makeBuildRequestTemplateSHA256() -> String {
    let material = [
      "MGB_CN_MAIN_GETBUILD_TEMPLATE", "1", "GET", buildOrigin, buildPath,
      buildQueryNames.joined(separator: ","), "Accept=application/json",
      "Accept-Encoding=identity", "body=nil", "handleCookies=false",
    ].joined(separator: "\0")
    return SHA256.hash(data: Data(material.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

struct MainBuildRequest: Sendable {
  let url: URL
  let requestIdentitySHA256: String
}

extension MainBuildRequest: ManifestSamplingRedactedValue {}

enum MainBuildShapePolicyHasher {
  static func hash(_ plan: MainBuildShapePlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed main build shape policy")
    }
    var bytes = Data("MGBMAINBUILDSHAPEPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension MainBuildShapePlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> MainBuildShapePlan {
    MainBuildShapePlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      branchRequestIdentitySHA256: branchRequestIdentitySHA256,
      branchSafeOrigin: branchSafeOrigin,
      branchPath: branchPath,
      buildSafeOrigin: buildSafeOrigin,
      buildPath: buildPath,
      branchMethod: branchMethod,
      buildMethod: buildMethod,
      buildQueryNames: buildQueryNames,
      buildRequestTemplateSHA256: buildRequestTemplateSHA256,
      maximumBranchResponseBytes: maximumBranchResponseBytes,
      maximumBuildResponseBytes: maximumBuildResponseBytes,
      maximumTotalResponseBytes: maximumTotalResponseBytes,
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
      branchSemanticPolicyVersion: branchSemanticPolicyVersion,
      branchShapePolicyVersion: branchShapePolicyVersion,
      branchShapeSHA256: branchShapeSHA256,
      branchGameBranchEntryCount: branchGameBranchEntryCount,
      branchReportPolicyVersion: branchReportPolicyVersion,
      branchReportSHA256: branchReportSHA256,
      branchCanonicalReportByteSize: branchCanonicalReportByteSize,
      buildShapePolicyVersion: buildShapePolicyVersion,
      buildReportPolicyVersion: buildReportPolicyVersion,
      buildKnownKeyNames: buildKnownKeyNames,
      buildUnknownKeyPolicy: buildUnknownKeyPolicy,
      buildScalarPolicy: buildScalarPolicy,
      buildObjectPolicy: buildObjectPolicy,
      buildArrayPolicy: buildArrayPolicy,
      maximumCanonicalReportBytes: maximumCanonicalReportBytes,
      maximumCanonicalReceiptBytes: maximumCanonicalReceiptBytes,
      stopPolicy: stopPolicy
    )
  }
}
