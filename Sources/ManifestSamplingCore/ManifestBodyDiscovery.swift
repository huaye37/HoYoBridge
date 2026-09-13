import CryptoKit
import Foundation

package struct ManifestBodyPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let metadataPlan: ManifestMetadataPlan
  package let manifestSafeOrigin: String
  package let manifestPrefixPathSHA256: String
  package let manifestRequestPathSHA256: String
  package let expectedCompressedSize: UInt64
  package let requestTemplateSHA256: String
  package let method: String
  package let requestAccept: String
  package let requestContentEncoding: String
  package let statusPolicy: String
  package let responseContentTypePolicy: String
  package let responseContentEncodingPolicy: String
  package let responseContentLengthPolicy: String
  package let responseBodyPolicy: String
  package let redirectPolicy: String
  package let authenticationPolicy: String
  package let cookiePolicy: String
  package let cachePolicy: String
  package let persistencePolicy: String
  package let outputPolicy: String
  package let stopPolicy: String
}

extension ManifestBodyPlan: ManifestSamplingRedactedValue {}

package struct ManifestBodyReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchBodySHA256: String
  package let buildBodySHA256: String
  package let buildShapeSHA256: String
  package let buildReportSHA256: String
  package let manifestSafeOrigin: String
  package let manifestPrefixPathSHA256: String
  package let manifestRequestPathSHA256: String
  package let statusCode: UInt16
  package let contentTypeKind: String
  package let contentEncodingKind: String
  package let declaredContentLength: UInt64
  package let bodySHA256: String
  package let byteSize: UInt64
  package let frameKind: String
  package let observedAtUnixSeconds: Int64
  package let requestCount: UInt8
}

extension ManifestBodyReceipt: ManifestSamplingRedactedValue {}

struct ManifestBinaryBodyEvidence: Equatable, Sendable {
  let frameKind: String
  let contentEncodingKind: String
}

extension ManifestBinaryBodyEvidence: ManifestSamplingRedactedValue {}

enum ManifestBodyDiscoveryProfile {
  static let profileID = "yaagl-ca78abc-cn-main-manifest-body-v1"
  static let expectedCompressedSize: UInt64 = 8_521_303
  static let expectedRequestPathSHA256 =
    "ce154736f9d4cd8d3355c17101f99526ccd3a67772cf04defdd362afbf6cfea8"
  static let plan = makePlan()

  static func classifyFrame(_ data: Data) -> String {
    guard data.count >= 4 else { return "tooShort" }
    return data.prefix(4).elementsEqual([0x28, 0xB5, 0x2F, 0xFD])
      ? "zstdStandardFrame"
      : "otherSHA256:" + BranchDiscoveryProfile.sha256(Data(data.prefix(4)))
  }

  private static func makePlan() -> ManifestBodyPlan {
    let metadataPlan = ManifestMetadataDiscoveryProfile.plan
    let planWithoutPolicy = ManifestBodyPlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      metadataPlan: metadataPlan,
      manifestSafeOrigin: metadataPlan.manifestSafeOrigin,
      manifestPrefixPathSHA256: metadataPlan.manifestPrefixPathSHA256,
      manifestRequestPathSHA256: expectedRequestPathSHA256,
      expectedCompressedSize: expectedCompressedSize,
      requestTemplateSHA256: metadataPlan.manifestRequestTemplateSHA256,
      method: "GET",
      requestAccept: "application/octet-stream",
      requestContentEncoding: "identity",
      statusPolicy: "exact200",
      responseContentTypePolicy: "exactApplicationOctetStream",
      responseContentEncodingPolicy: "absentOrIdentity",
      responseContentLengthPolicy: "exactFreshBuildDeclaredSize",
      responseBodyPolicy: "streamedMemoryOnlyExactLengthAndSHA256",
      redirectPolicy: "reject",
      authenticationPolicy: "serverTrustExactManifestHost",
      cookiePolicy: "noSendNoStoreIgnoreResponseSetCookie",
      cachePolicy: "none",
      persistencePolicy: "noExplicitFileWriteOwnedMemoryReleasedAfterReceipt",
      outputPolicy: "bodySHA256SizeAndFrameKindOnly",
      stopPolicy: "bodyReceiptOnlyNoDecompressNoPayload"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      ManifestBodyPolicyHasher.hash(planWithoutPolicy)
    )
  }
}

enum ManifestBodyPolicyHasher {
  static func hash(_ plan: ManifestBodyPlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed manifest body policy")
    }
    var bytes = Data("MGBMANIFESTBODYPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension ManifestBodyPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> ManifestBodyPlan {
    ManifestBodyPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      metadataPlan: metadataPlan,
      manifestSafeOrigin: manifestSafeOrigin,
      manifestPrefixPathSHA256: manifestPrefixPathSHA256,
      manifestRequestPathSHA256: manifestRequestPathSHA256,
      expectedCompressedSize: expectedCompressedSize,
      requestTemplateSHA256: requestTemplateSHA256,
      method: method,
      requestAccept: requestAccept,
      requestContentEncoding: requestContentEncoding,
      statusPolicy: statusPolicy,
      responseContentTypePolicy: responseContentTypePolicy,
      responseContentEncodingPolicy: responseContentEncodingPolicy,
      responseContentLengthPolicy: responseContentLengthPolicy,
      responseBodyPolicy: responseBodyPolicy,
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
