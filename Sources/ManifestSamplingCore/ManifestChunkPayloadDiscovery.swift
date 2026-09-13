import CryptoKit
import Foundation

package struct ManifestChunkPayloadPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let structurePlan: ManifestStructurePlan
  package let chunkOriginPlan: ChunkOriginPlan
  package let chunkSafeOrigin: String
  package let chunkPrefixPathComponentCount: UInt16
  package let chunkPrefixPathSHA256: String
  package let selectionPolicy: String
  package let maximumPayloadBytes: UInt64
  package let maximumUncompressedPayloadBytes: UInt64
  package let requestPolicy: String
  package let responsePolicy: String
  package let integrityPolicy: String
  package let cachePolicy: String
  package let outputPolicy: String
  package let failurePolicy: String
  package let stopPolicy: String
}

extension ManifestChunkPayloadPlan: ManifestSamplingRedactedValue {}

package struct ManifestChunkPayloadReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let policySHA256: String
  package let branchBodySHA256: String
  package let buildBodySHA256: String
  package let manifestBodySHA256: String
  package let manifestDecompressedSHA256: String
  package let chunkObjectIDSHA256: String
  package let chunkRequestPathSHA256: String
  package let chunkByteSize: UInt64
  package let chunkSHA256: String
  package let field7CompressedMD5Verified: Bool
  package let uncompressedMD5Verified: Bool
  package let cacheDisposition: String
  package let cacheRelativePath: String
  package let observedAtUnixSeconds: Int64
  package let requestCount: UInt8
}

extension ManifestChunkPayloadReceipt: ManifestSamplingRedactedValue {}

package struct ManifestChunkPayloadVerificationInput: Sendable {
  package let data: Data
  package let candidate: ManifestChunkPayloadCandidate

  package init(data: Data, candidate: ManifestChunkPayloadCandidate) {
    self.data = data
    self.candidate = candidate
  }
}

extension ManifestChunkPayloadVerificationInput: ManifestSamplingRedactedValue {}

package struct ManifestChunkPayloadStoredEvidence: Equatable, Sendable {
  package let byteSize: UInt64
  package let sha256: String
  package let compressedMD5: String
  package let uncompressedByteSize: UInt64
  package let uncompressedMD5: String
  package let cacheDisposition: String
  package let cacheRelativePath: String

  package init(
    byteSize: UInt64,
    sha256: String,
    compressedMD5: String,
    uncompressedByteSize: UInt64,
    uncompressedMD5: String,
    cacheDisposition: String,
    cacheRelativePath: String
  ) {
    self.byteSize = byteSize
    self.sha256 = sha256
    self.compressedMD5 = compressedMD5
    self.uncompressedByteSize = uncompressedByteSize
    self.uncompressedMD5 = uncompressedMD5
    self.cacheDisposition = cacheDisposition
    self.cacheRelativePath = cacheRelativePath
  }
}

extension ManifestChunkPayloadStoredEvidence: ManifestSamplingRedactedValue {}

package protocol ManifestChunkPayloadVerifying: Sendable {
  func verifyAndStore(
    _ input: ManifestChunkPayloadVerificationInput
  ) throws -> ManifestChunkPayloadStoredEvidence
}

enum ManifestChunkPayloadDiscoveryProfile {
  static let profileID = "mgb-observed-cn-main-smallest-chunk-payload-v1"
  static let maximumPayloadBytes: UInt64 = 16 * 1_024 * 1_024
  static let maximumUncompressedPayloadBytes: UInt64 = 64 * 1_024 * 1_024
  static let chunkOriginPin = ManifestOriginPin(
    safeOrigin: "https://autopatchcn.yuanshen.com",
    pathComponentCount: 5,
    pathSHA256: "50e6250f134337b5da80c513ad8cd1c5afc92f58bdeb280dc65863827071d2eb"
  )
  static let plan = makePlan()

  static func makeChunkURL(
    prefix: String,
    objectID: String
  ) throws -> URL {
    let idBytes = objectID.utf8
    guard !idBytes.isEmpty, idBytes.count <= 256, objectID != ".", objectID != "..",
      idBytes.allSatisfy({ byte in
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
          || byte == 45 || byte == 46 || byte == 95
      }),
      var components = URLComponents(string: prefix)
    else {
      throw ManifestSamplingError.chunkCandidateRejected
    }
    let separator = components.percentEncodedPath.hasSuffix("/") ? "" : "/"
    components.percentEncodedPath += separator + objectID
    guard components.scheme == "https", components.port == nil,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      let url = components.url
    else {
      throw ManifestSamplingError.originRejected
    }
    return url
  }

  static func requestIdentity(for url: URL) -> String {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.httpBody = nil
    request.httpShouldHandleCookies = false
    request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return BranchDiscoveryProfile.requestIdentity(for: request)
  }

  static func requestPathSHA256(
    _ url: URL,
    expectedSafeOrigin: String
  ) throws -> String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "https", components.port == nil,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      "https://" + (components.host ?? "") == expectedSafeOrigin
    else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    return SHA256.hash(data: Data(components.percentEncodedPath.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func makePlan() -> ManifestChunkPayloadPlan {
    let planWithoutPolicy = ManifestChunkPayloadPlan(
      schemaVersion: 1,
      profileID: profileID,
      policySHA256: "",
      structurePlan: ManifestStructureDiscoveryProfile.plan,
      chunkOriginPlan: ChunkOriginDiscoveryProfile.plan,
      chunkSafeOrigin: chunkOriginPin.safeOrigin,
      chunkPrefixPathComponentCount: chunkOriginPin.pathComponentCount,
      chunkPrefixPathSHA256: chunkOriginPin.pathSHA256,
      selectionPolicy: "minimumCompressedBytesThenUTF8ObjectID",
      maximumPayloadBytes: maximumPayloadBytes,
      maximumUncompressedPayloadBytes: maximumUncompressedPayloadBytes,
      requestPolicy: "freshFourGETsExactPrefixPlusSingleSafeObjectIDNoRedirectOrRetry",
      responsePolicy: "exact200OctetStreamIdentityAndManifestCompressedSize",
      integrityPolicy:
        "exactCompressedSizeField7CompressedMD5ZstdSizeAndUncompressedMD5Field2",
      cachePolicy: "privateContentAddressedSHA256UnderLocalRuntimesChunkProbeCache",
      outputPolicy: "digestSizeIntegrityAndRelativeCachePathOnlyNoObjectIDOrURL",
      failurePolicy: "safeSizeField7ZstdUncompressedMD5AndCacheStageCodesNoPayloadValue",
      stopPolicy: "oneChunkOnlyNoDecompressionInstallOrAdditionalPayload"
    )
    return planWithoutPolicy.replacingPolicySHA256(
      ManifestChunkPayloadPolicyHasher.hash(planWithoutPolicy)
    )
  }
}

enum ManifestChunkPayloadPolicyHasher {
  static func hash(_ plan: ManifestChunkPayloadPlan) -> String {
    guard
      let material = try? ManifestSamplingCanonicalJSON.encode(
        plan.replacingPolicySHA256("")
      )
    else {
      preconditionFailure("Invalid fixed chunk payload policy")
    }
    var bytes = Data("MGBCHUNKPAYLOADPLAN\0".utf8)
    bytes.append(material)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension ManifestChunkPayloadPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> ManifestChunkPayloadPlan {
    ManifestChunkPayloadPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      policySHA256: value,
      structurePlan: structurePlan,
      chunkOriginPlan: chunkOriginPlan,
      chunkSafeOrigin: chunkSafeOrigin,
      chunkPrefixPathComponentCount: chunkPrefixPathComponentCount,
      chunkPrefixPathSHA256: chunkPrefixPathSHA256,
      selectionPolicy: selectionPolicy,
      maximumPayloadBytes: maximumPayloadBytes,
      maximumUncompressedPayloadBytes: maximumUncompressedPayloadBytes,
      requestPolicy: requestPolicy,
      responsePolicy: responsePolicy,
      integrityPolicy: integrityPolicy,
      cachePolicy: cachePolicy,
      outputPolicy: outputPolicy,
      failurePolicy: failurePolicy,
      stopPolicy: stopPolicy
    )
  }
}
