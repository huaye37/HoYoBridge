import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct ManifestBodyDiscoveryTests {
  @Test
  func planIsCanonicalPinnedAndStartsNoNetwork() async throws {
    BodySamplingURLProtocol.reset()
    let client = try makeClient()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-manifest-body-cn"],
      environment: [:],
      client: client
    )
    let plan = BranchDiscoveryClient.manifestBodyPlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(
      plan.policySHA256
        == "e253f675047143eb73dd4a09de22fae280a451872b3e5ed875f9ef4881677dc3")
    #expect(plan.expectedCompressedSize == 8_521_303)
    #expect(
      plan.manifestRequestPathSHA256
        == "ce154736f9d4cd8d3355c17101f99526ccd3a67772cf04defdd362afbf6cfea8")
    #expect(plan.stopPolicy == "bodyReceiptOnlyNoDecompressNoPayload")
    #expect(!(ManifestBodyPlan.self is any Decodable.Type))
    #expect(BodySamplingURLProtocol.requests.isEmpty)
  }

  @Test
  func bodyRequestReferenceRequiresExactBuildSizeAndPath() throws {
    let reference = try makeBodyRequestReference()
    #expect(reference.expectedCompressedSize == UInt64(bodyFixture.count))
    #expect(reference.requestPathSHA256 == bodyRequestPathSHA256)
    #expect(!(ValidatedMainManifestBodyRequestReference.self is any Encodable.Type))
    #expect(!(ValidatedMainManifestBodyRequestReference.self is any Decodable.Type))
    var dumped = ""
    dump(reference, to: &dumped)
    #expect(dumped.contains("redacted"))
    for forbidden in bodyCanaries { #expect(!dumped.contains(forbidden)) }

    #expect(throws: ManifestSamplingError.requestIdentityMismatch) {
      try makeBodyRequestReference(expectedRequestPathSHA256: String(repeating: "a", count: 64))
    }
    #expect(throws: ManifestSamplingError.buildManifestReferenceRejected) {
      try makeBodyRequestReference(expectedCompressedSize: UInt64(bodyFixture.count + 1))
    }
  }

  @Test
  func gatedTransactionStreamsExactBodyAndReturnsOnlyDigestEvidence() async throws {
    BodySamplingURLProtocol.reset()
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestBodyPlan()
    let receipt = try await client.sampleCNManifestBody(
      acknowledgedPlanSHA256: plan.policySHA256,
      networkGate: BranchDiscoveryClient.requiredManifestBodyNetworkGate
    )
    #expect(BodySamplingURLProtocol.requests.count == 3)
    #expect(BodySamplingURLProtocol.requests.last?.url?.host == "cdn.example.com")
    #expect(
      BodySamplingURLProtocol.requests.last?.value(forHTTPHeaderField: "Accept")
        == "application/octet-stream")
    #expect(receipt.bodySHA256 == sha256(bodyFixture))
    #expect(receipt.byteSize == UInt64(bodyFixture.count))
    #expect(receipt.declaredContentLength == UInt64(bodyFixture.count))
    #expect(receipt.frameKind == "zstdStandardFrame")
    #expect(receipt.contentTypeKind == "applicationOctetStream")
    #expect(receipt.contentEncodingKind == "absent")
    #expect(receipt.requestCount == 3)
    #expect(!(ManifestBodyReceipt.self is any Decodable.Type))
    let output = try ManifestSamplingCanonicalJSON.encode(receipt)
    let text = String(decoding: output, as: UTF8.self)
    for forbidden in bodyCanaries { #expect(!text.contains(forbidden)) }
  }

  @Test
  func rejectsWrongHeadersAndShortOrOversizedBodies() async throws {
    let cases:
      [(
        headers: [String: String],
        body: Data,
        expected: ManifestSamplingError
      )] = [
        (
          ["Content-Type": "text/plain", "Content-Length": String(bodyFixture.count)],
          bodyFixture,
          .contentTypeRejected
        ),
        (
          [
            "Content-Type": "application/octet-stream; charset=utf-8",
            "Content-Length": String(bodyFixture.count),
          ],
          bodyFixture,
          .contentTypeRejected
        ),
        (
          [
            "Content-Type": "application/octet-stream", "Content-Encoding": "gzip",
            "Content-Length": String(bodyFixture.count),
          ],
          bodyFixture,
          .contentEncodingRejected
        ),
        (
          [
            "Content-Type": "application/octet-stream",
            "Content-Length": String(bodyFixture.count + 1),
          ],
          bodyFixture,
          .contentLengthRejected
        ),
        (
          [
            "Content-Type": "application/octet-stream",
            "Content-Length": String(bodyFixture.count),
          ],
          Data(bodyFixture.dropLast()),
          .contentLengthRejected
        ),
        (
          [
            "Content-Type": "application/octet-stream",
            "Content-Length": String(bodyFixture.count),
          ],
          bodyFixture + Data([0]),
          .oversized
        ),
      ]
    for testCase in cases {
      BodySamplingURLProtocol.reset()
      BodySamplingURLProtocol.manifestHeaders = testCase.headers
      BodySamplingURLProtocol.manifestBody = testCase.body
      let client = try makeClient()
      let plan = BranchDiscoveryClient.manifestBodyPlan()
      await #expect(throws: testCase.expected) {
        try await client.sampleCNManifestBody(
          acknowledgedPlanSHA256: plan.policySHA256,
          networkGate: BranchDiscoveryClient.requiredManifestBodyNetworkGate
        )
      }
      #expect(BodySamplingURLProtocol.requests.count == 3)
    }
  }

  @Test
  func closedGateAndFinalURLMismatchFailWithoutPayloadFollowup() async throws {
    BodySamplingURLProtocol.reset()
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestBodyPlan()
    await #expect(throws: ManifestSamplingError.executionGateClosed) {
      try await client.sampleCNManifestBody(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestMetadataNetworkGate
      )
    }
    #expect(BodySamplingURLProtocol.requests.isEmpty)

    BodySamplingURLProtocol.manifestResponseURL = URL(
      string: "https://other.example.com/not-the-request"
    )
    await #expect(throws: ManifestSamplingError.responseIdentityMismatch) {
      try await client.sampleCNManifestBody(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestBodyNetworkGate
      )
    }
    #expect(BodySamplingURLProtocol.requests.count == 3)
  }

  @Test
  func structurePlanIsCanonicalAndRequiresItsOwnGate() async throws {
    BodySamplingURLProtocol.reset()
    let client = try makeClient()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-manifest-structure-cn"],
      environment: [:],
      client: client
    )
    let plan = BranchDiscoveryClient.manifestStructurePlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(
      plan.policySHA256
        == "7ede9ed410cda836ac9ec2a43e2a5c33e7cf82e3d071bb8885dbf3ccccc5d382")
    #expect(
      plan.expectedCompressedBodySHA256
        == ManifestStructureDiscoveryProfile.expectedCompressedBodySHA256)
    #expect(plan.stopPolicy == "structureReceiptOnlyNoRegistryNoPayload")
    #expect(plan.maximumZstdWindowLog == 24)
    #expect(plan.profileRevision == 2)
    #expect(plan.schemaBaseline == "mgb-observed-cn-sophon-protobuf-structural-v2")
    #expect(plan.chunkInfoField7Policy == "requiredLowercaseHex32OpaqueNoIntegrityClaim")
    #expect(
      plan.manifestContentTypePolicy
        == "applicationOctetStreamWithAtMostFourBoundedASCIIParameters")
    #expect(
      plan.failurePolicy == "branchBuildManifestHeaderZstdWireAndStructuralCodeNoValue")
    #expect(!(ManifestStructurePlan.self is any Decodable.Type))
    #expect(BodySamplingURLProtocol.requests.isEmpty)

    await #expect(throws: ManifestSamplingError.executionGateClosed) {
      try await client.sampleCNManifestStructure(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestBodyNetworkGate,
        inspector: SyntheticBodyStructuralInspector()
      )
    }
    #expect(BodySamplingURLProtocol.requests.isEmpty)
  }

  @Test
  func structureTransactionConsumesOwnedBodyAndReturnsOnlyAggregates() async throws {
    BodySamplingURLProtocol.reset()
    BodySamplingURLProtocol.manifestHeaders["Content-Type"] =
      "application/octet-stream; charset=utf-8"
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestStructurePlan()
    let receipt = try await client.sampleCNManifestStructure(
      acknowledgedPlanSHA256: plan.policySHA256,
      networkGate: BranchDiscoveryClient.requiredManifestStructureNetworkGate,
      inspector: SyntheticBodyStructuralInspector()
    )
    #expect(BodySamplingURLProtocol.requests.count == 3)
    #expect(receipt.compressedBodySHA256 == sha256(bodyFixture))
    #expect(receipt.compressedByteSize == UInt64(bodyFixture.count))
    #expect(receipt.decompressedBodySHA256 == String(repeating: "d", count: 64))
    #expect(receipt.decompressedByteSize == 456)
    #expect(receipt.fileCount == 3)
    #expect(receipt.directoryCount == 1)
    #expect(receipt.chunkReferenceCount == 4)
    #expect(receipt.uniqueChunkObjectCount == 2)
    #expect(receipt.requestCount == 3)
    #expect(!(ManifestStructureReceipt.self is any Decodable.Type))
    let output = try ManifestSamplingCanonicalJSON.encode(receipt)
    let text = String(decoding: output, as: UTF8.self)
    for forbidden in bodyCanaries { #expect(!text.contains(forbidden)) }
  }

  @Test
  func structureInspectorFailureStopsWithoutAdditionalRequest() async throws {
    BodySamplingURLProtocol.reset()
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestStructurePlan()
    await #expect(throws: ManifestSamplingError.manifestStructuralRejected) {
      try await client.sampleCNManifestStructure(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestStructureNetworkGate,
        inspector: RejectingBodyStructuralInspector()
      )
    }
    #expect(BodySamplingURLProtocol.requests.count == 3)
  }

  @Test
  func structureTransportFailuresReportOnlyStageAndStop() async throws {
    let cases: [(stage: String, expected: ManifestSamplingError, requestCount: Int)] = [
      ("branch", .structureBranchRejected, 1),
      ("build", .structureBuildRejected, 2),
      ("manifest-type", .structureManifestContentTypeRejected, 3),
      ("manifest-encoding", .structureManifestEncodingRejected, 3),
      ("manifest-length", .structureManifestLengthRejected, 3),
    ]
    for testCase in cases {
      BodySamplingURLProtocol.reset()
      switch testCase.stage {
      case "branch": BodySamplingURLProtocol.branchContentType = "text/plain"
      case "build": BodySamplingURLProtocol.buildContentType = "text/plain"
      case "manifest-type":
        BodySamplingURLProtocol.manifestHeaders["Content-Type"] = "text/plain"
      case "manifest-encoding":
        BodySamplingURLProtocol.manifestHeaders["Content-Encoding"] = "gzip"
      default:
        BodySamplingURLProtocol.manifestHeaders["Content-Length"] = "1"
      }
      let client = try makeClient()
      let plan = BranchDiscoveryClient.manifestStructurePlan()
      await #expect(throws: testCase.expected) {
        try await client.sampleCNManifestStructure(
          acknowledgedPlanSHA256: plan.policySHA256,
          networkGate: BranchDiscoveryClient.requiredManifestStructureNetworkGate,
          inspector: SyntheticBodyStructuralInspector()
        )
      }
      #expect(BodySamplingURLProtocol.requests.count == testCase.requestCount)
    }
  }

  private func makeClient() throws -> BranchDiscoveryClient {
    let policies = try makePolicies()
    return BranchDiscoveryClient(
      configuration: bodySamplingConfiguration(),
      now: { Date(timeIntervalSince1970: 103) },
      mainBuildSemanticPolicy: policies.branch,
      mainBuildResponseSemanticPolicy: policies.build,
      manifestMetadataOriginPin: bodyOriginPin,
      manifestBodyExpectedRequestPathSHA256: bodyRequestPathSHA256,
      manifestBodyExpectedCompressedSize: UInt64(bodyFixture.count),
      manifestStructureExpectedBodySHA256: sha256(bodyFixture)
    )
  }

  private func makeBodyRequestReference(
    expectedRequestPathSHA256: String = bodyRequestPathSHA256,
    expectedCompressedSize: UInt64 = UInt64(bodyFixture.count)
  ) throws -> ValidatedMainManifestBodyRequestReference {
    let policies = try makePolicies()
    let branch = try StrictCNBranchSemanticDecoder.decode(
      bodyBranchJSON(),
      requestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      transportPolicySHA256: String(repeating: "a", count: 64),
      semanticPolicy: policies.branch
    )
    return try StrictMainManifestRequestDecoder.decodeBodyRequest(
      bodyBuildJSON(),
      branchCapability: branch,
      transportPolicySHA256: String(repeating: "b", count: 64),
      originPin: bodyOriginPin,
      expectedRequestPathSHA256: expectedRequestPathSHA256,
      expectedCompressedSize: expectedCompressedSize,
      semanticPolicy: policies.build
    )
  }

  private func makePolicies() throws -> (
    branch: BranchSemanticPolicy,
    build: MainBuildSemanticPolicy
  ) {
    let branchBody = bodyBranchJSON()
    let branchShape = try StrictJSONSchemaScanner.scan(branchBody, reportLimits: .standard)
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
    let buildBody = bodyBuildJSON()
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
    return (branchPolicy, buildPolicy)
  }
}

private let bodyPrefixPath = "/a/b/c/d/e"
private let bodyManifestID = "manifest-id-body-canary"
private let bodyRequestPathSHA256 = sha256(Data((bodyPrefixPath + "/" + bodyManifestID).utf8))
private let bodyOriginPin = ManifestOriginPin(
  safeOrigin: "https://cdn.example.com",
  pathComponentCount: 5,
  pathSHA256: sha256(Data(bodyPrefixPath.utf8))
)
private let bodyFixture = Data([0x28, 0xB5, 0x2F, 0xFD]) + Data("body-canary".utf8)
private let bodyCanaries = [
  "branch-canary", "package-canary", "password-canary", bodyManifestID,
  bodyPrefixPath, "body-canary",
]

private func bodyBranchJSON() -> Data {
  Data(
    #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
      .utf8
  )
}

private func bodyBuildJSON() -> Data {
  Data(
    """
    {"retcode":0,"message":"ok","data":{"tag":"tag-canary","build_id":"build-id-canary","manifests":[{"category_id":"game","category_name":"category-name-canary","matching_field":"game","manifest":{"id":"\(bodyManifestID)","checksum":"","compressed_size":"\(bodyFixture.count)","uncompressed_size":"456"},"manifest_download":{"password":"","url_prefix":"https://cdn.example.com\(bodyPrefixPath)"}}]}}
    """.utf8
  )
}

private func bodySamplingConfiguration() -> URLSessionConfiguration {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [BodySamplingURLProtocol.self]
  return configuration
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private struct SyntheticBodyStructuralInspector: ManifestBodyStructurallyInspecting {
  func inspect(
    _ input: ManifestLiveBodyInspectionInput
  ) throws -> ManifestChunkStructuralEvidence {
    guard input.data == bodyFixture,
      input.compressedSHA256 == sha256(bodyFixture),
      input.byteSize == UInt64(bodyFixture.count),
      input.manifestID == bodyManifestID,
      input.profileRevision == 2,
      input.release == "genshinOfficialCN",
      input.category == "game",
      input.schemaBaseline == "mgb-observed-cn-sophon-protobuf-structural-v2"
    else {
      throw ManifestSamplingError.manifestStructuralRejected
    }
    return ManifestChunkStructuralEvidence(
      decompressedBodySHA256: String(repeating: "d", count: 64),
      decompressedByteSize: 456,
      wirePolicyVersion: 1,
      fileCount: 3,
      directoryCount: 1,
      chunkReferenceCount: 4,
      uniqueChunkObjectCount: 2,
      targetInstalledBytes: 1_000,
      referencedChunkCompressedBytes: 700,
      uniqueChunkObjectBytes: 500,
      wireNodeCount: 9,
      wireStringBytes: 120
    )
  }
}

private struct RejectingBodyStructuralInspector: ManifestBodyStructurallyInspecting {
  func inspect(
    _ input: ManifestLiveBodyInspectionInput
  ) throws -> ManifestChunkStructuralEvidence {
    _ = input
    throw ManifestSamplingError.manifestStructuralRejected
  }
}

private final class BodySamplingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var observedRequests: [URLRequest] = []
  nonisolated(unsafe) static var manifestHeaders: [String: String] = [
    "Content-Type": "application/octet-stream",
    "Content-Length": String(bodyFixture.count),
  ]
  nonisolated(unsafe) static var manifestBody = bodyFixture
  nonisolated(unsafe) static var manifestResponseURL: URL?
  nonisolated(unsafe) static var branchContentType = "application/json"
  nonisolated(unsafe) static var buildContentType = "application/json"

  static func reset() {
    lock.lock()
    observedRequests = []
    manifestHeaders = [
      "Content-Type": "application/octet-stream",
      "Content-Length": String(bodyFixture.count),
    ]
    manifestBody = bodyFixture
    manifestResponseURL = nil
    branchContentType = "application/json"
    buildContentType = "application/json"
    lock.unlock()
  }

  static var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return observedRequests
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.observedRequests.append(request)
    let headers = Self.manifestHeaders
    let manifestBody = Self.manifestBody
    let overrideURL = Self.manifestResponseURL
    let branchContentType = Self.branchContentType
    let buildContentType = Self.buildContentType
    Self.lock.unlock()

    let body: Data
    let responseHeaders: [String: String]
    switch request.url?.host {
    case "hyp-api.mihoyo.com":
      body = bodyBranchJSON()
      responseHeaders = [
        "Content-Type": branchContentType,
        "Content-Length": String(body.count),
      ]
    case "api-takumi.mihoyo.com":
      body = bodyBuildJSON()
      responseHeaders = [
        "Content-Type": buildContentType,
        "Content-Length": String(body.count),
      ]
    case "cdn.example.com":
      body = manifestBody
      responseHeaders = headers
    default:
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let responseURL =
      request.url?.host == "cdn.example.com" ? (overrideURL ?? request.url) : request.url
    guard let responseURL,
      let response = HTTPURLResponse(
        url: responseURL,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: responseHeaders
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for offset in stride(from: 0, to: body.count, by: 3) {
      client?.urlProtocol(
        self,
        didLoad: body.subdata(in: offset..<min(offset + 3, body.count))
      )
    }
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
