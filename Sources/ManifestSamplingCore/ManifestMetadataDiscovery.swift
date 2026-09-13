import CryptoKit
import Foundation

package struct ManifestMetadataPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let originPlan: ManifestOriginPlan
  package let manifestSafeOrigin: String
  package let manifestPrefixPathComponentCount: UInt16
  package let manifestPrefixPathSHA256: String
  package let manifestMethod: String
  package let manifestRequestTemplateSHA256: String
  package let manifestIDPolicy: String
  package let requestAccept: String
  package let requestContentEncoding: String
  package let statusPolicy: String
  package let responseMetadataPolicy: String
  package let maximumDeclaredContentLength: UInt64
  package let redirectPolicy: String
  package let authenticationPolicy: String
  package let cookiePolicy: String
  package let cachePolicy: String
  package let persistencePolicy: String
  package let outputPolicy: String
  package let stopPolicy: String
}

extension ManifestMetadataPlan: ManifestSamplingRedactedValue {}

package struct ManifestMetadataReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchBodySHA256: String
  package let buildBodySHA256: String
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let manifestSafeOrigin: String
  package let manifestPrefixPathComponentCount: UInt16
  package let manifestPrefixPathSHA256: String
  package let manifestRequestPathSHA256: String
  package let statusCode: UInt16
  package let contentTypeKind: String
  package let contentEncodingKind: String
  package let contentLengthState: String
  package let declaredContentLength: UInt64?
  package let observedAtUnixSeconds: Int64
  package let requestCount: UInt8
  package let responseBodyAccepted: Bool
}

extension ManifestMetadataReceipt: ManifestSamplingRedactedValue {}

struct ManifestResponseMetadata: Equatable, Sendable {
  let statusCode: UInt16
  let contentTypeKind: String
  let contentEncodingKind: String
  let contentLengthState: String
  let declaredContentLength: UInt64?
  let observedAtUnixSeconds: Int64
}

extension ManifestResponseMetadata: ManifestSamplingRedactedValue {}

enum ManifestMetadataDiscoveryProfile {
  static let profileID = "yaagl-ca78abc-cn-main-manifest-metadata-v1"
  static let maximumDeclaredContentLength: UInt64 = 64 * 1_024 * 1_024
  static let originPin = ManifestOriginPin(
    safeOrigin: "https://autopatchcn.yuanshen.com",
    pathComponentCount: 5,
    pathSHA256: "ea1f952ad03a4218f39f3c89567aac56d03b1bd88252f116f1781249cd7b0485"
  )
  static let manifestRequestTemplateSHA256 = makeRequestTemplateSHA256()
  static let plan = makePlan()

  static func requestIdentity(
    for url: URL
  ) -> String {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.httpBody = nil
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return BranchDiscoveryProfile.requestIdentity(for: request)
  }

  static func requestPathSHA256(
    _ url: URL,
    expectedSafeOrigin: String = originPin.safeOrigin
  ) throws -> String {
    let expectedHost = URL(string: expectedSafeOrigin)?.host
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "https", components.host == expectedHost,
      components.port == nil, components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      !components.percentEncodedPath.isEmpty
    else {
      throw ManifestSamplingError.originRejected
    }
    return SHA256.hash(data: Data(components.percentEncodedPath.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func makePlan() -> ManifestMetadataPlan {
    let planWithoutPolicy = ManifestMetadataPlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      originPlan: ManifestOriginDiscoveryProfile.plan,
      manifestSafeOrigin: originPin.safeOrigin,
      manifestPrefixPathComponentCount: originPin.pathComponentCount,
      manifestPrefixPathSHA256: originPin.pathSHA256,
      manifestMethod: "GET",
      manifestRequestTemplateSHA256: manifestRequestTemplateSHA256,
      manifestIDPolicy: "singleASCIIUnreservedComponent1To256Bytes",
      requestAccept: "application/octet-stream",
      requestContentEncoding: "identity",
      statusPolicy: "exact200",
      responseMetadataPolicy: "safeClassificationsBeforeBodyDelivery",
      maximumDeclaredContentLength: maximumDeclaredContentLength,
      redirectPolicy: "reject",
      authenticationPolicy: "serverTrustExactManifestHost",
      cookiePolicy: "noSendNoStoreIgnoreResponseSetCookie",
      cachePolicy: "none",
      persistencePolicy: "noManifestResponseBodyAcceptedNoExplicitFileWrite",
      outputPolicy: "safeHeadersAndRequestPathSHAOnly",
      stopPolicy: "metadataReceiptOnlyNoBodyNoPayload"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      ManifestMetadataPolicyHasher.hash(planWithoutPolicy)
    )
  }

  private static func makeRequestTemplateSHA256() -> String {
    let material = [
      "MGB_CN_MAIN_MANIFEST_METADATA_REQUEST_TEMPLATE", "1", "GET",
      originPin.safeOrigin, String(originPin.pathComponentCount), originPin.pathSHA256,
      "manifestID=singleASCIIUnreservedComponent1To256Bytes",
      "Accept=application/octet-stream", "Accept-Encoding=identity", "body=nil",
      "handleCookies=false",
    ].joined(separator: "\0")
    return SHA256.hash(data: Data(material.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

enum ManifestMetadataPolicyHasher {
  static func hash(_ plan: ManifestMetadataPlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed manifest metadata policy")
    }
    var bytes = Data("MGBMANIFESTMETADATAPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension ManifestMetadataPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> ManifestMetadataPlan {
    ManifestMetadataPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      originPlan: originPlan,
      manifestSafeOrigin: manifestSafeOrigin,
      manifestPrefixPathComponentCount: manifestPrefixPathComponentCount,
      manifestPrefixPathSHA256: manifestPrefixPathSHA256,
      manifestMethod: manifestMethod,
      manifestRequestTemplateSHA256: manifestRequestTemplateSHA256,
      manifestIDPolicy: manifestIDPolicy,
      requestAccept: requestAccept,
      requestContentEncoding: requestContentEncoding,
      statusPolicy: statusPolicy,
      responseMetadataPolicy: responseMetadataPolicy,
      maximumDeclaredContentLength: maximumDeclaredContentLength,
      redirectPolicy: redirectPolicy,
      authenticationPolicy: authenticationPolicy,
      cookiePolicy: cookiePolicy,
      cachePolicy: cachePolicy,
      persistencePolicy: persistencePolicy,
      outputPolicy: outputPolicy,
      stopPolicy: stopPolicy
    )
  }
}
