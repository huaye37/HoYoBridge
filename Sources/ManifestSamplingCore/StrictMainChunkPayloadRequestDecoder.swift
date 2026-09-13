import CryptoKit
import Foundation

enum StrictMainChunkPayloadRequestDecoder {
  static func decode(
    _ body: Data,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    manifestOriginPin: ManifestOriginPin,
    expectedManifestRequestPathSHA256: String,
    expectedManifestCompressedSize: UInt64,
    chunkOriginPin: ManifestOriginPin,
    semanticPolicy: MainBuildSemanticPolicy = .observedCNV1,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> ValidatedMainChunkPayloadBuildReference {
    let manifestRequest = try StrictMainManifestRequestDecoder.decodeBodyRequest(
      body,
      branchCapability: branchCapability,
      transportPolicySHA256: transportPolicySHA256,
      originPin: manifestOriginPin,
      expectedRequestPathSHA256: expectedManifestRequestPathSHA256,
      expectedCompressedSize: expectedManifestCompressedSize,
      semanticPolicy: semanticPolicy,
      cancellationCheck: cancellationCheck
    )
    let chunkOrigin = try StrictMainBuildChunkOriginDecoder.decode(
      body,
      branchCapability: branchCapability,
      transportPolicySHA256: transportPolicySHA256,
      semanticPolicy: semanticPolicy,
      cancellationCheck: cancellationCheck
    )
    let observed = try ManifestOriginDiscoveryProfile.inspect(
      rawPrefix: chunkOrigin.urlPrefix.rawValue
    )
    guard observed.safeOrigin == chunkOriginPin.safeOrigin,
      observed.pathComponentCount == chunkOriginPin.pathComponentCount,
      observed.pathSHA256 == chunkOriginPin.pathSHA256
    else {
      throw ManifestSamplingError.originRejected
    }
    try cancellationCheck()
    return ValidatedMainChunkPayloadBuildReference(
      bindingSHA256: makeBinding(
        manifestRequestBindingSHA256: manifestRequest.bindingSHA256,
        chunkOriginBindingSHA256: chunkOrigin.bindingSHA256,
        chunkOriginPin: chunkOriginPin
      ),
      manifestRequest: manifestRequest,
      chunkURLPrefix: chunkOrigin.urlPrefix,
      chunkSafeOrigin: observed.safeOrigin,
      chunkPrefixPathComponentCount: observed.pathComponentCount,
      chunkPrefixPathSHA256: observed.pathSHA256
    )
  }

  private static func makeBinding(
    manifestRequestBindingSHA256: String,
    chunkOriginBindingSHA256: String,
    chunkOriginPin: ManifestOriginPin
  ) -> String {
    var framed = Data("MGB_CN_MAIN_CHUNK_PAYLOAD_BUILD_REFERENCE\0".utf8)
    for value in [
      manifestRequestBindingSHA256,
      chunkOriginBindingSHA256,
      chunkOriginPin.safeOrigin,
      String(chunkOriginPin.pathComponentCount),
      chunkOriginPin.pathSHA256,
    ] {
      let bytes = Data(value.utf8)
      framed.append(UInt8(truncatingIfNeeded: bytes.count >> 24))
      framed.append(UInt8(truncatingIfNeeded: bytes.count >> 16))
      framed.append(UInt8(truncatingIfNeeded: bytes.count >> 8))
      framed.append(UInt8(truncatingIfNeeded: bytes.count))
      framed.append(bytes)
    }
    return SHA256.hash(data: framed).map { String(format: "%02x", $0) }.joined()
  }
}

struct ValidatedMainChunkPayloadBuildReference: Equatable, Sendable {
  let bindingSHA256: String
  let manifestRequest: ValidatedMainManifestBodyRequestReference
  let chunkURLPrefix: BranchSecretValue
  let chunkSafeOrigin: String
  let chunkPrefixPathComponentCount: UInt16
  let chunkPrefixPathSHA256: String

  fileprivate init(
    bindingSHA256: String,
    manifestRequest: ValidatedMainManifestBodyRequestReference,
    chunkURLPrefix: BranchSecretValue,
    chunkSafeOrigin: String,
    chunkPrefixPathComponentCount: UInt16,
    chunkPrefixPathSHA256: String
  ) {
    self.bindingSHA256 = bindingSHA256
    self.manifestRequest = manifestRequest
    self.chunkURLPrefix = chunkURLPrefix
    self.chunkSafeOrigin = chunkSafeOrigin
    self.chunkPrefixPathComponentCount = chunkPrefixPathComponentCount
    self.chunkPrefixPathSHA256 = chunkPrefixPathSHA256
  }
}

extension ValidatedMainChunkPayloadBuildReference: ManifestSamplingRedactedValue {}
