import CryptoKit
import Foundation

enum StrictMainBuildChunkOriginDecoder {
  static func decode(
    _ body: Data,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    semanticPolicy: MainBuildSemanticPolicy = .observedCNV1,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> ValidatedMainBuildChunkOriginReference {
    try cancellationCheck()
    guard isLowercaseSHA256(transportPolicySHA256) else {
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

    let decoded: MainBuildChunkOriginRootDTO
    do {
      decoded = try JSONDecoder().decode(MainBuildChunkOriginRootDTO.self, from: owned)
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
    let urlPrefix = try makeURLPrefix(game.chunkDownload.urlPrefix)
    let bodySHA256 = SHA256.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    let bindingSHA256 = makeBinding(
      semanticPolicy: semanticPolicy,
      branchCapability: branchCapability,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      urlPrefix: urlPrefix
    )
    try cancellationCheck()
    return ValidatedMainBuildChunkOriginReference(
      semanticPolicyVersion: semanticPolicy.policyVersion,
      branchCapabilityBindingSHA256: branchCapability.bindingSHA256,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      valueFreeShapeSHA256: shape.sha256,
      safeReportSHA256: report.sha256,
      bindingSHA256: bindingSHA256,
      urlPrefix: urlPrefix
    )
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

  private static func makeBinding(
    semanticPolicy: MainBuildSemanticPolicy,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    bodySHA256: String,
    urlPrefix: BranchSecretValue
  ) -> String {
    var framed = Data("MGB_CN_MAIN_BUILD_CHUNK_ORIGIN_REFERENCE\0".utf8)
    framed.append(semanticPolicy.policyVersion)
    for value in [
      branchCapability.bindingSHA256,
      transportPolicySHA256,
      bodySHA256,
      semanticPolicy.expectedShapeSHA256,
      semanticPolicy.expectedReportSHA256,
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

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

struct ValidatedMainBuildChunkOriginReference: Equatable, Sendable {
  let semanticPolicyVersion: UInt8
  let branchCapabilityBindingSHA256: String
  let transportPolicySHA256: String
  let bodySHA256: String
  let valueFreeShapeSHA256: String
  let safeReportSHA256: String
  let bindingSHA256: String
  let urlPrefix: BranchSecretValue

  fileprivate init(
    semanticPolicyVersion: UInt8,
    branchCapabilityBindingSHA256: String,
    transportPolicySHA256: String,
    bodySHA256: String,
    valueFreeShapeSHA256: String,
    safeReportSHA256: String,
    bindingSHA256: String,
    urlPrefix: BranchSecretValue
  ) {
    self.semanticPolicyVersion = semanticPolicyVersion
    self.branchCapabilityBindingSHA256 = branchCapabilityBindingSHA256
    self.transportPolicySHA256 = transportPolicySHA256
    self.bodySHA256 = bodySHA256
    self.valueFreeShapeSHA256 = valueFreeShapeSHA256
    self.safeReportSHA256 = safeReportSHA256
    self.bindingSHA256 = bindingSHA256
    self.urlPrefix = urlPrefix
  }
}

extension ValidatedMainBuildChunkOriginReference: ManifestSamplingRedactedValue {}

private struct MainBuildChunkOriginRootDTO: Decodable {
  let retcode: Int
  let data: MainBuildChunkOriginDataDTO
}

private struct MainBuildChunkOriginDataDTO: Decodable {
  let tag: String
  let manifests: [MainBuildChunkOriginManifestDTO]
}

private struct MainBuildChunkOriginManifestDTO: Decodable {
  let matchingField: String
  let chunkDownload: MainBuildChunkOriginDownloadDTO

  private enum CodingKeys: String, CodingKey {
    case matchingField = "matching_field"
    case chunkDownload = "chunk_download"
  }
}

private struct MainBuildChunkOriginDownloadDTO: Decodable {
  let urlPrefix: String

  private enum CodingKeys: String, CodingKey {
    case urlPrefix = "url_prefix"
  }
}
