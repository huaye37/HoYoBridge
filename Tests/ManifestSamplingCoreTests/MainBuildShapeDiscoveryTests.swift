import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct MainBuildShapeDiscoveryTests {
  @Test
  func planIsSafeCanonicalAndRequiresTwoRequestStop() async throws {
    MainBuildSamplingURLProtocol.reset()
    let client = try makeClient()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-build-main-cn"],
      environment: [:],
      client: client
    )
    let plan = BranchDiscoveryClient.mainBuildShapePlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(MainBuildSamplingURLProtocol.startCount == 0)
    #expect(plan.policySHA256 == "dd0ab612aee8d025894e7f43269a287434844ecc29c2dbe03e70ea887844277d")
    #expect(
      plan.buildRequestTemplateSHA256
        == "a44a5523f11e6e26322d9ae118675b845c4751f6fadc2ead433c89ccc91e306d")
    #expect(plan.buildQueryNames == ["branch", "package_id", "password"])
    #expect(plan.maximumBranchResponseBytes == 1_048_576)
    #expect(plan.maximumBuildResponseBytes == 8_388_608)
    #expect(plan.maximumTotalResponseBytes == 9_437_184)
    #expect(plan.stopPolicy == "buildReceiptOnlyNoManifestNoPayload")
    #expect(
      BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodServerTrust,
        host: "api-takumi.mihoyo.com",
        protocolName: "https",
        port: 443,
        previousFailureCount: 0,
        expectedHost: "api-takumi.mihoyo.com"
      )
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains(#""buildSafeOrigin":"https://api-takumi.mihoyo.com""#))
    for forbidden in mainBuildCanaries {
      #expect(!text.contains(forbidden))
    }
  }

  @Test
  func closedGateStartsNoRequest() async throws {
    MainBuildSamplingURLProtocol.reset()
    let client = try makeClient()
    let plan = BranchDiscoveryClient.mainBuildShapePlan()
    let cases = [
      (["sample-build-main-cn", "--ack", plan.policySHA256], [:]),
      (
        ["sample-build-main-cn", "--ack", plan.policySHA256],
        [
          BranchDiscoveryClient.networkGateEnvironmentKey:
            BranchDiscoveryClient.requiredShapeReportNetworkGate
        ]
      ),
      (
        ["sample-build-main-cn", "--ack", "wrong"],
        [
          BranchDiscoveryClient.networkGateEnvironmentKey:
            BranchDiscoveryClient.requiredMainBuildNetworkGate
        ]
      ),
    ]
    for item in cases {
      await #expect(throws: ManifestSamplingError.executionGateClosed) {
        try await ManifestSampleCommandRunner.execute(
          arguments: item.0,
          environment: item.1,
          client: client
        )
      }
    }
    #expect(MainBuildSamplingURLProtocol.startCount == 0)
  }

  @Test
  func performsFreshBranchesThenOneBuildAndReturnsOnlySafeShape() async throws {
    MainBuildSamplingURLProtocol.reset()
    let branchBody = mainBuildBranchBody()
    let buildBody = mainBuildResponseBody()
    MainBuildSamplingURLProtocol.handler = { request in
      switch request.url?.host {
      case "hyp-api.mihoyo.com":
        #expect(request.url?.path == "/hyp/hyp-connect/api/getGameBranches")
        return .response(
          mockHTTPResponse(
            request: request,
            headers: [
              "Content-Type": "application/json",
              "Content-Length": "\(branchBody.count)",
            ]
          ),
          branchBody,
          chunkSize: 17
        )
      case "api-takumi.mihoyo.com":
        #expect(request.url?.path == "/downloader/sophon_chunk/api/getBuild")
        let query = URLComponents(
          url: request.url!,
          resolvingAgainstBaseURL: false
        )?.queryItems
        #expect(query?.map(\.name) == ["branch", "package_id", "password"])
        #expect(
          query?.map(\.value) == [
            "branch-canary", "package-canary", "password-canary",
          ]
        )
        return .response(
          mockHTTPResponse(
            request: request,
            headers: [
              "Content-Type": "application/json; charset=utf-8",
              "Content-Length": "\(buildBody.count)",
              "Set-Cookie": "cookie-canary=ignored",
            ]
          ),
          buildBody,
          chunkSize: 13
        )
      default:
        return .failure(URLError(.unsupportedURL))
      }
    }
    let client = try makeClient()
    let plan = BranchDiscoveryClient.mainBuildShapePlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["sample-build-main-cn", "--ack", plan.policySHA256],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey:
          BranchDiscoveryClient.requiredMainBuildNetworkGate
      ],
      client: client
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(MainBuildSamplingURLProtocol.hosts == ["hyp-api.mihoyo.com", "api-takumi.mihoyo.com"])
    #expect(text.contains(#""requestCount":2"#))
    #expect(text.contains(#""name":"tag""#))
    #expect(text.contains(sha256(Data("manifests".utf8))))
    #expect(!text.contains("buildRequestIdentity"))
    for forbidden in mainBuildCanaries + ["manifest-id-canary", "url-prefix-canary"] {
      #expect(!text.contains(forbidden))
    }
    #expect(!(MainBuildShapePlan.self is any Decodable.Type))
    #expect(!(MainBuildShapeReceipt.self is any Decodable.Type))
  }

  @Test
  func branchSemanticFailureStopsBeforeBuild() async throws {
    MainBuildSamplingURLProtocol.reset()
    let invalidBranch = Data(
      #"{"retcode":0,"message":"ok","data":{"game_branches":[]}}"#.utf8
    )
    MainBuildSamplingURLProtocol.handler = { request in
      .response(mockHTTPResponse(request: request), invalidBranch, chunkSize: nil)
    }
    let client = try makeClient()
    let plan = BranchDiscoveryClient.mainBuildShapePlan()
    await #expect(throws: (any Error).self) {
      try await client.sampleCNMainBuildShape(
        acknowledgedPlanSHA256: plan.policySHA256,
        networkGate: BranchDiscoveryClient.requiredMainBuildNetworkGate
      )
    }
    #expect(MainBuildSamplingURLProtocol.startCount == 1)
  }

  private func makeClient() throws -> BranchDiscoveryClient {
    let body = mainBuildBranchBody()
    let shape = try StrictJSONSchemaScanner.scan(body, reportLimits: .standard)
    let report = try #require(shape.safeReport)
    let policy = BranchSemanticPolicy(
      policyVersion: 1,
      expectedRequestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      expectedShapePolicyVersion: shape.policyVersion,
      expectedShapeSHA256: shape.sha256,
      expectedGameBranchEntryCount: shape.gameBranchEntryCount,
      expectedReportPolicyVersion: report.policyVersion,
      expectedReportSHA256: report.sha256,
      expectedCanonicalReportByteSize: report.canonicalByteSize,
      expectedGameID: "1Z8W5NHUQb"
    )
    return BranchDiscoveryClient(
      configuration: samplingConfiguration(MainBuildSamplingURLProtocol.self),
      now: { Date(timeIntervalSince1970: 77) },
      mainBuildSemanticPolicy: policy
    )
  }
}

private let mainBuildCanaries = [
  "branch-canary", "package-canary", "password-canary", "biz-canary", "tag-canary",
  "build-tag-canary",
]

private func mainBuildBranchBody() -> Data {
  Data(
    #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
      .utf8
  )
}

private func mainBuildResponseBody() -> Data {
  Data(
    #"{"retcode":0,"message":"ok","data":{"tag":"build-tag-canary","manifests":[{"matching_field":"game","manifest":{"id":"manifest-id-canary"},"manifest_download":{"url_prefix":"url-prefix-canary"}}]}}"#
      .utf8
  )
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class MainBuildSamplingURLProtocol: URLProtocol, @unchecked Sendable {
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
            let end = min(offset + chunkSize, data.count)
            client?.urlProtocol(self, didLoad: data.subdata(in: offset..<end))
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
