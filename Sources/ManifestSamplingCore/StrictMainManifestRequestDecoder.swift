import CryptoKit
import Foundation

struct ManifestOriginPin: Equatable, Sendable {
  let safeOrigin: String
  let pathComponentCount: UInt16
  let pathSHA256: String
}

extension ManifestOriginPin: ManifestSamplingRedactedValue {}

enum StrictMainManifestRequestDecoder {
  static func decodeBodyRequest(
    _ body: Data,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    originPin: ManifestOriginPin,
    expectedRequestPathSHA256: String,
    expectedCompressedSize: UInt64,
    semanticPolicy: MainBuildSemanticPolicy = .observedCNV1,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> ValidatedMainManifestBodyRequestReference {
    let owned = body.withUnsafeBytes { Data($0) }
    let request = try decode(
      owned,
      branchCapability: branchCapability,
      transportPolicySHA256: transportPolicySHA256,
      originPin: originPin,
      semanticPolicy: semanticPolicy,
      cancellationCheck: cancellationCheck
    )
    guard isLowercaseSHA256(expectedRequestPathSHA256),
      expectedCompressedSize > 0,
      expectedCompressedSize <= ManifestMetadataDiscoveryProfile.maximumDeclaredContentLength,
      try ManifestMetadataDiscoveryProfile.requestPathSHA256(
        request.manifestURL,
        expectedSafeOrigin: request.safeOrigin
      ) == expectedRequestPathSHA256
    else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    let decoded: MainManifestBodyRootDTO
    do {
      decoded = try JSONDecoder().decode(MainManifestBodyRootDTO.self, from: owned)
    } catch {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let selected = decoded.data.manifests.filter {
      $0.matchingField == semanticPolicy.expectedMatchingField
    }
    guard selected.count == 1, let game = selected.first else {
      throw ManifestSamplingError.buildSelectionRejected
    }
    let compressedSize = try parseCanonicalSize(game.manifest.compressedSize)
    guard compressedSize == expectedCompressedSize else {
      throw ManifestSamplingError.buildManifestReferenceRejected
    }
    try cancellationCheck()
    return ValidatedMainManifestBodyRequestReference(
      requestReferenceBindingSHA256: request.bindingSHA256,
      bodySHA256: request.bodySHA256,
      bindingSHA256: makeBodyRequestBinding(
        requestReference: request,
        expectedRequestPathSHA256: expectedRequestPathSHA256,
        compressedSize: compressedSize
      ),
      safeOrigin: request.safeOrigin,
      prefixPathComponentCount: request.prefixPathComponentCount,
      prefixPathSHA256: request.prefixPathSHA256,
      requestPathSHA256: expectedRequestPathSHA256,
      expectedCompressedSize: compressedSize,
      manifestID: request.manifestID,
      manifestURL: request.manifestURL
    )
  }

  static func decode(
    _ body: Data,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    originPin: ManifestOriginPin,
    semanticPolicy: MainBuildSemanticPolicy = .observedCNV1,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> ValidatedMainManifestRequestReference {
    try cancellationCheck()
    guard isLowercaseSHA256(transportPolicySHA256),
      isLowercaseSHA256(originPin.pathSHA256)
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let owned = body.withUnsafeBytes { Data($0) }
    let shape = try StrictJSONSchemaScanner.scanRootData(
      owned,
      reportLimits: .standard,
      cancellationCheck: cancellationCheck
    )
    guard shape.policyVersion == semanticPolicy.expectedShapePolicyVersion,
      shape.sha256 == semanticPolicy.expectedShapeSHA256,
      let report = shape.safeReport,
      report.policyVersion == semanticPolicy.expectedReportPolicyVersion,
      report.sha256 == semanticPolicy.expectedReportSHA256,
      report.canonicalByteSize == semanticPolicy.expectedCanonicalReportByteSize
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try cancellationCheck()

    let decoded: MainManifestRequestRootDTO
    do {
      decoded = try JSONDecoder().decode(MainManifestRequestRootDTO.self, from: owned)
    } catch {
      throw ManifestSamplingError.semanticShapeRejected
    }
    guard decoded.retcode == 0, decoded.data.tag == branchCapability.main.tag.rawValue,
      !decoded.data.manifests.isEmpty, decoded.data.manifests.count <= 256
    else {
      throw ManifestSamplingError.buildHeaderRejected
    }
    let selected = decoded.data.manifests.filter {
      $0.matchingField == semanticPolicy.expectedMatchingField
    }
    guard selected.count == 1, let game = selected.first else {
      throw ManifestSamplingError.buildSelectionRejected
    }
    let manifestID = try makeManifestID(game.manifest.id)
    let urlPrefix = try makeURLPrefix(game.manifestDownload.urlPrefix)
    let origin = try ManifestOriginDiscoveryProfile.inspect(rawPrefix: urlPrefix.rawValue)
    guard origin.safeOrigin == originPin.safeOrigin,
      origin.pathComponentCount == originPin.pathComponentCount,
      origin.pathSHA256 == originPin.pathSHA256
    else {
      throw ManifestSamplingError.originRejected
    }
    let manifestURL = try makeManifestURL(
      urlPrefix: urlPrefix.rawValue,
      manifestID: manifestID.rawValue
    )
    let bodySHA256 = SHA256.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    let bindingSHA256 = makeBinding(
      semanticPolicy: semanticPolicy,
      branchCapability: branchCapability,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      originPin: originPin,
      manifestID: manifestID,
      urlPrefix: urlPrefix
    )
    try cancellationCheck()
    return ValidatedMainManifestRequestReference(
      semanticPolicyVersion: semanticPolicy.policyVersion,
      branchCapabilityBindingSHA256: branchCapability.bindingSHA256,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      valueFreeShapeSHA256: shape.sha256,
      safeReportSHA256: report.sha256,
      bindingSHA256: bindingSHA256,
      safeOrigin: origin.safeOrigin,
      prefixPathComponentCount: origin.pathComponentCount,
      prefixPathSHA256: origin.pathSHA256,
      manifestID: manifestID,
      manifestURL: manifestURL
    )
  }

  private static func makeManifestID(_ value: String) throws -> BranchSecretValue {
    let bytes = value.utf8
    guard !bytes.isEmpty, bytes.count <= 256, value != ".", value != "..",
      bytes.allSatisfy({ byte in
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
          || byte == 45 || byte == 46 || byte == 95
      })
    else {
      throw ManifestSamplingError.buildManifestReferenceRejected
    }
    return BranchSecretValue(rawValue: value, byteSize: bytes.count)
  }

  private static func parseCanonicalSize(_ value: String) throws -> UInt64 {
    let bytes = value.utf8
    guard !bytes.isEmpty, bytes.count == 1 || bytes.first != 48,
      bytes.allSatisfy({ (48...57).contains($0) }),
      let parsed = UInt64(value), parsed > 0,
      parsed <= ManifestMetadataDiscoveryProfile.maximumDeclaredContentLength
    else {
      throw ManifestSamplingError.buildManifestReferenceRejected
    }
    return parsed
  }

  private static func makeURLPrefix(_ value: String) throws -> BranchSecretValue {
    let byteSize = value.utf8.count
    guard byteSize > 0, byteSize <= 2_048,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw ManifestSamplingError.buildDownloadReferenceRejected
    }
    return BranchSecretValue(rawValue: value, byteSize: byteSize)
  }

  private static func makeManifestURL(
    urlPrefix: String,
    manifestID: String
  ) throws -> URL {
    guard var components = URLComponents(string: urlPrefix) else {
      throw ManifestSamplingError.originRejected
    }
    let separator = components.percentEncodedPath.hasSuffix("/") ? "" : "/"
    components.percentEncodedPath += separator + manifestID
    guard components.scheme == "https", components.port == nil,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      let url = components.url
    else {
      throw ManifestSamplingError.originRejected
    }
    return url
  }

  private static func makeBinding(
    semanticPolicy: MainBuildSemanticPolicy,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    bodySHA256: String,
    originPin: ManifestOriginPin,
    manifestID: BranchSecretValue,
    urlPrefix: BranchSecretValue
  ) -> String {
    var framed = Data("MGB_CN_MAIN_MANIFEST_REQUEST_REFERENCE\0".utf8)
    framed.append(semanticPolicy.policyVersion)
    for value in [
      branchCapability.bindingSHA256,
      transportPolicySHA256,
      bodySHA256,
      semanticPolicy.expectedShapeSHA256,
      semanticPolicy.expectedReportSHA256,
      originPin.safeOrigin,
      String(originPin.pathComponentCount),
      originPin.pathSHA256,
      manifestID.rawValue,
      urlPrefix.rawValue,
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

  private static func makeBodyRequestBinding(
    requestReference: ValidatedMainManifestRequestReference,
    expectedRequestPathSHA256: String,
    compressedSize: UInt64
  ) -> String {
    var framed = Data("MGB_CN_MAIN_MANIFEST_BODY_REQUEST_REFERENCE\0".utf8)
    for value in [
      requestReference.bindingSHA256,
      expectedRequestPathSHA256,
      String(compressedSize),
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

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

struct ValidatedMainManifestRequestReference: Equatable, Sendable {
  let semanticPolicyVersion: UInt8
  let branchCapabilityBindingSHA256: String
  let transportPolicySHA256: String
  let bodySHA256: String
  let valueFreeShapeSHA256: String
  let safeReportSHA256: String
  let bindingSHA256: String
  let safeOrigin: String
  let prefixPathComponentCount: UInt16
  let prefixPathSHA256: String
  let manifestID: BranchSecretValue
  let manifestURL: URL

  fileprivate init(
    semanticPolicyVersion: UInt8,
    branchCapabilityBindingSHA256: String,
    transportPolicySHA256: String,
    bodySHA256: String,
    valueFreeShapeSHA256: String,
    safeReportSHA256: String,
    bindingSHA256: String,
    safeOrigin: String,
    prefixPathComponentCount: UInt16,
    prefixPathSHA256: String,
    manifestID: BranchSecretValue,
    manifestURL: URL
  ) {
    self.semanticPolicyVersion = semanticPolicyVersion
    self.branchCapabilityBindingSHA256 = branchCapabilityBindingSHA256
    self.transportPolicySHA256 = transportPolicySHA256
    self.bodySHA256 = bodySHA256
    self.valueFreeShapeSHA256 = valueFreeShapeSHA256
    self.safeReportSHA256 = safeReportSHA256
    self.bindingSHA256 = bindingSHA256
    self.safeOrigin = safeOrigin
    self.prefixPathComponentCount = prefixPathComponentCount
    self.prefixPathSHA256 = prefixPathSHA256
    self.manifestID = manifestID
    self.manifestURL = manifestURL
  }
}

extension ValidatedMainManifestRequestReference: ManifestSamplingRedactedValue {}

struct ValidatedMainManifestBodyRequestReference: Equatable, Sendable {
  let requestReferenceBindingSHA256: String
  let bodySHA256: String
  let bindingSHA256: String
  let safeOrigin: String
  let prefixPathComponentCount: UInt16
  let prefixPathSHA256: String
  let requestPathSHA256: String
  let expectedCompressedSize: UInt64
  let manifestID: BranchSecretValue
  let manifestURL: URL

  fileprivate init(
    requestReferenceBindingSHA256: String,
    bodySHA256: String,
    bindingSHA256: String,
    safeOrigin: String,
    prefixPathComponentCount: UInt16,
    prefixPathSHA256: String,
    requestPathSHA256: String,
    expectedCompressedSize: UInt64,
    manifestID: BranchSecretValue,
    manifestURL: URL
  ) {
    self.requestReferenceBindingSHA256 = requestReferenceBindingSHA256
    self.bodySHA256 = bodySHA256
    self.bindingSHA256 = bindingSHA256
    self.safeOrigin = safeOrigin
    self.prefixPathComponentCount = prefixPathComponentCount
    self.prefixPathSHA256 = prefixPathSHA256
    self.requestPathSHA256 = requestPathSHA256
    self.expectedCompressedSize = expectedCompressedSize
    self.manifestID = manifestID
    self.manifestURL = manifestURL
  }
}

extension ValidatedMainManifestBodyRequestReference: ManifestSamplingRedactedValue {}

private struct MainManifestRequestRootDTO: Decodable {
  let retcode: Int
  let data: MainManifestRequestDataDTO
}

private struct MainManifestRequestDataDTO: Decodable {
  let tag: String
  let manifests: [MainManifestRequestItemDTO]
}

private struct MainManifestRequestItemDTO: Decodable {
  let matchingField: String
  let manifest: MainManifestRequestReferenceDTO
  let manifestDownload: MainManifestRequestDownloadDTO

  private enum CodingKeys: String, CodingKey {
    case matchingField = "matching_field"
    case manifest
    case manifestDownload = "manifest_download"
  }
}

private struct MainManifestRequestReferenceDTO: Decodable {
  let id: String
}

private struct MainManifestRequestDownloadDTO: Decodable {
  let urlPrefix: String

  private enum CodingKeys: String, CodingKey {
    case urlPrefix = "url_prefix"
  }
}

private struct MainManifestBodyRootDTO: Decodable {
  let data: MainManifestBodyDataDTO
}

private struct MainManifestBodyDataDTO: Decodable {
  let manifests: [MainManifestBodyItemDTO]
}

private struct MainManifestBodyItemDTO: Decodable {
  let matchingField: String
  let manifest: MainManifestBodyReferenceDTO

  private enum CodingKeys: String, CodingKey {
    case matchingField = "matching_field"
    case manifest
  }
}

private struct MainManifestBodyReferenceDTO: Decodable {
  let compressedSize: String

  private enum CodingKeys: String, CodingKey {
    case compressedSize = "compressed_size"
  }
}
