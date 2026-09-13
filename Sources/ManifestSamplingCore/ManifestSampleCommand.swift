import Foundation

package enum ManifestSampleCommandRunner {
  package static func execute(
    arguments: [String],
    environment: [String: String],
    client: BranchDiscoveryClient = BranchDiscoveryClient(),
    structuralInspector: (any ManifestBodyStructurallyInspecting)? = nil,
    chunkPayloadVerifier: (any ManifestChunkPayloadVerifying)? = nil
  ) async throws -> Data {
    if arguments == ["plan"] {
      return try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.plan())
    }
    if arguments == ["plan-branches-shape-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.shapeReportPlan())
    }
    if arguments == ["plan-build-main-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.mainBuildShapePlan())
    }
    if arguments == ["plan-manifest-origin-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.manifestOriginPlan())
    }
    if arguments == ["plan-chunk-origin-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.chunkOriginPlan())
    }
    if arguments == ["plan-manifest-metadata-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(
        BranchDiscoveryClient.manifestMetadataPlan()
      )
    }
    if arguments == ["plan-manifest-body-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.manifestBodyPlan())
    }
    if arguments == ["plan-manifest-structure-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(
        BranchDiscoveryClient.manifestStructurePlan()
      )
    }
    if arguments == ["plan-one-chunk-payload-cn"] {
      return try ManifestSamplingCanonicalJSON.encode(
        BranchDiscoveryClient.manifestChunkPayloadPlan()
      )
    }
    guard arguments.count == 3,
      arguments[1] == "--ack"
    else {
      throw ManifestSamplingError.invalidCommand
    }
    switch arguments[0] {
    case "sample-branches-cn":
      let receipt = try await client.sampleCN(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-branches-shape-cn":
      let receipt = try await client.sampleCNShapeReport(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-build-main-cn":
      let receipt = try await client.sampleCNMainBuildShape(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-manifest-origin-cn":
      let receipt = try await client.sampleCNManifestOrigin(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-chunk-origin-cn":
      let receipt = try await client.sampleCNChunkOrigin(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-manifest-metadata-cn":
      let receipt = try await client.sampleCNManifestMetadata(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-manifest-body-cn":
      let receipt = try await client.sampleCNManifestBody(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey]
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-manifest-structure-cn":
      guard let structuralInspector else {
        throw ManifestSamplingError.invalidCommand
      }
      let receipt = try await client.sampleCNManifestStructure(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey],
        inspector: structuralInspector
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    case "sample-one-chunk-payload-cn":
      guard let structuralInspector, let chunkPayloadVerifier else {
        throw ManifestSamplingError.invalidCommand
      }
      let receipt = try await client.sampleCNManifestChunkPayload(
        acknowledgedPlanSHA256: arguments[2],
        networkGate: environment[BranchDiscoveryClient.networkGateEnvironmentKey],
        inspector: structuralInspector,
        verifier: chunkPayloadVerifier
      )
      return try ManifestSamplingCanonicalJSON.encode(receipt)
    default:
      throw ManifestSamplingError.invalidCommand
    }
  }
}
