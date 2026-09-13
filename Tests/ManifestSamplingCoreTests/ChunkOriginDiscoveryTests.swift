import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct ChunkOriginDiscoveryTests {
  @Test
  func planIsCanonicalSafeAndStartsNoNetwork() async throws {
    ChunkOriginSamplingURLProtocol.reset()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-chunk-origin-cn"],
      environment: [:],
      client: try makeClient(chunkPrefix: "https://chunks.example.com/a/b")
    )
    let plan = BranchDiscoveryClient.chunkOriginPlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(
      plan.policySHA256
        == "56b6b2f110d9cdec451fe4c885c5f185716790f05ca577b65ab858b8d58273ca")
    #expect(plan.semanticScopePolicy == "tagUniqueGameAndChunkURLPrefixOnly")
    #expect(plan.stopPolicy == "chunkOriginReceiptOnlyNoManifestOrPayloadRequest")
    #expect(ChunkOriginSamplingURLProtocol.hosts.isEmpty)
    let text = String(decoding: output, as: UTF8.self)
    for canary in chunkOriginCanaries { #expect(!text.contains(canary)) }
  }

  @Test
  func decoderReturnsRedactedValidatedChunkPrefix() throws {
    let reference = try makeChunkOriginReference(
      chunkPrefix: "https://chunks.example.com/a/b")
    let origin = try ChunkOriginDiscoveryProfile.inspect(capability: reference)

    #expect(origin.safeOrigin == "https://chunks.example.com")
    #expect(origin.pathComponentCount == 2)
    #expect(origin.pathSHA256 == sha256(Data("/a/b".utf8)))
    #expect(reference.description == "<redacted>")
    #expect(!(ValidatedMainBuildChunkOriginReference.self is any Encodable.Type))
    var dumped = ""
    dump(reference, to: &dumped)
    #expect(dumped.contains("redacted"))
    #expect(!dumped.contains("chunks.example.com"))
  }

  @Test
  func gatedTransactionReturnsOnlyChunkOriginAndStopsAfterBuild() async throws {
    ChunkOriginSamplingURLProtocol.reset()
    let client = try makeClient(chunkPrefix: "https://chunks.example.com/secret/path")
    ChunkOriginSamplingURLProtocol.handler = { request in
      switch request.url?.host {
      case "hyp-api.mihoyo.com":
        return .response(mockHTTPResponse(request: request), chunkOriginBranchBody(), chunkSize: 17)
      case "api-takumi.mihoyo.com":
        return .response(
          mockHTTPResponse(request: request),
          chunkOriginBuildBody(chunkPrefix: "https://chunks.example.com/secret/path"),
          chunkSize: 19
        )
      default:
        return .failure(URLError(.unsupportedURL))
      }
    }
    let plan = BranchDiscoveryClient.chunkOriginPlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["sample-chunk-origin-cn", "--ack", plan.policySHA256],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey:
          BranchDiscoveryClient.requiredChunkOriginNetworkGate
      ],
      client: client
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(
      ChunkOriginSamplingURLProtocol.hosts == [
        "hyp-api.mihoyo.com", "api-takumi.mihoyo.com",
      ])
    #expect(text.contains(#""chunkSafeOrigin":"https://chunks.example.com""#))
    #expect(text.contains(#""chunkPathComponentCount":2"#))
    #expect(text.contains(sha256(Data("/secret/path".utf8))))
    #expect(text.contains(#""requestCount":2"#))
    for canary in chunkOriginCanaries + ["/secret/path"] {
      #expect(!text.contains(canary))
    }
  }

  @Test
  func closedGateAndInvalidPrefixFailBeforePayload() async throws {
    ChunkOriginSamplingURLProtocol.reset()
    let plan = BranchDiscoveryClient.chunkOriginPlan()
    let client = try makeClient(chunkPrefix: "https://chunks.example.com/a/b")
    await #expect(throws: ManifestSamplingError.executionGateClosed) {
      try await client.sampleCNChunkOrigin(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestOriginNetworkGate
      )
    }
    #expect(ChunkOriginSamplingURLProtocol.hosts.isEmpty)

    #expect(throws: ManifestSamplingError.originRejected) {
      try ChunkOriginDiscoveryProfile.inspect(
        capability: makeChunkOriginReference(chunkPrefix: "http://chunks.example.com/a/b")
      )
    }
  }

  private func makeClient(chunkPrefix: String) throws -> BranchDiscoveryClient {
    let branchShape = try StrictJSONSchemaScanner.scan(
      chunkOriginBranchBody(),
      reportLimits: .standard
    )
    let branchReport = try #require(branchShape.safeReport)
    let branchPolicy = BranchSemanticPolicy(
      policyVersion: 1,
      expectedRequestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      expectedShapePolicyVersion: branchShape.policyVersion,
      expectedShapeSHA256: branchShape.sha256,
      expectedGameBranchEntryCount: branchShape.gameBranchEntryCount,
      expectedReportPolicyVersion: branchReport.policyVersion,
      expectedReportSHA256: branchReport.sha256,
      expectedCanonicalReportByteSize: branchReport.canonicalByteSize,
      expectedGameID: "1Z8W5NHUQb"
    )
    let buildShape = try StrictJSONSchemaScanner.scanRootData(
      chunkOriginBuildBody(chunkPrefix: chunkPrefix),
      reportLimits: .standard
    )
    let buildReport = try #require(buildShape.safeReport)
    let buildPolicy = MainBuildSemanticPolicy(
      policyVersion: 1,
      expectedShapePolicyVersion: buildShape.policyVersion,
      expectedShapeSHA256: buildShape.sha256,
      expectedReportPolicyVersion: buildReport.policyVersion,
      expectedReportSHA256: buildReport.sha256,
      expectedCanonicalReportByteSize: buildReport.canonicalByteSize,
      expectedMatchingField: "game"
    )
    return BranchDiscoveryClient(
      configuration: samplingConfiguration(ChunkOriginSamplingURLProtocol.self),
      now: { Date(timeIntervalSince1970: 101) },
      mainBuildSemanticPolicy: branchPolicy,
      mainBuildResponseSemanticPolicy: buildPolicy
    )
  }

  private func makeChunkOriginReference(
    chunkPrefix: String
  ) throws -> ValidatedMainBuildChunkOriginReference {
    let branchShape = try StrictJSONSchemaScanner.scan(
      chunkOriginBranchBody(),
      reportLimits: .standard
    )
    let branchReport = try #require(branchShape.safeReport)
    let branchPolicy = BranchSemanticPolicy(
      policyVersion: 1,
      expectedRequestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      expectedShapePolicyVersion: branchShape.policyVersion,
      expectedShapeSHA256: branchShape.sha256,
      expectedGameBranchEntryCount: branchShape.gameBranchEntryCount,
      expectedReportPolicyVersion: branchReport.policyVersion,
      expectedReportSHA256: branchReport.sha256,
      expectedCanonicalReportByteSize: branchReport.canonicalByteSize,
      expectedGameID: "1Z8W5NHUQb"
    )
    let branch = try StrictCNBranchSemanticDecoder.decode(
      chunkOriginBranchBody(),
      requestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      transportPolicySHA256: String(repeating: "a", count: 64),
      semanticPolicy: branchPolicy
    )
    let buildBody = chunkOriginBuildBody(chunkPrefix: chunkPrefix)
    let buildShape = try StrictJSONSchemaScanner.scanRootData(
      buildBody,
      reportLimits: .standard
    )
    let buildReport = try #require(buildShape.safeReport)
    let buildPolicy = MainBuildSemanticPolicy(
      policyVersion: 1,
      expectedShapePolicyVersion: buildShape.policyVersion,
      expectedShapeSHA256: buildShape.sha256,
      expectedReportPolicyVersion: buildReport.policyVersion,
      expectedReportSHA256: buildReport.sha256,
      expectedCanonicalReportByteSize: buildReport.canonicalByteSize,
      expectedMatchingField: "game"
    )
    return try StrictMainBuildChunkOriginDecoder.decode(
      buildBody,
      branchCapability: branch,
      transportPolicySHA256: String(repeating: "b", count: 64),
      semanticPolicy: buildPolicy
    )
  }
}

private let chunkOriginCanaries = [
  "branch-canary", "package-canary", "password-canary", "chunk-password-canary",
]

private func chunkOriginBranchBody() -> Data {
  Data(
    #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
      .utf8
  )
}

private func chunkOriginBuildBody(chunkPrefix: String) -> Data {
  Data(
    """
    {"retcode":0,"message":"ok","data":{"tag":"tag-canary","build_id":"build-id-canary","manifests":[{"category_id":"game","category_name":"category-name-canary","matching_field":"game","manifest":{"id":"manifest-id-canary","checksum":"checksum-canary","compressed_size":"123","uncompressed_size":"456"},"manifest_download":{"password":"download-password-canary","url_prefix":"https://manifest.example.com/a/b"},"chunk_download":{"password":"chunk-password-canary","url_prefix":"\(chunkPrefix)"}}]}}
    """.utf8
  )
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class ChunkOriginSamplingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> SamplingMockResult)?
  nonisolated(unsafe) private static var observedHosts: [String] = []

  static func reset() {
    lock.lock()
    handler = nil
    observedHosts = []
    lock.unlock()
  }

  static var hosts: [String] {
    lock.lock()
    defer { lock.unlock() }
    return observedHosts
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.observedHosts.append(request.url?.host ?? "missing")
    let handler = Self.handler
    Self.lock.unlock()
    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.dataNotAllowed))
      return
    }
    do {
      switch try handler(request) {
      case .response(let response, let data, let chunkSize):
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let chunkSize, chunkSize > 0 {
          for offset in stride(from: 0, to: data.count, by: chunkSize) {
            client?.urlProtocol(
              self,
              didLoad: data.subdata(in: offset..<min(offset + chunkSize, data.count))
            )
          }
        } else {
          client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
      case .redirect(let response, let request):
        client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
        client?.urlProtocolDidFinishLoading(self)
      case .failure(let error):
        client?.urlProtocol(self, didFailWithError: error)
      case .block:
        break
      }
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
