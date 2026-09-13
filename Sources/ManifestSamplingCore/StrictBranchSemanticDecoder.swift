import CryptoKit
import Foundation

struct BranchSemanticPolicy: Equatable, Sendable {
  static let observedCNV1 = BranchSemanticPolicy(
    policyVersion: 1,
    expectedRequestIdentitySHA256:
      "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
    expectedShapePolicyVersion: 1,
    expectedShapeSHA256:
      "a45e5b73aa00286cd3b054b11902a21db83b003f6f360ddb5446c82a82c22633",
    expectedGameBranchEntryCount: 1,
    expectedReportPolicyVersion: 1,
    expectedReportSHA256:
      "bb82a7b942898063b3d5abc09d9e7e62a372dfba5c7e30181658aab683de6b25",
    expectedCanonicalReportByteSize: 2_178,
    expectedGameID: "1Z8W5NHUQb"
  )

  let policyVersion: UInt8
  let expectedRequestIdentitySHA256: String
  let expectedShapePolicyVersion: UInt8
  let expectedShapeSHA256: String
  let expectedGameBranchEntryCount: UInt64
  let expectedReportPolicyVersion: UInt8
  let expectedReportSHA256: String
  let expectedCanonicalReportByteSize: UInt64
  let expectedGameID: String
}

enum StrictCNBranchSemanticDecoder {
  static func decode(
    _ body: Data,
    requestIdentitySHA256: String,
    transportPolicySHA256: String,
    semanticPolicy: BranchSemanticPolicy = .observedCNV1,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> ValidatedCNBranchCapability {
    try cancellationCheck()
    guard requestIdentitySHA256 == semanticPolicy.expectedRequestIdentitySHA256,
      isLowercaseSHA256(requestIdentitySHA256),
      isLowercaseSHA256(transportPolicySHA256)
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let owned = body.withUnsafeBytes { Data($0) }
    try cancellationCheck()
    let shape = try StrictJSONSchemaScanner.scan(
      owned,
      reportLimits: .standard,
      cancellationCheck: cancellationCheck
    )
    guard shape.policyVersion == semanticPolicy.expectedShapePolicyVersion,
      shape.sha256 == semanticPolicy.expectedShapeSHA256,
      shape.gameBranchEntryCount == semanticPolicy.expectedGameBranchEntryCount,
      let report = shape.safeReport,
      report.policyVersion == semanticPolicy.expectedReportPolicyVersion,
      report.sha256 == semanticPolicy.expectedReportSHA256,
      report.canonicalByteSize == semanticPolicy.expectedCanonicalReportByteSize
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try cancellationCheck()

    let decoded: BranchRootDTO
    do {
      decoded = try JSONDecoder().decode(BranchRootDTO.self, from: owned)
    } catch {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try cancellationCheck()
    guard decoded.retcode == 0, decoded.data.gameBranches.count == 1,
      let candidate = decoded.data.gameBranches.first,
      candidate.preDownload == nil,
      candidate.game.id == semanticPolicy.expectedGameID
    else {
      throw ManifestSamplingError.semanticValueRejected
    }

    let gameID = try makeSecret(candidate.game.id, maximumBytes: 128)
    let biz = try makeSecret(candidate.game.biz, maximumBytes: 128)
    let tag = try makeSecret(candidate.main.tag, maximumBytes: 128)
    let branch = try makeSecret(candidate.main.branch, maximumBytes: 256)
    let packageID = try makeSecret(candidate.main.packageID, maximumBytes: 256)
    let password = try makeSecret(candidate.main.password, maximumBytes: 256)
    let values = [gameID, biz, tag, branch, packageID, password]
    var totalBytes = 0
    for value in values {
      let (next, overflow) = totalBytes.addingReportingOverflow(value.byteSize)
      guard !overflow, next <= 2_048 else {
        throw ManifestSamplingError.semanticValueRejected
      }
      totalBytes = next
      try cancellationCheck()
    }

    let bodySHA256 = SHA256.hash(data: owned)
      .map { String(format: "%02x", $0) }
      .joined()
    let slot = ValidatedCNBranchSlot(
      tag: tag,
      branch: branch,
      packageID: packageID,
      password: password
    )
    let bindingSHA256 = makeBinding(
      semanticPolicy: semanticPolicy,
      requestIdentitySHA256: requestIdentitySHA256,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      gameID: gameID,
      biz: biz,
      slot: slot
    )
    try cancellationCheck()
    return ValidatedCNBranchCapability(
      semanticPolicyVersion: semanticPolicy.policyVersion,
      requestIdentitySHA256: requestIdentitySHA256,
      transportPolicySHA256: transportPolicySHA256,
      bodySHA256: bodySHA256,
      valueFreeShapeSHA256: shape.sha256,
      safeReportSHA256: report.sha256,
      bindingSHA256: bindingSHA256,
      gameID: gameID,
      biz: biz,
      main: slot
    )
  }

  private static func makeSecret(
    _ value: String,
    maximumBytes: Int
  ) throws -> BranchSecretValue {
    let byteSize = value.utf8.count
    guard byteSize > 0, byteSize <= maximumBytes,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw ManifestSamplingError.semanticValueRejected
    }
    return BranchSecretValue(rawValue: value, byteSize: byteSize)
  }

  private static func makeBinding(
    semanticPolicy: BranchSemanticPolicy,
    requestIdentitySHA256: String,
    transportPolicySHA256: String,
    bodySHA256: String,
    gameID: BranchSecretValue,
    biz: BranchSecretValue,
    slot: ValidatedCNBranchSlot
  ) -> String {
    var framed = Data("MGB_CN_BRANCH_CAPABILITY\0".utf8)
    framed.append(semanticPolicy.policyVersion)
    for value in [
      requestIdentitySHA256,
      transportPolicySHA256,
      bodySHA256,
      semanticPolicy.expectedShapeSHA256,
      semanticPolicy.expectedReportSHA256,
      gameID.rawValue,
      biz.rawValue,
      slot.tag.rawValue,
      slot.branch.rawValue,
      slot.packageID.rawValue,
      slot.password.rawValue,
    ] {
      let bytes = Data(value.utf8)
      framed.appendUInt32BE(UInt32(bytes.count))
      framed.append(bytes)
    }
    return SHA256.hash(data: framed).map { String(format: "%02x", $0) }.joined()
  }

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

struct ValidatedCNBranchCapability: Equatable, Sendable {
  let semanticPolicyVersion: UInt8
  let requestIdentitySHA256: String
  let transportPolicySHA256: String
  let bodySHA256: String
  let valueFreeShapeSHA256: String
  let safeReportSHA256: String
  let bindingSHA256: String
  let gameID: BranchSecretValue
  let biz: BranchSecretValue
  let main: ValidatedCNBranchSlot

  fileprivate init(
    semanticPolicyVersion: UInt8,
    requestIdentitySHA256: String,
    transportPolicySHA256: String,
    bodySHA256: String,
    valueFreeShapeSHA256: String,
    safeReportSHA256: String,
    bindingSHA256: String,
    gameID: BranchSecretValue,
    biz: BranchSecretValue,
    main: ValidatedCNBranchSlot
  ) {
    self.semanticPolicyVersion = semanticPolicyVersion
    self.requestIdentitySHA256 = requestIdentitySHA256
    self.transportPolicySHA256 = transportPolicySHA256
    self.bodySHA256 = bodySHA256
    self.valueFreeShapeSHA256 = valueFreeShapeSHA256
    self.safeReportSHA256 = safeReportSHA256
    self.bindingSHA256 = bindingSHA256
    self.gameID = gameID
    self.biz = biz
    self.main = main
  }
}

extension ValidatedCNBranchCapability: ManifestSamplingRedactedValue {}

struct ValidatedCNBranchSlot: Equatable, Sendable {
  let tag: BranchSecretValue
  let branch: BranchSecretValue
  let packageID: BranchSecretValue
  let password: BranchSecretValue
}

extension ValidatedCNBranchSlot: ManifestSamplingRedactedValue {}

struct BranchSecretValue: Equatable, Sendable {
  let rawValue: String
  let byteSize: Int
}

extension BranchSecretValue: ManifestSamplingRedactedValue {}

private struct BranchRootDTO: Decodable {
  let retcode: Int
  let message: String
  let data: BranchDataDTO
}

private struct BranchDataDTO: Decodable {
  let gameBranches: [BranchCandidateDTO]

  private enum CodingKeys: String, CodingKey {
    case gameBranches = "game_branches"
  }
}

private struct BranchCandidateDTO: Decodable {
  let game: BranchGameDTO
  let main: BranchSlotDTO
  let preDownload: BranchSlotDTO?

  private enum CodingKeys: String, CodingKey {
    case game
    case main
    case preDownload = "pre_download"
  }
}

private struct BranchGameDTO: Decodable {
  let id: String
  let biz: String
}

private struct BranchSlotDTO: Decodable {
  let tag: String
  let branch: String
  let packageID: String
  let password: String

  private enum CodingKeys: String, CodingKey {
    case tag
    case branch
    case packageID = "package_id"
    case password
  }
}

extension Data {
  fileprivate mutating func appendUInt32BE(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value >> 24))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }
}
