import CryptoKit
import Foundation

struct MainBuildSemanticPolicy: Equatable, Sendable {
  static let observedCNV1 = MainBuildSemanticPolicy(
    policyVersion: 1,
    expectedShapePolicyVersion: 1,
    expectedShapeSHA256:
      "21e89e02cc735be6296f7ab41763875a8b7ff86db2e3fcefec32453e131db851",
    expectedReportPolicyVersion: 1,
    expectedReportSHA256:
      "ab0d7df71bfd1be62d73d9414184afb58a6495c78a6470a2300283ebb9ee778f",
    expectedCanonicalReportByteSize: 4_521,
    expectedMatchingField: "game"
  )

  let policyVersion: UInt8
  let expectedShapePolicyVersion: UInt8
  let expectedShapeSHA256: String
  let expectedReportPolicyVersion: UInt8
  let expectedReportSHA256: String
  let expectedCanonicalReportByteSize: UInt64
  let expectedMatchingField: String
}

enum StrictMainBuildSemanticDecoder {
  static func decode(
    _ body: Data,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    semanticPolicy: MainBuildSemanticPolicy = .observedCNV1,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> ValidatedMainBuildCapability {
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

    let decoded: MainBuildRootDTO
    do {
      decoded = try JSONDecoder().decode(MainBuildRootDTO.self, from: owned)
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

    let tag = try makeSecret(
      decoded.data.tag,
      maximumBytes: 128,
      rejection: .buildSelectionRejected
    )
    let buildID = try makeSecret(
      decoded.data.buildID,
      maximumBytes: 256,
      rejection: .buildSelectionRejected
    )
    let categoryID = try makeSecret(
      game.categoryID,
      maximumBytes: 128,
      rejection: .buildSelectionRejected
    )
    let categoryName = try makeSecret(
      game.categoryName,
      maximumBytes: 128,
      rejection: .buildSelectionRejected
    )
    let matchingField = try makeSecret(
      game.matchingField,
      maximumBytes: 128,
      rejection: .buildSelectionRejected
    )
    let manifestID = try makeSecret(
      game.manifest.id,
      maximumBytes: 256,
      rejection: .buildManifestReferenceRejected
    )
    let checksum = try makeSecret(
      game.manifest.checksum,
      maximumBytes: 256,
      rejection: .buildManifestReferenceRejected
    )
    let compressedSize = try makeSecret(
      game.manifest.compressedSize,
      maximumBytes: 64,
      rejection: .buildManifestReferenceRejected
    )
    let uncompressedSize = try makeSecret(
      game.manifest.uncompressedSize,
      maximumBytes: 64,
      rejection: .buildManifestReferenceRejected
    )
    let downloadPassword = try makeSecret(
      game.manifestDownload.password,
      maximumBytes: 256,
      rejection: .buildDownloadReferenceRejected
    )
    let urlPrefix = try makeSecret(
      game.manifestDownload.urlPrefix,
      maximumBytes: 2_048,
      rejection: .buildDownloadReferenceRejected
    )
    let values = [
      tag, buildID, categoryID, categoryName, matchingField, manifestID, checksum,
      compressedSize, uncompressedSize, downloadPassword, urlPrefix,
    ]
    var totalBytes = 0
    for value in values {
      let (next, overflow) = totalBytes.addingReportingOverflow(value.byteSize)
      guard !overflow, next <= 4_096 else {
        throw ManifestSamplingError.buildValueBudgetRejected
      }
      totalBytes = next
      try cancellationCheck()
    }

    let bodySHA256 = SHA256.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    let manifest = ValidatedMainManifestReference(
      id: manifestID,
      checksum: checksum,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize
    )
    let download = ValidatedManifestDownloadReference(
      password: downloadPassword,
      urlPrefix: urlPrefix
    )
    let bindingSHA256 = makeBinding(
      semanticPolicy: semanticPolicy,
      branchCapability: branchCapability,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      tag: tag,
      buildID: buildID,
      categoryID: categoryID,
      categoryName: categoryName,
      matchingField: matchingField,
      manifest: manifest,
      download: download
    )
    try cancellationCheck()
    return ValidatedMainBuildCapability(
      semanticPolicyVersion: semanticPolicy.policyVersion,
      branchCapabilityBindingSHA256: branchCapability.bindingSHA256,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      valueFreeShapeSHA256: shape.sha256,
      safeReportSHA256: report.sha256,
      bindingSHA256: bindingSHA256,
      tag: tag,
      buildID: buildID,
      categoryID: categoryID,
      categoryName: categoryName,
      matchingField: matchingField,
      manifest: manifest,
      manifestDownload: download
    )
  }

  private static func makeSecret(
    _ value: String,
    maximumBytes: Int,
    rejection: ManifestSamplingError
  ) throws -> BranchSecretValue {
    let byteSize = value.utf8.count
    guard byteSize > 0, byteSize <= maximumBytes,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw rejection
    }
    return BranchSecretValue(rawValue: value, byteSize: byteSize)
  }

  private static func makeBinding(
    semanticPolicy: MainBuildSemanticPolicy,
    branchCapability: ValidatedCNBranchCapability,
    transportPolicySHA256: String,
    bodySHA256: String,
    tag: BranchSecretValue,
    buildID: BranchSecretValue,
    categoryID: BranchSecretValue,
    categoryName: BranchSecretValue,
    matchingField: BranchSecretValue,
    manifest: ValidatedMainManifestReference,
    download: ValidatedManifestDownloadReference
  ) -> String {
    var framed = Data("MGB_CN_MAIN_BUILD_CAPABILITY\0".utf8)
    framed.append(semanticPolicy.policyVersion)
    for value in [
      branchCapability.bindingSHA256,
      transportPolicySHA256,
      bodySHA256,
      semanticPolicy.expectedShapeSHA256,
      semanticPolicy.expectedReportSHA256,
      tag.rawValue,
      buildID.rawValue,
      categoryID.rawValue,
      categoryName.rawValue,
      matchingField.rawValue,
      manifest.id.rawValue,
      manifest.checksum.rawValue,
      manifest.compressedSize.rawValue,
      manifest.uncompressedSize.rawValue,
      download.password.rawValue,
      download.urlPrefix.rawValue,
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

struct ValidatedMainBuildCapability: Equatable, Sendable {
  let semanticPolicyVersion: UInt8
  let branchCapabilityBindingSHA256: String
  let transportPolicySHA256: String
  let bodySHA256: String
  let valueFreeShapeSHA256: String
  let safeReportSHA256: String
  let bindingSHA256: String
  let tag: BranchSecretValue
  let buildID: BranchSecretValue
  let categoryID: BranchSecretValue
  let categoryName: BranchSecretValue
  let matchingField: BranchSecretValue
  let manifest: ValidatedMainManifestReference
  let manifestDownload: ValidatedManifestDownloadReference

  fileprivate init(
    semanticPolicyVersion: UInt8,
    branchCapabilityBindingSHA256: String,
    transportPolicySHA256: String,
    bodySHA256: String,
    valueFreeShapeSHA256: String,
    safeReportSHA256: String,
    bindingSHA256: String,
    tag: BranchSecretValue,
    buildID: BranchSecretValue,
    categoryID: BranchSecretValue,
    categoryName: BranchSecretValue,
    matchingField: BranchSecretValue,
    manifest: ValidatedMainManifestReference,
    manifestDownload: ValidatedManifestDownloadReference
  ) {
    self.semanticPolicyVersion = semanticPolicyVersion
    self.branchCapabilityBindingSHA256 = branchCapabilityBindingSHA256
    self.transportPolicySHA256 = transportPolicySHA256
    self.bodySHA256 = bodySHA256
    self.valueFreeShapeSHA256 = valueFreeShapeSHA256
    self.safeReportSHA256 = safeReportSHA256
    self.bindingSHA256 = bindingSHA256
    self.tag = tag
    self.buildID = buildID
    self.categoryID = categoryID
    self.categoryName = categoryName
    self.matchingField = matchingField
    self.manifest = manifest
    self.manifestDownload = manifestDownload
  }
}

extension ValidatedMainBuildCapability: ManifestSamplingRedactedValue {}

struct ValidatedMainManifestReference: Equatable, Sendable {
  let id: BranchSecretValue
  let checksum: BranchSecretValue
  let compressedSize: BranchSecretValue
  let uncompressedSize: BranchSecretValue
}

extension ValidatedMainManifestReference: ManifestSamplingRedactedValue {}

struct ValidatedManifestDownloadReference: Equatable, Sendable {
  let password: BranchSecretValue
  let urlPrefix: BranchSecretValue
}

extension ValidatedManifestDownloadReference: ManifestSamplingRedactedValue {}

private struct MainBuildRootDTO: Decodable {
  let retcode: Int
  let message: String
  let data: MainBuildDataDTO
}

private struct MainBuildDataDTO: Decodable {
  let tag: String
  let buildID: String
  let manifests: [MainBuildManifestDTO]

  private enum CodingKeys: String, CodingKey {
    case tag
    case buildID = "build_id"
    case manifests
  }
}

private struct MainBuildManifestDTO: Decodable {
  let categoryID: String
  let categoryName: String
  let matchingField: String
  let manifest: MainManifestReferenceDTO
  let manifestDownload: ManifestDownloadReferenceDTO

  private enum CodingKeys: String, CodingKey {
    case categoryID = "category_id"
    case categoryName = "category_name"
    case matchingField = "matching_field"
    case manifest
    case manifestDownload = "manifest_download"
  }
}

private struct MainManifestReferenceDTO: Decodable {
  let id: String
  let checksum: String
  let compressedSize: String
  let uncompressedSize: String

  private enum CodingKeys: String, CodingKey {
    case id
    case checksum
    case compressedSize = "compressed_size"
    case uncompressedSize = "uncompressed_size"
  }
}

private struct ManifestDownloadReferenceDTO: Decodable {
  let password: String
  let urlPrefix: String

  private enum CodingKeys: String, CodingKey {
    case password
    case urlPrefix = "url_prefix"
  }
}
