import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct ManifestMetadataDiscoveryTests {
  @Test
  func planIsCanonicalPinnedAndStartsNoNetwork() async throws {
    MetadataSamplingURLProtocol.reset()
    let client = try makeClient()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-manifest-metadata-cn"],
      environment: [:],
      client: client
    )
    let plan = BranchDiscoveryClient.manifestMetadataPlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(
      plan.policySHA256
        == "32809f02f6843c6f8f9ea931f18c25d1bb68f3f410b286b46b79405eb64aff8b")
    #expect(
      plan.manifestRequestTemplateSHA256
        == "65f8d3ea14e740776deed2a458bf83b1a172e3d5b5cf11bf5879cb7261d362f5")
    #expect(plan.manifestSafeOrigin == "https://autopatchcn.yuanshen.com")
    #expect(plan.manifestPrefixPathComponentCount == 5)
    #expect(plan.stopPolicy == "metadataReceiptOnlyNoBodyNoPayload")
    #expect(!(ManifestMetadataPlan.self is any Decodable.Type))
    #expect(MetadataSamplingURLProtocol.requests.isEmpty)
    let text = String(decoding: output, as: UTF8.self)
    for forbidden in metadataCanaries { #expect(!text.contains(forbidden)) }
  }

  @Test
  func narrowRequestReferenceBindsOriginAndRedactsManifestID() throws {
    let reference = try makeManifestRequestReference()
    #expect(reference.safeOrigin == "https://cdn.example.com")
    #expect(reference.prefixPathComponentCount == 5)
    #expect(reference.prefixPathSHA256 == sha256(Data(metadataPrefixPath.utf8)))
    #expect(reference.manifestURL.host == "cdn.example.com")
    #expect(!(ValidatedMainManifestRequestReference.self is any Encodable.Type))
    #expect(!(ValidatedMainManifestRequestReference.self is any Decodable.Type))
    var dumped = ""
    dump(reference, to: &dumped)
    #expect(dumped.contains("redacted"))
    for forbidden in metadataCanaries { #expect(!dumped.contains(forbidden)) }

    let wrongPin = ManifestOriginPin(
      safeOrigin: "https://other.example.com",
      pathComponentCount: 5,
      pathSHA256: sha256(Data(metadataPrefixPath.utf8))
    )
    #expect(throws: ManifestSamplingError.originRejected) {
      try makeManifestRequestReference(originPin: wrongPin)
    }
    #expect(throws: ManifestSamplingError.buildManifestReferenceRejected) {
      try makeManifestRequestReference(manifestID: "unsafe/id")
    }
  }

  @Test
  func gatedTransactionReturnsMetadataAndAcceptsNoManifestBody() async throws {
    MetadataSamplingURLProtocol.reset()
    MetadataSamplingURLProtocol.manifestHeaders = [
      "Content-Type": "application/octet-stream",
      "Content-Encoding": "identity",
      "Content-Length": "12345",
    ]
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestMetadataPlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["sample-manifest-metadata-cn", "--ack", plan.policySHA256],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey:
          BranchDiscoveryClient.requiredManifestMetadataNetworkGate
      ],
      client: client
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(
      MetadataSamplingURLProtocol.requests.map(\.url?.host) == [
        "hyp-api.mihoyo.com", "api-takumi.mihoyo.com", "cdn.example.com",
      ])
    #expect(
      MetadataSamplingURLProtocol.requests.map {
        $0.value(forHTTPHeaderField: "Accept")
      } == ["application/json", "application/json", "application/octet-stream"]
    )
    #expect(text.contains(#""contentTypeKind":"applicationOctetStream""#))
    #expect(text.contains(#""contentEncodingKind":"identity""#))
    #expect(text.contains(#""contentLengthState":"withinLimit""#))
    #expect(text.contains(#""declaredContentLength":12345"#))
    #expect(text.contains(#""requestCount":3"#))
    #expect(text.contains(#""responseBodyAccepted":false"#))
    #expect(!(ManifestMetadataReceipt.self is any Decodable.Type))
    for forbidden in metadataCanaries { #expect(!text.contains(forbidden)) }
  }

  @Test
  func unknownHeadersAreHashedAndMalformedLengthIsValueFree() async throws {
    MetadataSamplingURLProtocol.reset()
    MetadataSamplingURLProtocol.manifestHeaders = [
      "Content-Type": "text/x-metadata-canary",
      "Content-Encoding": "br-metadata-canary",
      "Content-Length": "001",
    ]
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestMetadataPlan()
    let receipt = try await client.sampleCNManifestMetadata(
      acknowledgedPlanSHA256: plan.policySHA256,
      networkGate: BranchDiscoveryClient.requiredManifestMetadataNetworkGate
    )
    #expect(
      receipt.contentTypeKind
        == "otherSHA256:" + sha256(Data("text/x-metadata-canary".utf8)))
    #expect(
      receipt.contentEncodingKind
        == "otherSHA256:" + sha256(Data("br-metadata-canary".utf8)))
    #expect(receipt.contentLengthState == "invalid")
    #expect(receipt.declaredContentLength == nil)
    let output = try ManifestSamplingCanonicalJSON.encode(receipt)
    let text = String(decoding: output, as: UTF8.self)
    #expect(!text.contains("metadata-canary"))
    #expect(!text.contains(metadataManifestBodyCanary))

    MetadataSamplingURLProtocol.reset()
    let overLimit = ManifestMetadataDiscoveryProfile.maximumDeclaredContentLength + 1
    MetadataSamplingURLProtocol.manifestHeaders = [
      "Content-Type": "application/octet-stream",
      "Content-Length": String(overLimit),
    ]
    let overLimitReceipt = try await makeClient().sampleCNManifestMetadata(
      acknowledgedPlanSHA256: plan.policySHA256,
      networkGate: BranchDiscoveryClient.requiredManifestMetadataNetworkGate
    )
    #expect(overLimitReceipt.contentLengthState == "overLimit")
    #expect(overLimitReceipt.declaredContentLength == overLimit)
    #expect(overLimitReceipt.responseBodyAccepted == false)
  }

  @Test
  func closedGateAndFinalURLMismatchFailWithoutFollowup() async throws {
    MetadataSamplingURLProtocol.reset()
    let client = try makeClient()
    let plan = BranchDiscoveryClient.manifestMetadataPlan()
    await #expect(throws: ManifestSamplingError.executionGateClosed) {
      try await client.sampleCNManifestMetadata(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestOriginNetworkGate
      )
    }
    #expect(MetadataSamplingURLProtocol.requests.isEmpty)

    MetadataSamplingURLProtocol.manifestResponseURL = URL(
      string: "https://other.example.com/not-the-request"
    )
    await #expect(throws: ManifestSamplingError.responseIdentityMismatch) {
      try await client.sampleCNManifestMetadata(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestMetadataNetworkGate
      )
    }
    #expect(MetadataSamplingURLProtocol.requests.count == 3)
  }

  private func makeClient() throws -> BranchDiscoveryClient {
    let branchBody = metadataBranchBody()
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
    let buildBody = metadataBuildBody()
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
    let originPin = ManifestOriginPin(
      safeOrigin: "https://cdn.example.com",
      pathComponentCount: 5,
      pathSHA256: sha256(Data(metadataPrefixPath.utf8))
    )
    return BranchDiscoveryClient(
      configuration: metadataSamplingConfiguration(),
      now: { Date(timeIntervalSince1970: 101) },
      mainBuildSemanticPolicy: branchPolicy,
      mainBuildResponseSemanticPolicy: buildPolicy,
      manifestMetadataOriginPin: originPin
    )
  }

  private func makeManifestRequestReference(
    manifestID: String = metadataManifestID,
    originPin: ManifestOriginPin? = nil
  ) throws -> ValidatedMainManifestRequestReference {
    let branchBody = metadataBranchBody()
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
    let branch = try StrictCNBranchSemanticDecoder.decode(
      branchBody,
      requestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      transportPolicySHA256: String(repeating: "a", count: 64),
      semanticPolicy: branchPolicy
    )
    let buildBody = metadataBuildBody(manifestID: manifestID)
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
    return try StrictMainManifestRequestDecoder.decode(
      buildBody,
      branchCapability: branch,
      transportPolicySHA256: String(repeating: "b", count: 64),
      originPin: originPin
        ?? ManifestOriginPin(
          safeOrigin: "https://cdn.example.com",
          pathComponentCount: 5,
          pathSHA256: sha256(Data(metadataPrefixPath.utf8))
        ),
      semanticPolicy: buildPolicy
    )
  }
}

private let metadataPrefixPath = "/a/b/c/d/e"
private let metadataManifestID = "manifest-id-canary"
private let metadataManifestBodyCanary = "manifest-body-canary-must-not-be-accepted"
private let metadataCanaries = [
  "branch-canary", "package-canary", "password-canary", metadataManifestID,
  metadataPrefixPath, metadataManifestBodyCanary,
]

private func metadataBranchBody() -> Data {
  Data(
    #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
      .utf8
  )
}

private func metadataBuildBody(
  manifestID: String = metadataManifestID
) -> Data {
  Data(
    """
    {"retcode":0,"message":"ok","data":{"tag":"tag-canary","build_id":"build-id-canary","manifests":[{"category_id":"game","category_name":"category-name-canary","matching_field":"game","manifest":{"id":"\(manifestID)","checksum":"","compressed_size":"123","uncompressed_size":"456"},"manifest_download":{"password":"","url_prefix":"https://cdn.example.com\(metadataPrefixPath)"}}]}}
    """.utf8
  )
}

private func metadataSamplingConfiguration() -> URLSessionConfiguration {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [MetadataSamplingURLProtocol.self]
  return configuration
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class MetadataSamplingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var observedRequests: [URLRequest] = []
  nonisolated(unsafe) static var manifestHeaders: [String: String] = [
    "Content-Type": "application/octet-stream",
    "Content-Length": "12345",
  ]
  nonisolated(unsafe) static var manifestResponseURL: URL?

  static func reset() {
    lock.lock()
    observedRequests = []
    manifestHeaders = [
      "Content-Type": "application/octet-stream",
      "Content-Length": "12345",
    ]
    manifestResponseURL = nil
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
    let overrideURL = Self.manifestResponseURL
    Self.lock.unlock()

    let body: Data
    let responseHeaders: [String: String]
    switch request.url?.host {
    case "hyp-api.mihoyo.com":
      body = metadataBranchBody()
      responseHeaders = [
        "Content-Type": "application/json",
        "Content-Length": String(body.count),
      ]
    case "api-takumi.mihoyo.com":
      body = metadataBuildBody()
      responseHeaders = [
        "Content-Type": "application/json",
        "Content-Length": String(body.count),
      ]
    case "cdn.example.com":
      body = Data(metadataManifestBodyCanary.utf8)
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
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
