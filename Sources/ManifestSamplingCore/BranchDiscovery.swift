import CryptoKit
import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

package protocol ManifestSamplingRedactedValue: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{}

extension ManifestSamplingRedactedValue {
  package var description: String { "<redacted>" }
  package var debugDescription: String { "<redacted>" }
  package var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

package enum ManifestSamplingError: Error, Equatable, Sendable {
  case invalidCommand
  case executionGateClosed
  case requestIdentityMismatch
  case redirectRejected
  case authenticationRejected
  case transportFailure
  case responseIdentityMismatch
  case statusRejected
  case contentTypeRejected
  case contentEncodingRejected
  case contentLengthRejected
  case contentTypeAndEncodingRejected
  case contentTypeAndLengthRejected
  case contentEncodingAndLengthRejected
  case contentTypeEncodingAndLengthRejected
  case oversized
  case malformedJSON
  case duplicateJSONKey
  case resourceLimit
  case shapeReportLimit
  case semanticShapeRejected
  case semanticValueRejected
  case buildHeaderRejected
  case buildSelectionRejected
  case buildManifestReferenceRejected
  case buildDownloadReferenceRejected
  case buildValueBudgetRejected
  case originRejected
  case manifestZstdFrameRejected
  case manifestZstdDictionaryRejected
  case manifestZstdWindowRejected
  case manifestZstdOutputRejected
  case manifestZstdRatioRejected
  case manifestZstdTruncated
  case manifestZstdTrailingData
  case manifestZstdDecoderRejected
  case manifestWireSchemaDrift(messageKind: String, fieldNumber: UInt64, wireType: UInt8)
  case manifestWireInvalid
  case manifestWireResourceLimit
  case manifestStructuralRejected
  case structureBranchRejected
  case structureBuildRejected
  case structureManifestResponseRejected
  case structureManifestIdentityRejected
  case structureManifestStatusRejected
  case structureManifestContentTypeRejected
  case structureManifestEncodingRejected
  case structureManifestLengthRejected
  case structureManifestOversized
  case chunkCandidateRejected
  case chunkResponseRejected
  case chunkIntegrityRejected
  case chunkField7MD5Rejected
  case chunkDecompressionRejected
  case chunkUncompressedMD5Rejected
  case chunkCacheRejected

  package var safeCode: String {
    switch self {
    case .invalidCommand: "invalid-command"
    case .executionGateClosed: "execution-gate-closed"
    case .requestIdentityMismatch: "request-identity-mismatch"
    case .redirectRejected: "redirect-rejected"
    case .authenticationRejected: "authentication-rejected"
    case .transportFailure: "transport-failure"
    case .responseIdentityMismatch: "response-identity-mismatch"
    case .statusRejected: "status-rejected"
    case .contentTypeRejected: "content-type-rejected"
    case .contentEncodingRejected: "content-encoding-rejected"
    case .contentLengthRejected: "content-length-rejected"
    case .contentTypeAndEncodingRejected: "content-type-and-encoding-rejected"
    case .contentTypeAndLengthRejected: "content-type-and-length-rejected"
    case .contentEncodingAndLengthRejected: "content-encoding-and-length-rejected"
    case .contentTypeEncodingAndLengthRejected: "content-type-encoding-and-length-rejected"
    case .oversized: "oversized"
    case .malformedJSON: "malformed-json"
    case .duplicateJSONKey: "duplicate-json-key"
    case .resourceLimit: "resource-limit"
    case .shapeReportLimit: "shape-report-limit"
    case .semanticShapeRejected: "semantic-shape-rejected"
    case .semanticValueRejected: "semantic-value-rejected"
    case .buildHeaderRejected: "build-header-rejected"
    case .buildSelectionRejected: "build-selection-rejected"
    case .buildManifestReferenceRejected: "build-manifest-reference-rejected"
    case .buildDownloadReferenceRejected: "build-download-reference-rejected"
    case .buildValueBudgetRejected: "build-value-budget-rejected"
    case .originRejected: "origin-rejected"
    case .manifestZstdFrameRejected: "manifest-zstd-frame-rejected"
    case .manifestZstdDictionaryRejected: "manifest-zstd-dictionary-rejected"
    case .manifestZstdWindowRejected: "manifest-zstd-window-rejected"
    case .manifestZstdOutputRejected: "manifest-zstd-output-rejected"
    case .manifestZstdRatioRejected: "manifest-zstd-ratio-rejected"
    case .manifestZstdTruncated: "manifest-zstd-truncated"
    case .manifestZstdTrailingData: "manifest-zstd-trailing-data"
    case .manifestZstdDecoderRejected: "manifest-zstd-decoder-rejected"
    case .manifestWireSchemaDrift(let messageKind, let fieldNumber, let wireType):
      "manifest-wire-schema-drift-\(messageKind)-f\(fieldNumber)-w\(wireType)"
    case .manifestWireInvalid: "manifest-wire-invalid"
    case .manifestWireResourceLimit: "manifest-wire-resource-limit"
    case .manifestStructuralRejected: "manifest-structural-rejected"
    case .structureBranchRejected: "structure-branch-rejected"
    case .structureBuildRejected: "structure-build-rejected"
    case .structureManifestResponseRejected: "structure-manifest-response-rejected"
    case .structureManifestIdentityRejected: "structure-manifest-identity-rejected"
    case .structureManifestStatusRejected: "structure-manifest-status-rejected"
    case .structureManifestContentTypeRejected: "structure-manifest-content-type-rejected"
    case .structureManifestEncodingRejected: "structure-manifest-encoding-rejected"
    case .structureManifestLengthRejected: "structure-manifest-length-rejected"
    case .structureManifestOversized: "structure-manifest-oversized"
    case .chunkCandidateRejected: "chunk-candidate-rejected"
    case .chunkResponseRejected: "chunk-response-rejected"
    case .chunkIntegrityRejected: "chunk-integrity-rejected"
    case .chunkField7MD5Rejected: "chunk-field7-md5-rejected"
    case .chunkDecompressionRejected: "chunk-decompression-rejected"
    case .chunkUncompressedMD5Rejected: "chunk-uncompressed-md5-rejected"
    case .chunkCacheRejected: "chunk-cache-rejected"
    }
  }
}

extension ManifestSamplingError: ManifestSamplingRedactedValue {}

package struct BranchDiscoveryPlan: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let requestIdentitySHA256: String
  package let policySHA256: String
  package let method: String
  package let safeOrigin: String
  package let path: String
  package let maximumResponseBytes: UInt64
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
  package let requestTimeoutSeconds: UInt16
  package let resourceTimeoutSeconds: UInt16
}

extension BranchDiscoveryPlan: ManifestSamplingRedactedValue {}

package struct BranchDiscoveryReceipt: Encodable, Equatable, Sendable {
  package let schemaVersion: UInt8
  package let profileID: String
  package let requestIdentitySHA256: String
  package let policySHA256: String
  package let statusCode: UInt16
  package let observedAtUnixSeconds: Int64
  package let bodySHA256: String
  package let byteSize: UInt64
  package let valueFreeShapePolicyVersion: UInt8
  package let valueFreeShapeSHA256: String
  package let gameBranchEntryCount: UInt64
}

extension BranchDiscoveryReceipt: ManifestSamplingRedactedValue {}

package enum ManifestSamplingCanonicalJSON {
  package static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }
}

package struct BranchDiscoveryClient: @unchecked Sendable {
  package static let requiredNetworkGate = "ALLOW_BRANCH_CN_V1"
  package static let requiredShapeReportNetworkGate = "ALLOW_BRANCH_CN_SHAPE_V1"
  package static let requiredMainBuildNetworkGate = "ALLOW_BRANCH_BUILD_MAIN_CN_V1"
  package static let requiredManifestOriginNetworkGate = "ALLOW_BRANCH_BUILD_ORIGIN_CN_V1"
  package static let requiredChunkOriginNetworkGate = "ALLOW_BRANCH_BUILD_CHUNK_ORIGIN_CN_V1"
  package static let requiredManifestMetadataNetworkGate =
    "ALLOW_BRANCH_BUILD_MANIFEST_METADATA_CN_V1"
  package static let requiredManifestBodyNetworkGate =
    "ALLOW_BRANCH_BUILD_MANIFEST_BODY_CN_V1"
  package static let requiredManifestStructureNetworkGate =
    "ALLOW_BRANCH_BUILD_MANIFEST_STRUCTURE_CN_V1"
  package static let requiredChunkPayloadNetworkGate =
    "ALLOW_BRANCH_BUILD_ONE_CHUNK_PAYLOAD_CN_V1"
  package static let networkGateEnvironmentKey = "MGB_MANIFEST_SAMPLE_NETWORK"
  package static let maximumResponseBytes: UInt64 = 1 * 1_024 * 1_024

  private let configuration: URLSessionConfiguration?
  private let now: @Sendable () -> Date
  private let mainBuildSemanticPolicy: BranchSemanticPolicy
  private let mainBuildResponseSemanticPolicy: MainBuildSemanticPolicy
  private let manifestMetadataOriginPin: ManifestOriginPin
  private let manifestBodyExpectedRequestPathSHA256: String
  private let manifestBodyExpectedCompressedSize: UInt64
  private let manifestStructureExpectedBodySHA256: String
  private let chunkPayloadOriginPin: ManifestOriginPin

  package init() {
    configuration = nil
    now = Date.init
    mainBuildSemanticPolicy = .observedCNV1
    mainBuildResponseSemanticPolicy = .observedCNV1
    manifestMetadataOriginPin = ManifestMetadataDiscoveryProfile.originPin
    manifestBodyExpectedRequestPathSHA256 = ManifestBodyDiscoveryProfile.expectedRequestPathSHA256
    manifestBodyExpectedCompressedSize = ManifestBodyDiscoveryProfile.expectedCompressedSize
    manifestStructureExpectedBodySHA256 =
      ManifestStructureDiscoveryProfile.expectedCompressedBodySHA256
    chunkPayloadOriginPin = ManifestChunkPayloadDiscoveryProfile.chunkOriginPin
  }

  init(
    configuration: URLSessionConfiguration,
    now: @escaping @Sendable () -> Date = Date.init,
    mainBuildSemanticPolicy: BranchSemanticPolicy = .observedCNV1,
    mainBuildResponseSemanticPolicy: MainBuildSemanticPolicy = .observedCNV1,
    manifestMetadataOriginPin: ManifestOriginPin = ManifestMetadataDiscoveryProfile.originPin,
    manifestBodyExpectedRequestPathSHA256: String =
      ManifestBodyDiscoveryProfile.expectedRequestPathSHA256,
    manifestBodyExpectedCompressedSize: UInt64 =
      ManifestBodyDiscoveryProfile.expectedCompressedSize,
    manifestStructureExpectedBodySHA256: String =
      ManifestStructureDiscoveryProfile.expectedCompressedBodySHA256,
    chunkPayloadOriginPin: ManifestOriginPin =
      ManifestChunkPayloadDiscoveryProfile.chunkOriginPin
  ) {
    let copiedConfiguration = configuration.copy() as! URLSessionConfiguration
    self.configuration = copiedConfiguration
    self.now = now
    self.mainBuildSemanticPolicy = mainBuildSemanticPolicy
    self.mainBuildResponseSemanticPolicy = mainBuildResponseSemanticPolicy
    self.manifestMetadataOriginPin = manifestMetadataOriginPin
    self.manifestBodyExpectedRequestPathSHA256 = manifestBodyExpectedRequestPathSHA256
    self.manifestBodyExpectedCompressedSize = manifestBodyExpectedCompressedSize
    self.manifestStructureExpectedBodySHA256 = manifestStructureExpectedBodySHA256
    self.chunkPayloadOriginPin = chunkPayloadOriginPin
  }

  package static func plan() -> BranchDiscoveryPlan {
    BranchDiscoveryProfile.cn.plan
  }

  package static func shapeReportPlan() -> BranchShapeReportPlan {
    BranchShapeDiscoveryProfile.plan
  }

  package static func mainBuildShapePlan() -> MainBuildShapePlan {
    MainBuildShapeDiscoveryProfile.plan
  }

  package static func manifestOriginPlan() -> ManifestOriginPlan {
    ManifestOriginDiscoveryProfile.plan
  }

  package static func chunkOriginPlan() -> ChunkOriginPlan {
    ChunkOriginDiscoveryProfile.plan
  }

  package static func manifestMetadataPlan() -> ManifestMetadataPlan {
    ManifestMetadataDiscoveryProfile.plan
  }

  package static func manifestBodyPlan() -> ManifestBodyPlan {
    ManifestBodyDiscoveryProfile.plan
  }

  package static func manifestStructurePlan() -> ManifestStructurePlan {
    ManifestStructureDiscoveryProfile.plan
  }

  package static func manifestChunkPayloadPlan() -> ManifestChunkPayloadPlan {
    ManifestChunkPayloadDiscoveryProfile.plan
  }

  package func sampleCN(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> BranchDiscoveryReceipt {
    try Task.checkCancellation()
    let profile = BranchDiscoveryProfile.cn
    guard networkGate == Self.requiredNetworkGate,
      acknowledgedPlanSHA256 == profile.plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let result = try await sample(
      profile: BranchTransportProfile(
        profileID: profile.profileID,
        url: profile.url,
        requestIdentitySHA256: profile.requestIdentitySHA256,
        policySHA256: profile.plan.policySHA256,
        maximumResponseBytes: Self.maximumResponseBytes
      ),
      mode: .branches(reportLimits: nil, semanticPolicy: nil)
    )
    guard case .branches(let shape, _) = result.document else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    return BranchDiscoveryReceipt(
      schemaVersion: 1,
      profileID: result.profileID,
      requestIdentitySHA256: result.requestIdentitySHA256,
      policySHA256: result.policySHA256,
      statusCode: result.statusCode,
      observedAtUnixSeconds: result.observedAtUnixSeconds,
      bodySHA256: result.bodySHA256,
      byteSize: result.byteSize,
      valueFreeShapePolicyVersion: shape.policyVersion,
      valueFreeShapeSHA256: shape.sha256,
      gameBranchEntryCount: shape.gameBranchEntryCount
    )
  }

  package func sampleCNShapeReport(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> BranchShapeReportReceipt {
    try Task.checkCancellation()
    let plan = BranchShapeDiscoveryProfile.plan
    guard networkGate == Self.requiredShapeReportNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let result = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID,
        url: base.url,
        requestIdentitySHA256: plan.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: Self.maximumResponseBytes
      ),
      mode: .branches(reportLimits: .standard, semanticPolicy: nil)
    )
    guard case .branches(let shape, _) = result.document,
      let report = shape.safeReport
    else {
      throw ManifestSamplingError.shapeReportLimit
    }
    let receipt = BranchShapeReportReceipt(
      schemaVersion: 1,
      profileID: result.profileID,
      requestIdentitySHA256: result.requestIdentitySHA256,
      policySHA256: result.policySHA256,
      statusCode: result.statusCode,
      observedAtUnixSeconds: result.observedAtUnixSeconds,
      bodySHA256: result.bodySHA256,
      byteSize: result.byteSize,
      valueFreeShapePolicyVersion: shape.policyVersion,
      valueFreeShapeSHA256: shape.sha256,
      gameBranchEntryCount: shape.gameBranchEntryCount,
      reportPolicyVersion: report.policyVersion,
      reportSHA256: report.sha256,
      canonicalReportByteSize: report.canonicalByteSize,
      matchesPriorShape: BranchShapeDiscoveryProfile.matchesPriorShape(
        policyVersion: shape.policyVersion,
        sha256: shape.sha256,
        gameBranchEntryCount: shape.gameBranchEntryCount
      ),
      shape: report.root
    )
    let canonical = try ManifestSamplingCanonicalJSON.encode(receipt)
    guard canonical.count <= BranchShapeDiscoveryProfile.maximumCanonicalReceiptBytes else {
      throw ManifestSamplingError.shapeReportLimit
    }
    return receipt
  }

  package func sampleCNMainBuildShape(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> MainBuildShapeReceipt {
    try Task.checkCancellation()
    let plan = MainBuildShapeDiscoveryProfile.plan
    guard networkGate == Self.requiredMainBuildNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-branches",
        url: base.url,
        requestIdentitySHA256: plan.branchRequestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: plan.maximumBranchResponseBytes
      ),
      mode: .branches(
        reportLimits: .standard,
        semanticPolicy: mainBuildSemanticPolicy
      )
    )
    guard case .branches(let branchShape, let capability) = branchResult.document,
      let branchReport = branchShape.safeReport,
      let capability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: capability
    )
    let buildResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-build",
        url: buildRequest.url,
        requestIdentitySHA256: buildRequest.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: plan.maximumBuildResponseBytes
      ),
      mode: .rootData(reportLimits: .standard, semanticContext: nil)
    )
    guard case .rootData(let buildShape, _) = buildResult.document,
      let buildReport = buildShape.safeReport
    else {
      throw ManifestSamplingError.shapeReportLimit
    }
    let (totalBytes, overflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !overflow, totalBytes <= plan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    let receipt = MainBuildShapeReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchRequestIdentitySHA256: plan.branchRequestIdentitySHA256,
      buildRequestTemplateSHA256: plan.buildRequestTemplateSHA256,
      branchObservedAtUnixSeconds: branchResult.observedAtUnixSeconds,
      branchBodySHA256: branchResult.bodySHA256,
      branchByteSize: branchResult.byteSize,
      branchShapeSHA256: branchShape.sha256,
      branchReportSHA256: branchReport.sha256,
      buildObservedAtUnixSeconds: buildResult.observedAtUnixSeconds,
      buildStatusCode: buildResult.statusCode,
      buildBodySHA256: buildResult.bodySHA256,
      buildByteSize: buildResult.byteSize,
      buildShapePolicyVersion: buildShape.policyVersion,
      buildShapeSHA256: buildShape.sha256,
      buildReportPolicyVersion: buildReport.policyVersion,
      buildReportSHA256: buildReport.sha256,
      canonicalBuildReportByteSize: buildReport.canonicalByteSize,
      requestCount: 2,
      shape: buildReport.root
    )
    let canonical = try ManifestSamplingCanonicalJSON.encode(receipt)
    guard canonical.count <= MainBuildShapeDiscoveryProfile.maximumCanonicalReceiptBytes else {
      throw ManifestSamplingError.shapeReportLimit
    }
    return receipt
  }

  package func sampleCNManifestOrigin(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> ManifestOriginReceipt {
    try Task.checkCancellation()
    let plan = ManifestOriginDiscoveryProfile.plan
    let buildPlan = plan.mainBuildPlan
    guard networkGate == Self.requiredManifestOriginNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-branches",
        url: base.url,
        requestIdentitySHA256: buildPlan.branchRequestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBranchResponseBytes
      ),
      mode: .branches(
        reportLimits: .standard,
        semanticPolicy: mainBuildSemanticPolicy
      )
    )
    guard case .branches(let branchShape, let branchCapability) = branchResult.document,
      let branchReport = branchShape.safeReport,
      let branchCapability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: branchCapability
    )
    let buildResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-build",
        url: buildRequest.url,
        requestIdentitySHA256: buildRequest.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBuildResponseBytes
      ),
      mode: .rootData(
        reportLimits: .standard,
        semanticContext: .origin(
          branchCapability: branchCapability,
          policy: mainBuildResponseSemanticPolicy
        )
      )
    )
    guard case .rootData(let buildShape, let semanticDocument) = buildResult.document,
      let buildReport = buildShape.safeReport,
      case .some(.origin(let originReference)) = semanticDocument
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let origin = try ManifestOriginDiscoveryProfile.inspect(capability: originReference)
    let (totalBytes, overflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !overflow, totalBytes <= buildPlan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    try Task.checkCancellation()
    return ManifestOriginReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchBodySHA256: branchResult.bodySHA256,
      branchShapeSHA256: branchShape.sha256,
      branchReportSHA256: branchReport.sha256,
      buildBodySHA256: buildResult.bodySHA256,
      buildShapeSHA256: buildShape.sha256,
      buildReportSHA256: buildReport.sha256,
      manifestSafeOrigin: origin.safeOrigin,
      manifestPathComponentCount: origin.pathComponentCount,
      manifestPathSHA256: origin.pathSHA256,
      observedAtUnixSeconds: buildResult.observedAtUnixSeconds,
      requestCount: 2
    )
  }

  package func sampleCNChunkOrigin(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> ChunkOriginReceipt {
    try Task.checkCancellation()
    let plan = ChunkOriginDiscoveryProfile.plan
    let buildPlan = plan.mainBuildPlan
    guard networkGate == Self.requiredChunkOriginNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-branches",
        url: base.url,
        requestIdentitySHA256: buildPlan.branchRequestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBranchResponseBytes
      ),
      mode: .branches(
        reportLimits: .standard,
        semanticPolicy: mainBuildSemanticPolicy
      )
    )
    guard case .branches(_, let branchCapability) = branchResult.document,
      let branchCapability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: branchCapability
    )
    let buildResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-build",
        url: buildRequest.url,
        requestIdentitySHA256: buildRequest.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBuildResponseBytes
      ),
      mode: .rootData(
        reportLimits: .standard,
        semanticContext: .chunkOrigin(
          branchCapability: branchCapability,
          policy: mainBuildResponseSemanticPolicy
        )
      )
    )
    guard case .rootData(let buildShape, let semanticDocument) = buildResult.document,
      let buildReport = buildShape.safeReport,
      case .some(.chunkOrigin(let originReference)) = semanticDocument
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let origin = try ChunkOriginDiscoveryProfile.inspect(capability: originReference)
    let (totalBytes, overflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !overflow, totalBytes <= buildPlan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    try Task.checkCancellation()
    return ChunkOriginReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchBodySHA256: branchResult.bodySHA256,
      buildBodySHA256: buildResult.bodySHA256,
      buildShapeSHA256: buildShape.sha256,
      buildReportSHA256: buildReport.sha256,
      chunkSafeOrigin: origin.safeOrigin,
      chunkPathComponentCount: origin.pathComponentCount,
      chunkPathSHA256: origin.pathSHA256,
      observedAtUnixSeconds: buildResult.observedAtUnixSeconds,
      requestCount: 2
    )
  }

  package func sampleCNManifestMetadata(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> ManifestMetadataReceipt {
    try Task.checkCancellation()
    let plan = ManifestMetadataDiscoveryProfile.plan
    let buildPlan = plan.originPlan.mainBuildPlan
    guard networkGate == Self.requiredManifestMetadataNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-branches",
        url: base.url,
        requestIdentitySHA256: buildPlan.branchRequestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBranchResponseBytes
      ),
      mode: .branches(
        reportLimits: .standard,
        semanticPolicy: mainBuildSemanticPolicy
      )
    )
    guard case .branches(_, let branchCapability) = branchResult.document,
      let branchCapability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: branchCapability
    )
    let buildResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-build",
        url: buildRequest.url,
        requestIdentitySHA256: buildRequest.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBuildResponseBytes
      ),
      mode: .rootData(
        reportLimits: .standard,
        semanticContext: .manifestRequest(
          branchCapability: branchCapability,
          policy: mainBuildResponseSemanticPolicy,
          originPin: manifestMetadataOriginPin
        )
      )
    )
    guard case .rootData(let buildShape, let semanticDocument) = buildResult.document,
      let buildReport = buildShape.safeReport,
      case .some(.manifestRequest(let requestReference)) = semanticDocument
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let (jsonBytes, overflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !overflow, jsonBytes <= buildPlan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    try Task.checkCancellation()
    let manifestRequestIdentity = ManifestMetadataDiscoveryProfile.requestIdentity(
      for: requestReference.manifestURL
    )
    guard manifestRequestIdentity.utf8.count == 64 else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    let metadataResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-manifest",
        url: requestReference.manifestURL,
        requestIdentitySHA256: manifestRequestIdentity,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: plan.maximumDeclaredContentLength
      ),
      mode: .metadataOnly
    )
    guard case .metadata(let metadata) = metadataResult.document else {
      throw ManifestSamplingError.transportFailure
    }
    let requestPathSHA256 = try ManifestMetadataDiscoveryProfile.requestPathSHA256(
      requestReference.manifestURL,
      expectedSafeOrigin: requestReference.safeOrigin
    )
    try Task.checkCancellation()
    return ManifestMetadataReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchBodySHA256: branchResult.bodySHA256,
      buildBodySHA256: buildResult.bodySHA256,
      buildShapeSHA256: buildShape.sha256,
      buildReportSHA256: buildReport.sha256,
      manifestSafeOrigin: requestReference.safeOrigin,
      manifestPrefixPathComponentCount: requestReference.prefixPathComponentCount,
      manifestPrefixPathSHA256: requestReference.prefixPathSHA256,
      manifestRequestPathSHA256: requestPathSHA256,
      statusCode: metadata.statusCode,
      contentTypeKind: metadata.contentTypeKind,
      contentEncodingKind: metadata.contentEncodingKind,
      contentLengthState: metadata.contentLengthState,
      declaredContentLength: metadata.declaredContentLength,
      observedAtUnixSeconds: metadata.observedAtUnixSeconds,
      requestCount: 3,
      responseBodyAccepted: false
    )
  }

  package func sampleCNManifestBody(
    acknowledgedPlanSHA256: String,
    networkGate: String?
  ) async throws -> ManifestBodyReceipt {
    try Task.checkCancellation()
    let plan = ManifestBodyDiscoveryProfile.plan
    let buildPlan = plan.metadataPlan.originPlan.mainBuildPlan
    guard networkGate == Self.requiredManifestBodyNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-branches",
        url: base.url,
        requestIdentitySHA256: buildPlan.branchRequestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBranchResponseBytes
      ),
      mode: .branches(
        reportLimits: .standard,
        semanticPolicy: mainBuildSemanticPolicy
      )
    )
    guard case .branches(_, let branchCapability) = branchResult.document,
      let branchCapability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: branchCapability
    )
    let buildResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-build",
        url: buildRequest.url,
        requestIdentitySHA256: buildRequest.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBuildResponseBytes
      ),
      mode: .rootData(
        reportLimits: .standard,
        semanticContext: .manifestBodyRequest(
          branchCapability: branchCapability,
          policy: mainBuildResponseSemanticPolicy,
          originPin: manifestMetadataOriginPin,
          expectedRequestPathSHA256: manifestBodyExpectedRequestPathSHA256,
          expectedCompressedSize: manifestBodyExpectedCompressedSize
        )
      )
    )
    guard case .rootData(let buildShape, let semanticDocument) = buildResult.document,
      let buildReport = buildShape.safeReport,
      case .some(.manifestBodyRequest(let requestReference)) = semanticDocument
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let (jsonBytes, overflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !overflow, jsonBytes <= buildPlan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    try Task.checkCancellation()
    let manifestRequestIdentity = ManifestMetadataDiscoveryProfile.requestIdentity(
      for: requestReference.manifestURL
    )
    guard manifestRequestIdentity.utf8.count == 64 else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    let bodyResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-manifest",
        url: requestReference.manifestURL,
        requestIdentitySHA256: manifestRequestIdentity,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: manifestBodyExpectedCompressedSize
      ),
      mode: .binaryBody(
        expectedContentLength: manifestBodyExpectedCompressedSize,
        retainBody: false,
        allowsBoundedContentTypeParameters: false
      )
    )
    guard case .binary(let evidence, nil) = bodyResult.document,
      bodyResult.byteSize == manifestBodyExpectedCompressedSize
    else {
      throw ManifestSamplingError.contentLengthRejected
    }
    try Task.checkCancellation()
    return ManifestBodyReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchBodySHA256: branchResult.bodySHA256,
      buildBodySHA256: buildResult.bodySHA256,
      buildShapeSHA256: buildShape.sha256,
      buildReportSHA256: buildReport.sha256,
      manifestSafeOrigin: requestReference.safeOrigin,
      manifestPrefixPathSHA256: requestReference.prefixPathSHA256,
      manifestRequestPathSHA256: requestReference.requestPathSHA256,
      statusCode: bodyResult.statusCode,
      contentTypeKind: "applicationOctetStream",
      contentEncodingKind: evidence.contentEncodingKind,
      declaredContentLength: requestReference.expectedCompressedSize,
      bodySHA256: bodyResult.bodySHA256,
      byteSize: bodyResult.byteSize,
      frameKind: evidence.frameKind,
      observedAtUnixSeconds: bodyResult.observedAtUnixSeconds,
      requestCount: 3
    )
  }

  package func sampleCNManifestStructure(
    acknowledgedPlanSHA256: String,
    networkGate: String?,
    inspector: any ManifestBodyStructurallyInspecting
  ) async throws -> ManifestStructureReceipt {
    try Task.checkCancellation()
    let plan = ManifestStructureDiscoveryProfile.plan
    let bodyPlan = plan.bodyPlan
    let buildPlan = bodyPlan.metadataPlan.originPlan.mainBuildPlan
    guard networkGate == Self.requiredManifestStructureNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult: BranchTransportResult
    do {
      branchResult = try await sample(
        profile: BranchTransportProfile(
          profileID: plan.profileID + "-branches",
          url: base.url,
          requestIdentitySHA256: buildPlan.branchRequestIdentitySHA256,
          policySHA256: plan.policySHA256,
          maximumResponseBytes: buildPlan.maximumBranchResponseBytes
        ),
        mode: .branches(
          reportLimits: .standard,
          semanticPolicy: mainBuildSemanticPolicy
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestSamplingError.structureBranchRejected
    }
    guard case .branches(_, let branchCapability) = branchResult.document,
      let branchCapability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: branchCapability
    )
    let buildResult: BranchTransportResult
    do {
      buildResult = try await sample(
        profile: BranchTransportProfile(
          profileID: plan.profileID + "-build",
          url: buildRequest.url,
          requestIdentitySHA256: buildRequest.requestIdentitySHA256,
          policySHA256: plan.policySHA256,
          maximumResponseBytes: buildPlan.maximumBuildResponseBytes
        ),
        mode: .rootData(
          reportLimits: .standard,
          semanticContext: .manifestBodyRequest(
            branchCapability: branchCapability,
            policy: mainBuildResponseSemanticPolicy,
            originPin: manifestMetadataOriginPin,
            expectedRequestPathSHA256: manifestBodyExpectedRequestPathSHA256,
            expectedCompressedSize: manifestBodyExpectedCompressedSize
          )
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestSamplingError.structureBuildRejected
    }
    guard case .rootData(let buildShape, let semanticDocument) = buildResult.document,
      let buildReport = buildShape.safeReport,
      case .some(.manifestBodyRequest(let requestReference)) = semanticDocument
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let (jsonBytes, overflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !overflow, jsonBytes <= buildPlan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    try Task.checkCancellation()
    let manifestRequestIdentity = ManifestMetadataDiscoveryProfile.requestIdentity(
      for: requestReference.manifestURL
    )
    guard manifestRequestIdentity.utf8.count == 64 else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    let bodyResult: BranchTransportResult
    do {
      bodyResult = try await sample(
        profile: BranchTransportProfile(
          profileID: plan.profileID + "-manifest",
          url: requestReference.manifestURL,
          requestIdentitySHA256: manifestRequestIdentity,
          policySHA256: plan.policySHA256,
          maximumResponseBytes: manifestBodyExpectedCompressedSize
        ),
        mode: .binaryBody(
          expectedContentLength: manifestBodyExpectedCompressedSize,
          retainBody: true,
          allowsBoundedContentTypeParameters: true
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestSamplingError {
      switch error {
      case .redirectRejected, .authenticationRejected, .responseIdentityMismatch:
        throw ManifestSamplingError.structureManifestIdentityRejected
      case .statusRejected:
        throw ManifestSamplingError.structureManifestStatusRejected
      case .contentTypeRejected, .contentTypeAndEncodingRejected,
        .contentTypeAndLengthRejected, .contentTypeEncodingAndLengthRejected:
        throw ManifestSamplingError.structureManifestContentTypeRejected
      case .contentEncodingRejected, .contentEncodingAndLengthRejected:
        throw ManifestSamplingError.structureManifestEncodingRejected
      case .contentLengthRejected:
        throw ManifestSamplingError.structureManifestLengthRejected
      case .oversized:
        throw ManifestSamplingError.structureManifestOversized
      default:
        throw ManifestSamplingError.structureManifestResponseRejected
      }
    } catch {
      throw ManifestSamplingError.structureManifestResponseRejected
    }
    guard case .binary(_, let retainedBody?) = bodyResult.document,
      bodyResult.byteSize == manifestBodyExpectedCompressedSize,
      bodyResult.bodySHA256 == manifestStructureExpectedBodySHA256
    else {
      throw ManifestSamplingError.contentLengthRejected
    }
    try Task.checkCancellation()
    let structural = try inspector.inspect(
      ManifestLiveBodyInspectionInput(
        data: retainedBody,
        compressedSHA256: bodyResult.bodySHA256,
        byteSize: bodyResult.byteSize,
        manifestID: requestReference.manifestID.rawValue,
        plan: plan
      )
    )
    try Task.checkCancellation()
    return ManifestStructureReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchBodySHA256: branchResult.bodySHA256,
      buildBodySHA256: buildResult.bodySHA256,
      buildShapeSHA256: buildShape.sha256,
      buildReportSHA256: buildReport.sha256,
      compressedBodySHA256: bodyResult.bodySHA256,
      compressedByteSize: bodyResult.byteSize,
      decompressedBodySHA256: structural.decompressedBodySHA256,
      decompressedByteSize: structural.decompressedByteSize,
      wirePolicyVersion: structural.wirePolicyVersion,
      fileCount: structural.fileCount,
      directoryCount: structural.directoryCount,
      chunkReferenceCount: structural.chunkReferenceCount,
      uniqueChunkObjectCount: structural.uniqueChunkObjectCount,
      targetInstalledBytes: structural.targetInstalledBytes,
      referencedChunkCompressedBytes: structural.referencedChunkCompressedBytes,
      uniqueChunkObjectBytes: structural.uniqueChunkObjectBytes,
      wireNodeCount: structural.wireNodeCount,
      wireStringBytes: structural.wireStringBytes,
      observedAtUnixSeconds: bodyResult.observedAtUnixSeconds,
      requestCount: 3
    )
  }

  package func sampleCNManifestChunkPayload(
    acknowledgedPlanSHA256: String,
    networkGate: String?,
    inspector: any ManifestBodyStructurallyInspecting,
    verifier: any ManifestChunkPayloadVerifying
  ) async throws -> ManifestChunkPayloadReceipt {
    try Task.checkCancellation()
    let plan = ManifestChunkPayloadDiscoveryProfile.plan
    let structurePlan = plan.structurePlan
    let bodyPlan = structurePlan.bodyPlan
    let buildPlan = bodyPlan.metadataPlan.originPlan.mainBuildPlan
    guard networkGate == Self.requiredChunkPayloadNetworkGate,
      acknowledgedPlanSHA256 == plan.policySHA256
    else {
      throw ManifestSamplingError.executionGateClosed
    }
    let base = BranchDiscoveryProfile.cn
    let branchResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-branches",
        url: base.url,
        requestIdentitySHA256: buildPlan.branchRequestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBranchResponseBytes
      ),
      mode: .branches(
        reportLimits: .standard,
        semanticPolicy: mainBuildSemanticPolicy
      )
    )
    guard case .branches(_, let branchCapability) = branchResult.document,
      let branchCapability
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    try Task.checkCancellation()
    let buildRequest = try MainBuildShapeDiscoveryProfile.makeBuildRequest(
      capability: branchCapability
    )
    let buildResult = try await sample(
      profile: BranchTransportProfile(
        profileID: plan.profileID + "-build",
        url: buildRequest.url,
        requestIdentitySHA256: buildRequest.requestIdentitySHA256,
        policySHA256: plan.policySHA256,
        maximumResponseBytes: buildPlan.maximumBuildResponseBytes
      ),
      mode: .rootData(
        reportLimits: .standard,
        semanticContext: .chunkPayloadRequest(
          branchCapability: branchCapability,
          policy: mainBuildResponseSemanticPolicy,
          manifestOriginPin: manifestMetadataOriginPin,
          expectedManifestRequestPathSHA256: manifestBodyExpectedRequestPathSHA256,
          expectedManifestCompressedSize: manifestBodyExpectedCompressedSize,
          chunkOriginPin: chunkPayloadOriginPin
        )
      )
    )
    guard case .rootData(_, let semanticDocument) = buildResult.document,
      case .some(.chunkPayloadRequest(let requestReference)) = semanticDocument
    else {
      throw ManifestSamplingError.semanticShapeRejected
    }
    let (jsonBytes, jsonOverflow) = branchResult.byteSize.addingReportingOverflow(
      buildResult.byteSize
    )
    guard !jsonOverflow, jsonBytes <= buildPlan.maximumTotalResponseBytes else {
      throw ManifestSamplingError.oversized
    }
    try Task.checkCancellation()
    let manifestRequestIdentity = ManifestMetadataDiscoveryProfile.requestIdentity(
      for: requestReference.manifestRequest.manifestURL
    )
    guard manifestRequestIdentity.utf8.count == 64 else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    let manifestResult: BranchTransportResult
    do {
      manifestResult = try await sample(
        profile: BranchTransportProfile(
          profileID: plan.profileID + "-manifest",
          url: requestReference.manifestRequest.manifestURL,
          requestIdentitySHA256: manifestRequestIdentity,
          policySHA256: plan.policySHA256,
          maximumResponseBytes: manifestBodyExpectedCompressedSize
        ),
        mode: .binaryBody(
          expectedContentLength: manifestBodyExpectedCompressedSize,
          retainBody: true,
          allowsBoundedContentTypeParameters: true
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestSamplingError.structureManifestResponseRejected
    }
    guard case .binary(_, let retainedManifest?) = manifestResult.document,
      manifestResult.byteSize == manifestBodyExpectedCompressedSize,
      manifestResult.bodySHA256 == manifestStructureExpectedBodySHA256
    else {
      throw ManifestSamplingError.structureManifestResponseRejected
    }
    let structural: ManifestChunkStructuralEvidence
    do {
      structural = try inspector.inspect(
        ManifestLiveBodyInspectionInput(
          data: retainedManifest,
          compressedSHA256: manifestResult.bodySHA256,
          byteSize: manifestResult.byteSize,
          manifestID: requestReference.manifestRequest.manifestID.rawValue,
          plan: structurePlan
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestSamplingError {
      throw error
    } catch {
      throw ManifestSamplingError.manifestStructuralRejected
    }
    guard let candidate = structural.payloadCandidate,
      candidate.compressedBytes > 0,
      candidate.compressedBytes <= plan.maximumPayloadBytes,
      candidate.uncompressedBytes > 0,
      candidate.uncompressedBytes <= plan.maximumUncompressedPayloadBytes,
      candidate.wireField7OpaqueHash.utf8.count == 32
    else {
      throw ManifestSamplingError.chunkCandidateRejected
    }
    try Task.checkCancellation()
    let chunkURL = try ManifestChunkPayloadDiscoveryProfile.makeChunkURL(
      prefix: requestReference.chunkURLPrefix.rawValue,
      objectID: candidate.objectID
    )
    let chunkRequestIdentity = ManifestChunkPayloadDiscoveryProfile.requestIdentity(for: chunkURL)
    guard chunkRequestIdentity.utf8.count == 64 else {
      throw ManifestSamplingError.requestIdentityMismatch
    }
    let chunkRequestPathSHA256 = try ManifestChunkPayloadDiscoveryProfile.requestPathSHA256(
      chunkURL,
      expectedSafeOrigin: requestReference.chunkSafeOrigin
    )
    let chunkResult: BranchTransportResult
    do {
      chunkResult = try await sample(
        profile: BranchTransportProfile(
          profileID: plan.profileID + "-chunk",
          url: chunkURL,
          requestIdentitySHA256: chunkRequestIdentity,
          policySHA256: plan.policySHA256,
          maximumResponseBytes: candidate.compressedBytes
        ),
        mode: .binaryBody(
          expectedContentLength: candidate.compressedBytes,
          retainBody: true,
          allowsBoundedContentTypeParameters: true
        )
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ManifestSamplingError.chunkResponseRejected
    }
    guard case .binary(_, let retainedChunk?) = chunkResult.document,
      chunkResult.byteSize == candidate.compressedBytes
    else {
      throw ManifestSamplingError.chunkResponseRejected
    }
    let stored: ManifestChunkPayloadStoredEvidence
    do {
      stored = try verifier.verifyAndStore(
        ManifestChunkPayloadVerificationInput(data: retainedChunk, candidate: candidate)
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestSamplingError {
      throw error
    } catch {
      throw ManifestSamplingError.chunkIntegrityRejected
    }
    let expectedCachePath =
      "objects/sha256/\(stored.sha256.prefix(2))/\(stored.sha256)"
    guard stored.byteSize == candidate.compressedBytes,
      stored.compressedMD5 == candidate.wireField7OpaqueHash,
      stored.uncompressedByteSize == candidate.uncompressedBytes,
      stored.uncompressedMD5 == candidate.uncompressedMD5,
      stored.sha256.utf8.count == 64,
      stored.cacheRelativePath == expectedCachePath,
      ["stored", "reused", "concurrentCacheHit"].contains(stored.cacheDisposition)
    else {
      throw ManifestSamplingError.chunkCacheRejected
    }
    try Task.checkCancellation()
    return ManifestChunkPayloadReceipt(
      schemaVersion: 1,
      profileID: plan.profileID,
      policySHA256: plan.policySHA256,
      branchBodySHA256: branchResult.bodySHA256,
      buildBodySHA256: buildResult.bodySHA256,
      manifestBodySHA256: manifestResult.bodySHA256,
      manifestDecompressedSHA256: structural.decompressedBodySHA256,
      chunkObjectIDSHA256: SHA256.hash(data: Data(candidate.objectID.utf8))
        .map { String(format: "%02x", $0) }.joined(),
      chunkRequestPathSHA256: chunkRequestPathSHA256,
      chunkByteSize: stored.byteSize,
      chunkSHA256: stored.sha256,
      field7CompressedMD5Verified: true,
      uncompressedMD5Verified: true,
      cacheDisposition: stored.cacheDisposition,
      cacheRelativePath: stored.cacheRelativePath,
      observedAtUnixSeconds: chunkResult.observedAtUnixSeconds,
      requestCount: 4
    )
  }

  private func sample(
    profile: BranchTransportProfile,
    mode: JSONDiscoveryMode
  ) async throws -> BranchTransportResult {
    try Task.checkCancellation()

    var request = URLRequest(url: profile.url)
    request.httpMethod = "GET"
    request.httpBody = nil
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.setValue(mode.requestAccept, forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    guard request.url?.absoluteString == profile.url.absoluteString,
      request.httpMethod == "GET", request.httpBody == nil,
      BranchDiscoveryProfile.requestIdentity(for: request) == profile.requestIdentitySHA256
    else {
      throw ManifestSamplingError.requestIdentityMismatch
    }

    let baseConfiguration = configuration ?? URLSessionConfiguration.ephemeral
    let sessionConfiguration = Self.makeSessionConfiguration(baseConfiguration)
    let delegate = BranchDiscoveryDelegate(
      profile: profile,
      mode: mode,
      now: now
    )
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    let session = URLSession(
      configuration: sessionConfiguration,
      delegate: delegate,
      delegateQueue: queue
    )
    defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: request)
    do {
      let receipt = try await withTaskCancellationHandler {
        try await delegate.run(task)
      } onCancel: {
        delegate.cancel()
        task.cancel()
      }
      try Task.checkCancellation()
      return receipt
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as ManifestSamplingError {
      throw error
    } catch {
      throw ManifestSamplingError.transportFailure
    }
  }

  static func makeSessionConfiguration(
    _ source: URLSessionConfiguration
  ) -> URLSessionConfiguration {
    let configuration = source.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.httpAdditionalHeaders = nil
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    configuration.httpMaximumConnectionsPerHost = 1
    configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
    return configuration
  }
}

extension BranchDiscoveryClient: ManifestSamplingRedactedValue {}

enum BranchDiscoveryAuthenticationPolicy {
  static func allowsDefaultHandling(
    authenticationMethod: String,
    host: String,
    protocolName: String?,
    port: Int,
    previousFailureCount: Int,
    expectedHost: String = "hyp-api.mihoyo.com"
  ) -> Bool {
    authenticationMethod == NSURLAuthenticationMethodServerTrust
      && host.lowercased() == expectedHost.lowercased()
      && protocolName?.lowercased() == "https"
      && port == 443
      && previousFailureCount == 0
  }
}

struct BranchDiscoveryProfile: Sendable {
  static let cn = BranchDiscoveryProfile()

  let profileID = "yaagl-ca78abc-cn-getGameBranches-a1"
  let url: URL
  let requestIdentitySHA256: String
  let plan: BranchDiscoveryPlan

  private init() {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "hyp-api.mihoyo.com"
    components.path = "/hyp/hyp-connect/api/getGameBranches"
    let exactQueryItems = [
      URLQueryItem(name: "game_ids[]", value: "1Z8W5NHUQb"),
      URLQueryItem(name: "launcher_id", value: "jGHBHlcOq1"),
    ]
    components.queryItems = exactQueryItems
    guard components.scheme == "https", components.host == "hyp-api.mihoyo.com",
      components.port == nil, components.user == nil, components.password == nil,
      components.path == "/hyp/hyp-connect/api/getGameBranches",
      components.fragment == nil, components.queryItems == exactQueryItems,
      let resolvedURL = components.url
    else {
      preconditionFailure("Invalid fixed branch discovery profile")
    }
    url = resolvedURL
    var request = URLRequest(url: resolvedURL)
    request.httpMethod = "GET"
    request.httpBody = nil
    request.httpShouldHandleCookies = false
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let identity = Self.requestIdentity(for: request)
    requestIdentitySHA256 = identity
    let planWithoutPolicy = BranchDiscoveryPlan(
      schemaVersion: 1,
      profileID: profileID,
      requestIdentitySHA256: identity,
      policySHA256: "",
      method: "GET",
      safeOrigin: "https://hyp-api.mihoyo.com",
      path: "/hyp/hyp-connect/api/getGameBranches",
      maximumResponseBytes: BranchDiscoveryClient.maximumResponseBytes,
      tlsPolicy: "systemTrustMinimumTLS12",
      authenticationPolicy: "serverTrustExactHost",
      finalURLPolicy: "exact",
      statusPolicy: "exact200",
      contentTypePolicy: "applicationJSONUTF8",
      contentEncodingPolicy: "identity",
      retryPolicy: "singleTaskNoApplicationRetry",
      cachePolicy: "none",
      cookiePolicy: "noSendNoStoreIgnoreResponseSetCookie",
      redirectPolicy: "reject",
      persistencePolicy: "responseBodyMemoryOnlyNoExplicitFileWrite",
      requestTimeoutSeconds: 15,
      resourceTimeoutSeconds: 20
    )
    plan = planWithoutPolicy.replacingPolicySHA256(
      BranchDiscoveryPolicyHasher.hash(planWithoutPolicy))
  }

  static func requestIdentity(for request: URLRequest) -> String {
    guard let url = request.url else { return "" }
    return sha256(
      [
        "MGBMANIFESTSAMPLEREQUEST\0", "1", request.httpMethod ?? "", url.absoluteString,
        request.value(forHTTPHeaderField: "Accept") ?? "",
        request.value(forHTTPHeaderField: "Accept-Encoding") ?? "",
        request.httpBody == nil ? "body=nil" : "body=present",
        request.httpShouldHandleCookies ? "handleCookies=true" : "handleCookies=false",
      ].joined(separator: "\0")
    )
  }

  static func sha256(_ value: String) -> String {
    sha256(Data(value.utf8))
  }

  static func sha256(_ value: Data) -> String {
    SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
  }
}

private struct BranchDiscoveryPolicyMaterial: Encodable {
  let schemaVersion: UInt8
  let profileID: String
  let requestIdentitySHA256: String
  let method: String
  let safeOrigin: String
  let path: String
  let maximumResponseBytes: UInt64
  let tlsPolicy: String
  let authenticationPolicy: String
  let finalURLPolicy: String
  let statusPolicy: String
  let contentTypePolicy: String
  let contentEncodingPolicy: String
  let retryPolicy: String
  let cachePolicy: String
  let cookiePolicy: String
  let redirectPolicy: String
  let persistencePolicy: String
  let requestTimeoutSeconds: UInt16
  let resourceTimeoutSeconds: UInt16

  init(_ plan: BranchDiscoveryPlan) {
    schemaVersion = plan.schemaVersion
    profileID = plan.profileID
    requestIdentitySHA256 = plan.requestIdentitySHA256
    method = plan.method
    safeOrigin = plan.safeOrigin
    path = plan.path
    maximumResponseBytes = plan.maximumResponseBytes
    tlsPolicy = plan.tlsPolicy
    authenticationPolicy = plan.authenticationPolicy
    finalURLPolicy = plan.finalURLPolicy
    statusPolicy = plan.statusPolicy
    contentTypePolicy = plan.contentTypePolicy
    contentEncodingPolicy = plan.contentEncodingPolicy
    retryPolicy = plan.retryPolicy
    cachePolicy = plan.cachePolicy
    cookiePolicy = plan.cookiePolicy
    redirectPolicy = plan.redirectPolicy
    persistencePolicy = plan.persistencePolicy
    requestTimeoutSeconds = plan.requestTimeoutSeconds
    resourceTimeoutSeconds = plan.resourceTimeoutSeconds
  }
}

enum BranchDiscoveryPolicyHasher {
  static func hash(_ plan: BranchDiscoveryPlan) -> String {
    guard
      let policyJSON = try? ManifestSamplingCanonicalJSON.encode(
        BranchDiscoveryPolicyMaterial(plan))
    else {
      preconditionFailure("Invalid fixed branch discovery policy")
    }
    var bytes = Data("MGBMANIFESTSAMPLEPLAN\0".utf8)
    bytes.append(policyJSON)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

extension BranchDiscoveryPlan {
  fileprivate func replacingPolicySHA256(_ value: String) -> BranchDiscoveryPlan {
    BranchDiscoveryPlan(
      schemaVersion: schemaVersion,
      profileID: profileID,
      requestIdentitySHA256: requestIdentitySHA256,
      policySHA256: value,
      method: method,
      safeOrigin: safeOrigin,
      path: path,
      maximumResponseBytes: maximumResponseBytes,
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
      requestTimeoutSeconds: requestTimeoutSeconds,
      resourceTimeoutSeconds: resourceTimeoutSeconds
    )
  }
}

private struct BranchTransportProfile: Sendable {
  let profileID: String
  let url: URL
  let requestIdentitySHA256: String
  let policySHA256: String
  let maximumResponseBytes: UInt64
}

extension BranchTransportProfile: ManifestSamplingRedactedValue {}

private struct BranchTransportResult: Sendable {
  let profileID: String
  let requestIdentitySHA256: String
  let policySHA256: String
  let statusCode: UInt16
  let observedAtUnixSeconds: Int64
  let bodySHA256: String
  let byteSize: UInt64
  let document: JSONDiscoveredDocument
}

extension BranchTransportResult: ManifestSamplingRedactedValue {}

private enum JSONDiscoveryMode: Sendable {
  case branches(
    reportLimits: SafeJSONShapeReportLimits?,
    semanticPolicy: BranchSemanticPolicy?
  )
  case rootData(
    reportLimits: SafeJSONShapeReportLimits?,
    semanticContext: MainBuildSemanticContext?
  )
  case metadataOnly
  case binaryBody(
    expectedContentLength: UInt64,
    retainBody: Bool,
    allowsBoundedContentTypeParameters: Bool
  )

  var requestAccept: String {
    switch self {
    case .branches, .rootData: "application/json"
    case .metadataOnly, .binaryBody: "application/octet-stream"
    }
  }
}

private enum JSONDiscoveredDocument: Sendable {
  case branches(JSONValueFreeShape, ValidatedCNBranchCapability?)
  case rootData(JSONRootDataValueFreeShape, MainBuildSemanticDocument?)
  case metadata(ManifestResponseMetadata)
  case binary(ManifestBinaryBodyEvidence, Data?)
}

private enum MainBuildSemanticContext: Sendable {
  case origin(
    branchCapability: ValidatedCNBranchCapability,
    policy: MainBuildSemanticPolicy
  )
  case manifestRequest(
    branchCapability: ValidatedCNBranchCapability,
    policy: MainBuildSemanticPolicy,
    originPin: ManifestOriginPin
  )
  case manifestBodyRequest(
    branchCapability: ValidatedCNBranchCapability,
    policy: MainBuildSemanticPolicy,
    originPin: ManifestOriginPin,
    expectedRequestPathSHA256: String,
    expectedCompressedSize: UInt64
  )
  case chunkOrigin(
    branchCapability: ValidatedCNBranchCapability,
    policy: MainBuildSemanticPolicy
  )
  case chunkPayloadRequest(
    branchCapability: ValidatedCNBranchCapability,
    policy: MainBuildSemanticPolicy,
    manifestOriginPin: ManifestOriginPin,
    expectedManifestRequestPathSHA256: String,
    expectedManifestCompressedSize: UInt64,
    chunkOriginPin: ManifestOriginPin
  )
}

private enum MainBuildSemanticDocument: Sendable {
  case origin(ValidatedMainBuildOriginReference)
  case manifestRequest(ValidatedMainManifestRequestReference)
  case manifestBodyRequest(ValidatedMainManifestBodyRequestReference)
  case chunkOrigin(ValidatedMainBuildChunkOriginReference)
  case chunkPayloadRequest(ValidatedMainChunkPayloadBuildReference)
}

private final class BranchDiscoveryDelegate: NSObject, URLSessionDataDelegate,
  URLSessionTaskDelegate, @unchecked Sendable
{
  private let profile: BranchTransportProfile
  private let mode: JSONDiscoveryMode
  private let now: @Sendable () -> Date
  private let lock = NSLock()
  private var body = Data()
  private var hasher = SHA256()
  private var expectedContentLength: UInt64?
  private var binaryContentEncodingKind: String?
  private var receivedResponse = false
  private var terminalError: (any Error)?
  private var continuation: CheckedContinuation<BranchTransportResult, any Error>?
  private var completion: Result<BranchTransportResult, any Error>?
  private let cancellationToken = SamplingCancellationToken()

  init(
    profile: BranchTransportProfile,
    mode: JSONDiscoveryMode,
    now: @escaping @Sendable () -> Date
  ) {
    self.profile = profile
    self.mode = mode
    self.now = now
    if case .metadataOnly = mode {
      return
    }
    body.reserveCapacity(64 * 1_024)
  }

  func run(_ task: URLSessionDataTask) async throws -> BranchTransportResult {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if let completion {
        lock.unlock()
        continuation.resume(with: completion)
        return
      }
      precondition(self.continuation == nil)
      self.continuation = continuation
      lock.unlock()
      task.resume()
    }
  }

  func cancel() {
    cancellationToken.cancel()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    recordTerminalError(ManifestSamplingError.redirectRejected)
    completionHandler(nil)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (
        URLSession.AuthChallengeDisposition, URLCredential?
      ) -> Void
  ) {
    handle(challenge, completionHandler: completionHandler)
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (
        URLSession.AuthChallengeDisposition, URLCredential?
      ) -> Void
  ) {
    handle(challenge, completionHandler: completionHandler)
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    do {
      guard !receivedResponse, terminalError == nil,
        let response = response as? HTTPURLResponse,
        response.url?.absoluteString == profile.url.absoluteString
      else {
        throw ManifestSamplingError.responseIdentityMismatch
      }
      guard response.statusCode == 200 else {
        throw ManifestSamplingError.statusRejected
      }
      if case .metadataOnly = mode {
        let observedAt = now().timeIntervalSince1970
        guard observedAt.isFinite,
          observedAt >= 0, observedAt <= 253_402_300_799
        else {
          throw ManifestSamplingError.transportFailure
        }
        let metadata = Self.makeMetadata(
          response,
          maximumDeclaredContentLength: profile.maximumResponseBytes,
          observedAtUnixSeconds: Int64(observedAt)
        )
        receivedResponse = true
        finish(
          .success(
            BranchTransportResult(
              profileID: profile.profileID,
              requestIdentitySHA256: profile.requestIdentitySHA256,
              policySHA256: profile.policySHA256,
              statusCode: 200,
              observedAtUnixSeconds: Int64(observedAt),
              bodySHA256: "",
              byteSize: 0,
              document: .metadata(metadata)
            )
          )
        )
        completionHandler(.cancel)
        return
      }
      if case .binaryBody(let expectedLength, _, let allowsParameters) = mode {
        guard expectedLength > 0, expectedLength <= profile.maximumResponseBytes else {
          throw ManifestSamplingError.oversized
        }
        guard
          Self.isAllowedOctetStream(
            response.value(forHTTPHeaderField: "Content-Type"),
            allowsBoundedParameters: allowsParameters
          )
        else {
          throw ManifestSamplingError.contentTypeRejected
        }
        guard Self.isIdentityEncoding(response.value(forHTTPHeaderField: "Content-Encoding")) else {
          throw ManifestSamplingError.contentEncodingRejected
        }
        guard response.value(forHTTPHeaderField: "Content-Length") == String(expectedLength),
          response.expectedContentLength == Int64(expectedLength)
        else {
          throw ManifestSamplingError.contentLengthRejected
        }
        expectedContentLength = expectedLength
        binaryContentEncodingKind =
          response.value(forHTTPHeaderField: "Content-Encoding") == nil ? "absent" : "identity"
        receivedResponse = true
        completionHandler(.allow)
        return
      }
      var metadataFailures: UInt8 = 0
      if !Self.isAllowedJSONContentType(response.value(forHTTPHeaderField: "Content-Type")) {
        metadataFailures |= 0b001
      }
      if !Self.isIdentityEncoding(response.value(forHTTPHeaderField: "Content-Encoding")) {
        metadataFailures |= 0b010
      }
      var parsedContentLength: UInt64?
      if let rawLength = response.value(forHTTPHeaderField: "Content-Length") {
        if let first = rawLength.utf8.first, (49...57).contains(first),
          rawLength.utf8.allSatisfy({ (48...57).contains($0) }),
          let length = UInt64(rawLength), length > 0
        {
          guard length <= profile.maximumResponseBytes else {
            throw ManifestSamplingError.oversized
          }
          if response.expectedContentLength == Int64(length) {
            parsedContentLength = length
          } else {
            metadataFailures |= 0b100
          }
        } else {
          metadataFailures |= 0b100
        }
      }
      guard metadataFailures == 0 else {
        throw Self.metadataError(metadataFailures)
      }
      expectedContentLength = parsedContentLength
      receivedResponse = true
      completionHandler(.allow)
    } catch {
      recordTerminalError(error)
      completionHandler(.cancel)
    }
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    guard terminalError == nil, receivedResponse else { return }
    if case .metadataOnly = mode {
      dataTask.cancel()
      return
    }
    let (next, overflow) = UInt64(body.count).addingReportingOverflow(UInt64(data.count))
    guard !overflow, next <= profile.maximumResponseBytes else {
      recordTerminalError(ManifestSamplingError.oversized)
      dataTask.cancel()
      return
    }
    guard expectedContentLength.map({ next <= $0 }) != false else {
      recordTerminalError(ManifestSamplingError.contentLengthRejected)
      dataTask.cancel()
      return
    }
    hasher.update(data: data)
    body.append(data)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let terminalError {
      finish(.failure(terminalError))
      return
    }
    if let error {
      if (error as? URLError)?.code == .cancelled {
        finish(.failure(CancellationError()))
      } else {
        finish(.failure(ManifestSamplingError.transportFailure))
      }
      return
    }
    do {
      guard receivedResponse else {
        throw ManifestSamplingError.responseIdentityMismatch
      }
      guard !body.isEmpty,
        expectedContentLength.map({ $0 == UInt64(body.count) }) != false
      else {
        throw ManifestSamplingError.contentLengthRejected
      }
      let bodySHA256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
      let document: JSONDiscoveredDocument
      switch mode {
      case .branches(let reportLimits, let semanticPolicy):
        let shape = try StrictJSONSchemaScanner.scan(
          body,
          reportLimits: reportLimits,
          cancellationCheck: cancellationToken.check
        )
        let capability: ValidatedCNBranchCapability?
        if let semanticPolicy {
          capability = try StrictCNBranchSemanticDecoder.decode(
            body,
            requestIdentitySHA256: profile.requestIdentitySHA256,
            transportPolicySHA256: profile.policySHA256,
            semanticPolicy: semanticPolicy,
            cancellationCheck: cancellationToken.check
          )
        } else {
          capability = nil
        }
        document = .branches(shape, capability)
      case .rootData(let reportLimits, let semanticContext):
        let shape = try StrictJSONSchemaScanner.scanRootData(
          body,
          reportLimits: reportLimits,
          cancellationCheck: cancellationToken.check
        )
        let semanticDocument: MainBuildSemanticDocument?
        switch semanticContext {
        case .origin(let branchCapability, let policy):
          semanticDocument = .origin(
            try StrictMainBuildOriginDecoder.decode(
              body,
              branchCapability: branchCapability,
              transportPolicySHA256: profile.policySHA256,
              semanticPolicy: policy,
              cancellationCheck: cancellationToken.check
            )
          )
        case .manifestRequest(let branchCapability, let policy, let originPin):
          semanticDocument = .manifestRequest(
            try StrictMainManifestRequestDecoder.decode(
              body,
              branchCapability: branchCapability,
              transportPolicySHA256: profile.policySHA256,
              originPin: originPin,
              semanticPolicy: policy,
              cancellationCheck: cancellationToken.check
            )
          )
        case .manifestBodyRequest(
          let branchCapability,
          let policy,
          let originPin,
          let expectedRequestPathSHA256,
          let expectedCompressedSize
        ):
          semanticDocument = .manifestBodyRequest(
            try StrictMainManifestRequestDecoder.decodeBodyRequest(
              body,
              branchCapability: branchCapability,
              transportPolicySHA256: profile.policySHA256,
              originPin: originPin,
              expectedRequestPathSHA256: expectedRequestPathSHA256,
              expectedCompressedSize: expectedCompressedSize,
              semanticPolicy: policy,
              cancellationCheck: cancellationToken.check
            )
          )
        case .chunkOrigin(let branchCapability, let policy):
          semanticDocument = .chunkOrigin(
            try StrictMainBuildChunkOriginDecoder.decode(
              body,
              branchCapability: branchCapability,
              transportPolicySHA256: profile.policySHA256,
              semanticPolicy: policy,
              cancellationCheck: cancellationToken.check
            )
          )
        case .chunkPayloadRequest(
          let branchCapability,
          let policy,
          let manifestOriginPin,
          let expectedManifestRequestPathSHA256,
          let expectedManifestCompressedSize,
          let chunkOriginPin
        ):
          semanticDocument = .chunkPayloadRequest(
            try StrictMainChunkPayloadRequestDecoder.decode(
              body,
              branchCapability: branchCapability,
              transportPolicySHA256: profile.policySHA256,
              manifestOriginPin: manifestOriginPin,
              expectedManifestRequestPathSHA256: expectedManifestRequestPathSHA256,
              expectedManifestCompressedSize: expectedManifestCompressedSize,
              chunkOriginPin: chunkOriginPin,
              semanticPolicy: policy,
              cancellationCheck: cancellationToken.check
            )
          )
        case nil:
          semanticDocument = nil
        }
        document = .rootData(shape, semanticDocument)
      case .metadataOnly:
        throw ManifestSamplingError.transportFailure
      case .binaryBody(_, let retainBody, _):
        let retainedBody = retainBody ? body.withUnsafeBytes { Data($0) } : nil
        document = .binary(
          ManifestBinaryBodyEvidence(
            frameKind: ManifestBodyDiscoveryProfile.classifyFrame(body),
            contentEncodingKind: binaryContentEncodingKind ?? "invalid"
          ),
          retainedBody
        )
      }
      let observedAt = now().timeIntervalSince1970
      guard observedAt.isFinite,
        observedAt >= 0, observedAt <= 253_402_300_799
      else {
        throw ManifestSamplingError.transportFailure
      }
      let receipt = BranchTransportResult(
        profileID: profile.profileID,
        requestIdentitySHA256: profile.requestIdentitySHA256,
        policySHA256: profile.policySHA256,
        statusCode: 200,
        observedAtUnixSeconds: Int64(observedAt),
        bodySHA256: bodySHA256,
        byteSize: UInt64(body.count),
        document: document
      )
      body.removeAll(keepingCapacity: false)
      finish(.success(receipt))
    } catch is CancellationError {
      body.removeAll(keepingCapacity: false)
      finish(.failure(CancellationError()))
    } catch let error as ManifestSamplingError {
      body.removeAll(keepingCapacity: false)
      finish(.failure(error))
    } catch {
      body.removeAll(keepingCapacity: false)
      finish(.failure(ManifestSamplingError.malformedJSON))
    }
  }

  private func handle(
    _ challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (
        URLSession.AuthChallengeDisposition, URLCredential?
      ) -> Void
  ) {
    if BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
      authenticationMethod: challenge.protectionSpace.authenticationMethod,
      host: challenge.protectionSpace.host,
      protocolName: challenge.protectionSpace.protocol,
      port: challenge.protectionSpace.port,
      previousFailureCount: challenge.previousFailureCount,
      expectedHost: profile.url.host ?? ""
    ) {
      completionHandler(.performDefaultHandling, nil)
    } else {
      recordTerminalError(ManifestSamplingError.authenticationRejected)
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }

  private func recordTerminalError(_ error: any Error) {
    lock.lock()
    if terminalError == nil { terminalError = error }
    lock.unlock()
  }

  private func finish(_ result: Result<BranchTransportResult, any Error>) {
    if case .failure = result { body.removeAll(keepingCapacity: false) }
    lock.lock()
    guard completion == nil else {
      lock.unlock()
      return
    }
    completion = result
    let continuation = continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }

  private static func isIdentityEncoding(_ value: String?) -> Bool {
    guard let value else { return true }
    return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "identity"
  }

  private static func isAllowedOctetStream(
    _ value: String?,
    allowsBoundedParameters: Bool
  ) -> Bool {
    guard let value, value.utf8.count <= 512 else { return false }
    let parts = value.split(separator: ";", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard parts.first?.lowercased() == "application/octet-stream" else {
      return false
    }
    guard parts.count > 1 else { return true }
    guard allowsBoundedParameters, parts.count <= 5 else { return false }
    return parts.dropFirst().allSatisfy { parameter in
      !parameter.isEmpty && parameter.utf8.count <= 128
        && parameter.utf8.allSatisfy { (32...126).contains($0) }
    }
  }

  private static func makeMetadata(
    _ response: HTTPURLResponse,
    maximumDeclaredContentLength: UInt64,
    observedAtUnixSeconds: Int64
  ) -> ManifestResponseMetadata {
    let contentTypeKind = classifyContentType(
      response.value(forHTTPHeaderField: "Content-Type")
    )
    let contentEncodingKind = classifyContentEncoding(
      response.value(forHTTPHeaderField: "Content-Encoding")
    )
    let rawLength = response.value(forHTTPHeaderField: "Content-Length")
    let length: UInt64?
    let lengthState: String
    if let rawLength {
      let bytes = rawLength.utf8
      if !bytes.isEmpty,
        bytes.count == 1 || bytes.first != 48,
        bytes.allSatisfy({ (48...57).contains($0) }),
        let parsed = UInt64(rawLength)
      {
        length = parsed
        lengthState =
          parsed <= maximumDeclaredContentLength ? "withinLimit" : "overLimit"
      } else {
        length = nil
        lengthState = "invalid"
      }
    } else {
      length = nil
      lengthState = "absent"
    }
    return ManifestResponseMetadata(
      statusCode: 200,
      contentTypeKind: contentTypeKind,
      contentEncodingKind: contentEncodingKind,
      contentLengthState: lengthState,
      declaredContentLength: length,
      observedAtUnixSeconds: observedAtUnixSeconds
    )
  }

  private static func classifyContentType(_ value: String?) -> String {
    guard let value else { return "absent" }
    let mediaType =
      value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    switch mediaType {
    case "application/octet-stream": return "applicationOctetStream"
    case "binary/octet-stream": return "binaryOctetStream"
    case "application/zstd": return "applicationZstd"
    case "application/x-zstd": return "applicationXZstd"
    case "application/x-protobuf": return "applicationXProtobuf"
    case "": return "invalid"
    default: return "otherSHA256:" + BranchDiscoveryProfile.sha256(mediaType)
    }
  }

  private static func classifyContentEncoding(_ value: String?) -> String {
    guard let value else { return "absent" }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "identity": return "identity"
    case "": return "invalid"
    default: return "otherSHA256:" + BranchDiscoveryProfile.sha256(normalized)
    }
  }

  private static func metadataError(_ failures: UInt8) -> ManifestSamplingError {
    switch failures {
    case 0b001: .contentTypeRejected
    case 0b010: .contentEncodingRejected
    case 0b100: .contentLengthRejected
    case 0b011: .contentTypeAndEncodingRejected
    case 0b101: .contentTypeAndLengthRejected
    case 0b110: .contentEncodingAndLengthRejected
    default: .contentTypeEncodingAndLengthRejected
    }
  }

  private static func isAllowedJSONContentType(_ value: String?) -> Bool {
    guard let value else { return false }
    let parts = value.split(separator: ";", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    guard parts.first == "application/json" else { return false }
    return parts.count == 1 || (parts.count == 2 && parts[1] == "charset=utf-8")
  }
}

extension BranchDiscoveryProfile: ManifestSamplingRedactedValue {}
extension BranchDiscoveryDelegate: ManifestSamplingRedactedValue {}

private final class SamplingCancellationToken: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  func check() throws {
    lock.lock()
    let isCancelled = cancelled
    lock.unlock()
    if isCancelled { throw CancellationError() }
  }
}
