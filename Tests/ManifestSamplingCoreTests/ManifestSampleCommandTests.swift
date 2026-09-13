import Foundation
import Testing

@testable import ManifestSamplingCore

@Suite(.serialized)
struct ManifestSampleCommandTests {
  @Test
  func planIsCanonicalSafeAndStartsNoNetwork() async throws {
    SamplingTripwireURLProtocol.reset()
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingTripwireURLProtocol.self))
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan"],
      environment: [:],
      client: client
    )
    #expect(SamplingTripwireURLProtocol.startCount == 0)
    let expected = try ManifestSamplingCanonicalJSON.encode(BranchDiscoveryClient.plan())
    #expect(output == expected)
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains(#""safeOrigin":"https://hyp-api.mihoyo.com""#))
    #expect(text.contains(#""path":"/hyp/hyp-connect/api/getGameBranches""#))
    for forbidden in ["game_ids", "launcher_id", "1Z8W5NHUQb", "jGHBHlcOq1"] {
      #expect(!text.contains(forbidden))
    }
    #expect(text.contains(BranchDiscoveryClient.plan().policySHA256))
    #expect(
      BranchDiscoveryClient.plan().requestIdentitySHA256
        == "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d")
    #expect(
      BranchDiscoveryClient.plan().policySHA256
        == "4b78e4fb1fb711010a90799c145bc08d607f4ad53f4cb70d32438f5ee062cec3")
    #expect(
      BranchDiscoveryPolicyHasher.hash(BranchDiscoveryClient.plan())
        == BranchDiscoveryClient.plan().policySHA256)
    #expect(
      BranchDiscoveryPolicyHasher.hash(changingMaximumBytes(BranchDiscoveryClient.plan()))
        != BranchDiscoveryClient.plan().policySHA256)
  }

  @Test
  func everyClosedGateFailsBeforeSessionCreation() async throws {
    SamplingTripwireURLProtocol.reset()
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingTripwireURLProtocol.self))
    let plan = BranchDiscoveryClient.plan()
    let cases: [([String], [String: String], ManifestSamplingError)] = [
      (["sample-branches-cn"], [:], .invalidCommand),
      (["sample-branches-cn", "--ack", plan.policySHA256], [:], .executionGateClosed),
      (
        ["sample-branches-cn", "--ack", "wrong"],
        [
          BranchDiscoveryClient.networkGateEnvironmentKey: BranchDiscoveryClient.requiredNetworkGate
        ], .executionGateClosed
      ),
      (
        ["sample-branches-cn", "--ack", plan.policySHA256, "https://example.invalid"],
        [
          BranchDiscoveryClient.networkGateEnvironmentKey: BranchDiscoveryClient.requiredNetworkGate
        ], .invalidCommand
      ),
    ]
    for item in cases {
      await #expect(throws: item.2) {
        try await ManifestSampleCommandRunner.execute(
          arguments: item.0,
          environment: item.1,
          client: client
        )
      }
    }
    #expect(SamplingTripwireURLProtocol.startCount == 0)
  }

  @Test
  func openGatesEmitOnlySafeReceipt() async throws {
    SamplingMockURLProtocol.reset()
    SamplingMockURLProtocol.handler = { request in
      .response(mockHTTPResponse(request: request), validBranchBody(), chunkSize: 5)
    }
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingMockURLProtocol.self),
      now: { Date(timeIntervalSince1970: 7) }
    )
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: [
        "sample-branches-cn", "--ack", BranchDiscoveryClient.plan().policySHA256,
      ],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey: BranchDiscoveryClient.requiredNetworkGate
      ],
      client: client
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains(#""statusCode":200"#))
    #expect(text.contains(#""observedAtUnixSeconds":7"#))
    for forbidden in [
      "mihoyo", "game_ids", "launcher_id", "canary-tag", "canary-branch",
      "canary-package", "canary-password",
    ] {
      #expect(!text.contains(forbidden))
    }
  }

  private func changingMaximumBytes(_ plan: BranchDiscoveryPlan) -> BranchDiscoveryPlan {
    BranchDiscoveryPlan(
      schemaVersion: plan.schemaVersion,
      profileID: plan.profileID,
      requestIdentitySHA256: plan.requestIdentitySHA256,
      policySHA256: plan.policySHA256,
      method: plan.method,
      safeOrigin: plan.safeOrigin,
      path: plan.path,
      maximumResponseBytes: plan.maximumResponseBytes + 1,
      tlsPolicy: plan.tlsPolicy,
      authenticationPolicy: plan.authenticationPolicy,
      finalURLPolicy: plan.finalURLPolicy,
      statusPolicy: plan.statusPolicy,
      contentTypePolicy: plan.contentTypePolicy,
      contentEncodingPolicy: plan.contentEncodingPolicy,
      retryPolicy: plan.retryPolicy,
      cachePolicy: plan.cachePolicy,
      cookiePolicy: plan.cookiePolicy,
      redirectPolicy: plan.redirectPolicy,
      persistencePolicy: plan.persistencePolicy,
      requestTimeoutSeconds: plan.requestTimeoutSeconds,
      resourceTimeoutSeconds: plan.resourceTimeoutSeconds
    )
  }
}
