import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct ManifestChunkPayloadDiscoveryTests {
  @Test
  func planIsCanonicalAndClosedGateStartsNoRequest() async throws {
    ChunkPayloadSamplingURLProtocol.reset()
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestChunkPayloadPlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-one-chunk-payload-cn"],
      environment: [:],
      client: client,
      structuralInspector: SyntheticChunkPayloadInspector(),
      chunkPayloadVerifier: SyntheticChunkPayloadVerifier()
    )
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(
      plan.policySHA256
        == "36e23a25908d06ac4ad69dd4ea80b2cdcf6866924a35e93a22b5d8907845f6d0")
    #expect(plan.maximumPayloadBytes == 16 * 1_024 * 1_024)
    #expect(plan.stopPolicy == "oneChunkOnlyNoDecompressionInstallOrAdditionalPayload")
    #expect(ChunkPayloadSamplingURLProtocol.requests.isEmpty)

    await #expect(throws: ManifestSamplingError.executionGateClosed) {
      try await client.sampleCNManifestChunkPayload(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestStructureNetworkGate,
        inspector: SyntheticChunkPayloadInspector(),
        verifier: SyntheticChunkPayloadVerifier()
      )
    }
    #expect(ChunkPayloadSamplingURLProtocol.requests.isEmpty)
  }

  @Test
  func fetchesExactlyOneCandidateAndReturnsOnlyVerifiedCacheEvidence() async throws {
    ChunkPayloadSamplingURLProtocol.reset()
    ChunkPayloadSamplingURLProtocol.handler = response(for:)
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestChunkPayloadPlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["sample-one-chunk-payload-cn", "--ack", plan.policySHA256],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey:
          BranchDiscoveryClient.requiredChunkPayloadNetworkGate
      ],
      client: client,
      structuralInspector: SyntheticChunkPayloadInspector(),
      chunkPayloadVerifier: SyntheticChunkPayloadVerifier()
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(
      ChunkPayloadSamplingURLProtocol.hosts == [
        "hyp-api.mihoyo.com", "api-takumi.mihoyo.com", "cdn.example.com",
        "chunks.example.com",
      ])
    #expect(text.contains(#""chunkByteSize":5"#))
    #expect(text.contains(#""field7CompressedMD5Verified":true"#))
    #expect(text.contains(#""uncompressedMD5Verified":true"#))
    #expect(text.contains(#""cacheDisposition":"stored""#))
    #expect(text.contains(chunkPayloadSHA256))
    #expect(text.contains(#""requestCount":4"#))
    for forbidden in chunkPayloadCanaries + [chunkObjectID, "/chunk/path/"] {
      #expect(!text.contains(forbidden))
    }
  }

  @Test
  func verifierFailureStopsAfterTheSinglePayloadResponse() async throws {
    ChunkPayloadSamplingURLProtocol.reset()
    ChunkPayloadSamplingURLProtocol.handler = response(for:)
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestChunkPayloadPlan()
    await #expect(throws: ManifestSamplingError.chunkIntegrityRejected) {
      try await client.sampleCNManifestChunkPayload(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredChunkPayloadNetworkGate,
        inspector: SyntheticChunkPayloadInspector(),
        verifier: RejectingChunkPayloadVerifier()
      )
    }
    #expect(ChunkPayloadSamplingURLProtocol.requests.count == 4)
  }

  private func makeClient() throws -> BranchDiscoveryClient {
    let branchShape = try StrictJSONSchemaScanner.scan(
      chunkPayloadBranchBody,
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
      chunkPayloadBuildBody,
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
      configuration: samplingConfiguration(ChunkPayloadSamplingURLProtocol.self),
      now: { Date(timeIntervalSince1970: 103) },
      mainBuildSemanticPolicy: branchPolicy,
      mainBuildResponseSemanticPolicy: buildPolicy,
      manifestMetadataOriginPin: ManifestOriginPin(
        safeOrigin: "https://cdn.example.com",
        pathComponentCount: 2,
        pathSHA256: sha256(Data("/manifest/path".utf8))
      ),
      manifestBodyExpectedRequestPathSHA256: sha256(
        Data("/manifest/path/manifest-id".utf8)
      ),
      manifestBodyExpectedCompressedSize: UInt64(chunkManifestFixture.count),
      manifestStructureExpectedBodySHA256: sha256(chunkManifestFixture),
      chunkPayloadOriginPin: ManifestOriginPin(
        safeOrigin: "https://chunks.example.com",
        pathComponentCount: 2,
        pathSHA256: sha256(Data("/chunk/path".utf8))
      )
    )
  }

  private func response(for request: URLRequest) throws -> SamplingMockResult {
    switch request.url?.host {
    case "hyp-api.mihoyo.com":
      return .response(mockHTTPResponse(request: request), chunkPayloadBranchBody, chunkSize: 17)
    case "api-takumi.mihoyo.com":
      return .response(mockHTTPResponse(request: request), chunkPayloadBuildBody, chunkSize: 19)
    case "cdn.example.com":
      return .response(
        binaryResponse(request, size: chunkManifestFixture.count), chunkManifestFixture,
        chunkSize: 3)
    case "chunks.example.com":
      #expect(request.url?.path == "/chunk/path/" + chunkObjectID)
      return .response(
        binaryResponse(request, size: chunkPayloadFixture.count), chunkPayloadFixture, chunkSize: 2)
    default:
      return .failure(URLError(.unsupportedURL))
    }
  }
}

private let chunkObjectID = "chunk-object-canary"
private let chunkPayloadFixture = Data("hello".utf8)
private let chunkPayloadSHA256 =
  "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
private let chunkManifestFixture = Data([0x28, 0xB5, 0x2F, 0xFD]) + Data("manifest".utf8)
private let chunkPayloadCanaries = [
  "branch-canary", "package-canary", "password-canary", "chunk-password-canary",
]

private let chunkPayloadBranchBody = Data(
  #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
    .utf8
)

private let chunkPayloadBuildBody = Data(
  """
  {"retcode":0,"message":"ok","data":{"tag":"tag-canary","build_id":"build-id-canary","manifests":[{"category_id":"game","category_name":"category-name-canary","matching_field":"game","manifest":{"id":"manifest-id","checksum":"checksum-canary","compressed_size":"\(chunkManifestFixture.count)","uncompressed_size":"456"},"manifest_download":{"password":"download-password-canary","url_prefix":"https://cdn.example.com/manifest/path"},"chunk_download":{"password":"chunk-password-canary","url_prefix":"https://chunks.example.com/chunk/path"}}]}}
  """.utf8
)

private struct SyntheticChunkPayloadInspector: ManifestBodyStructurallyInspecting {
  func inspect(
    _ input: ManifestLiveBodyInspectionInput
  ) throws -> ManifestChunkStructuralEvidence {
    guard input.data == chunkManifestFixture,
      input.manifestID == "manifest-id"
    else {
      throw ManifestSamplingError.manifestStructuralRejected
    }
    return ManifestChunkStructuralEvidence(
      decompressedBodySHA256: String(repeating: "d", count: 64),
      decompressedByteSize: 100,
      wirePolicyVersion: 1,
      fileCount: 1,
      directoryCount: 0,
      chunkReferenceCount: 1,
      uniqueChunkObjectCount: 1,
      targetInstalledBytes: 8,
      referencedChunkCompressedBytes: 5,
      uniqueChunkObjectBytes: 5,
      wireNodeCount: 3,
      wireStringBytes: 80,
      payloadCandidate: ManifestChunkPayloadCandidate(
        objectID: chunkObjectID,
        compressedBytes: 5,
        uncompressedBytes: 8,
        uncompressedMD5: String(repeating: "a", count: 32),
        compressedXXHash: 0x26C7_827D_889F_6DA3,
        wireField7OpaqueHash: "5d41402abc4b2a76b9719d911017c592"
      )
    )
  }
}

private struct SyntheticChunkPayloadVerifier: ManifestChunkPayloadVerifying {
  func verifyAndStore(
    _ input: ManifestChunkPayloadVerificationInput
  ) throws -> ManifestChunkPayloadStoredEvidence {
    guard input.data == chunkPayloadFixture,
      input.candidate.objectID == chunkObjectID
    else {
      throw ManifestSamplingError.chunkIntegrityRejected
    }
    return ManifestChunkPayloadStoredEvidence(
      byteSize: 5,
      sha256: chunkPayloadSHA256,
      compressedMD5: input.candidate.wireField7OpaqueHash,
      uncompressedByteSize: input.candidate.uncompressedBytes,
      uncompressedMD5: input.candidate.uncompressedMD5,
      cacheDisposition: "stored",
      cacheRelativePath: "objects/sha256/2c/" + chunkPayloadSHA256
    )
  }
}

private struct RejectingChunkPayloadVerifier: ManifestChunkPayloadVerifying {
  func verifyAndStore(
    _ input: ManifestChunkPayloadVerificationInput
  ) throws -> ManifestChunkPayloadStoredEvidence {
    _ = input
    throw ManifestSamplingError.chunkIntegrityRejected
  }
}

private func binaryResponse(_ request: URLRequest, size: Int) -> HTTPURLResponse {
  mockHTTPResponse(
    request: request,
    headers: [
      "Content-Type": "application/octet-stream",
      "Content-Length": String(size),
    ]
  )
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class ChunkPayloadSamplingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> SamplingMockResult)?
  nonisolated(unsafe) private static var observedRequests: [URLRequest] = []

  static func reset() {
    lock.lock()
    handler = nil
    observedRequests = []
    lock.unlock()
  }

  static var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return observedRequests
  }

  static var hosts: [String] { requests.map { $0.url?.host ?? "missing" } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.observedRequests.append(request)
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
