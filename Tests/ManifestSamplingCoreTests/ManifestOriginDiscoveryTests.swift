import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct ManifestOriginDiscoveryTests {
  @Test
  func planAndOriginPolicyAreSafeAndCanonical() async throws {
    OriginSamplingURLProtocol.reset()
    let client = try makeClient(urlPrefix: "https://cdn.example.com/a/b")
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-manifest-origin-cn"],
      environment: [:],
      client: client
    )
    let plan = BranchDiscoveryClient.manifestOriginPlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(OriginSamplingURLProtocol.startCount == 0)
    #expect(
      plan.policySHA256
        == "626daa27d87bc10a41afce9e833249d7d662157675b4cf3a7772233704e62dde")
    #expect(
      plan.mainBuildPlan.policySHA256 == BranchDiscoveryClient.mainBuildShapePlan().policySHA256)
    #expect(plan.stopPolicy == "originReceiptOnlyNoManifestRequest")
    #expect(plan.failurePolicy == "safeOriginStageCodeNoValue")
    #expect(plan.semanticScopePolicy == "tagUniqueGameAndURLPrefixOnly")
    let text = String(decoding: output, as: UTF8.self)
    #expect(!text.contains("cdn.example.com"))
    for forbidden in originCanaries { #expect(!text.contains(forbidden)) }
  }

  @Test
  func validatesSafeOriginAndRejectsUnsafePrefixes() throws {
    let reference = try makeOriginReference(urlPrefix: "https://cdn.example.com/a/b")
    let valid = try ManifestOriginDiscoveryProfile.inspect(
      capability: reference
    )
    #expect(valid.safeOrigin == "https://cdn.example.com")
    #expect(valid.pathComponentCount == 2)
    #expect(valid.pathSHA256 == sha256(Data("/a/b".utf8)))
    #expect(valid.description == "<redacted>")
    #expect(!(ValidatedMainBuildOriginReference.self is any Encodable.Type))
    #expect(!(ValidatedMainBuildOriginReference.self is any Decodable.Type))
    var dumped = ""
    dump(reference, to: &dumped)
    #expect(dumped.contains("redacted"))
    #expect(!dumped.contains("cdn.example.com"))

    let invalid = [
      "http://cdn.example.com/a/b",
      "https://127.0.0.1/a/b",
      "https://[::1]/a/b",
      "https://cdn.example.com:443/a/b",
      "https://user@cdn.example.com/a/b",
      "https://cdn.example.com/a/b?token=secret",
      "https://cdn.example.com/a/b#fragment",
      "https://cdn.example.com/a/../b",
      "https://cdn.example.com/a/%2E%2E/b",
      "https://CDN.example.com/a/b",
      "https://localhost/a/b",
      "https://cdn.example.com/",
      "https://cdn.example.com/" + String(repeating: "a/", count: 33),
      "https://cdn.example.com/" + String(repeating: "a", count: 129),
    ]
    for prefix in invalid {
      #expect(throws: ManifestSamplingError.originRejected) {
        try ManifestOriginDiscoveryProfile.inspect(
          capability: makeOriginReference(urlPrefix: prefix)
        )
      }
    }
  }

  @Test
  func gatedTransactionReturnsOnlyOriginAndStopsAfterBuild() async throws {
    OriginSamplingURLProtocol.reset()
    let branchBody = originBranchBody()
    let buildBody = originBuildBody(
      urlPrefix: "https://cdn.example.com/secret/path",
      downloadPassword: ""
    )
    OriginSamplingURLProtocol.handler = { request in
      switch request.url?.host {
      case "hyp-api.mihoyo.com":
        return .response(mockHTTPResponse(request: request), branchBody, chunkSize: 19)
      case "api-takumi.mihoyo.com":
        return .response(mockHTTPResponse(request: request), buildBody, chunkSize: 23)
      default:
        return .failure(URLError(.unsupportedURL))
      }
    }
    let client = try makeClient(
      urlPrefix: "https://cdn.example.com/secret/path",
      downloadPassword: ""
    )
    let plan = BranchDiscoveryClient.manifestOriginPlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["sample-manifest-origin-cn", "--ack", plan.policySHA256],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey:
          BranchDiscoveryClient.requiredManifestOriginNetworkGate
      ],
      client: client
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(OriginSamplingURLProtocol.hosts == ["hyp-api.mihoyo.com", "api-takumi.mihoyo.com"])
    #expect(text.contains(#""manifestSafeOrigin":"https://cdn.example.com""#))
    #expect(text.contains(#""manifestPathComponentCount":2"#))
    #expect(text.contains(sha256(Data("/secret/path".utf8))))
    #expect(text.contains(#""requestCount":2"#))
    for forbidden in originCanaries + ["/secret/path", "manifest-id-canary"] {
      #expect(!text.contains(forbidden))
    }
    #expect(!(ManifestOriginPlan.self is any Decodable.Type))
    #expect(!(ManifestOriginReceipt.self is any Decodable.Type))
  }

  @Test
  func closedGateStartsNoRequest() async throws {
    OriginSamplingURLProtocol.reset()
    let client = try makeClient(urlPrefix: "https://cdn.example.com/a/b")
    let plan = BranchDiscoveryClient.manifestOriginPlan()
    await #expect(throws: ManifestSamplingError.executionGateClosed) {
      try await client.sampleCNManifestOrigin(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredMainBuildNetworkGate
      )
    }
    #expect(OriginSamplingURLProtocol.startCount == 0)
  }

  @Test
  func semanticFailureReturnsOnlySafeStageCodeAndStopsAfterBuild() async throws {
    OriginSamplingURLProtocol.reset()
    let branchBody = originBranchBody()
    let buildBody = originBuildBody(urlPrefix: "")
    OriginSamplingURLProtocol.handler = { request in
      switch request.url?.host {
      case "hyp-api.mihoyo.com":
        return .response(mockHTTPResponse(request: request), branchBody, chunkSize: nil)
      case "api-takumi.mihoyo.com":
        return .response(mockHTTPResponse(request: request), buildBody, chunkSize: nil)
      default:
        return .failure(URLError(.unsupportedURL))
      }
    }
    let client = try makeClient(urlPrefix: "")
    let plan = BranchDiscoveryClient.manifestOriginPlan()
    await #expect(throws: ManifestSamplingError.buildDownloadReferenceRejected) {
      try await client.sampleCNManifestOrigin(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredManifestOriginNetworkGate
      )
    }
    #expect(OriginSamplingURLProtocol.hosts == ["hyp-api.mihoyo.com", "api-takumi.mihoyo.com"])
  }

  private func makeClient(
    urlPrefix: String,
    downloadPassword: String = "download-password-canary"
  ) throws -> BranchDiscoveryClient {
    let branchBody = originBranchBody()
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
    let buildBody = originBuildBody(
      urlPrefix: urlPrefix,
      downloadPassword: downloadPassword
    )
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
    return BranchDiscoveryClient(
      configuration: samplingConfiguration(OriginSamplingURLProtocol.self),
      now: { Date(timeIntervalSince1970: 99) },
      mainBuildSemanticPolicy: branchPolicy,
      mainBuildResponseSemanticPolicy: buildPolicy
    )
  }

  private func makeOriginReference(
    urlPrefix: String
  ) throws -> ValidatedMainBuildOriginReference {
    let branchBody = originBranchBody()
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
    let buildBody = originBuildBody(urlPrefix: urlPrefix)
    let shape = try StrictJSONSchemaScanner.scanRootData(buildBody, reportLimits: .standard)
    let report = try #require(shape.safeReport)
    let policy = MainBuildSemanticPolicy(
      policyVersion: 1,
      expectedShapePolicyVersion: shape.policyVersion,
      expectedShapeSHA256: shape.sha256,
      expectedReportPolicyVersion: report.policyVersion,
      expectedReportSHA256: report.sha256,
      expectedCanonicalReportByteSize: report.canonicalByteSize,
      expectedMatchingField: "game"
    )
    return try StrictMainBuildOriginDecoder.decode(
      buildBody,
      branchCapability: branch,
      transportPolicySHA256: String(repeating: "b", count: 64),
      semanticPolicy: policy
    )
  }
}

private let originCanaries = [
  "branch-canary", "package-canary", "password-canary", "download-password-canary",
]

private func originBranchBody() -> Data {
  Data(
    #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
      .utf8
  )
}

private func originBuildBody(
  urlPrefix: String,
  downloadPassword: String = "download-password-canary"
) -> Data {
  Data(
    """
    {"retcode":0,"message":"ok","data":{"tag":"tag-canary","build_id":"build-id-canary","manifests":[{"category_id":"game","category_name":"category-name-canary","matching_field":"game","manifest":{"id":"manifest-id-canary","checksum":"checksum-canary","compressed_size":"123","uncompressed_size":"456"},"manifest_download":{"password":"\(downloadPassword)","url_prefix":"\(urlPrefix)"}}]}}
    """.utf8
  )
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class OriginSamplingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> SamplingMockResult)?
  nonisolated(unsafe) private static var observedHosts: [String] = []

  static func reset() {
    lock.lock()
    handler = nil
    observedHosts = []
    lock.unlock()
  }

  static var startCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return observedHosts.count
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
              self, didLoad: data.subdata(in: offset..<min(offset + chunkSize, data.count)))
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
