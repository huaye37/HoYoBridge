import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct BranchShapeDiscoveryTests {
  @Test
  func shapePlanIsCanonicalSafeAndBindsReportPolicy() async throws {
    ShapeSamplingURLProtocol.reset()
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(ShapeSamplingURLProtocol.self)
    )
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["plan-branches-shape-cn"],
      environment: [:],
      client: client
    )
    let plan = BranchDiscoveryClient.shapeReportPlan()
    let expected = try ManifestSamplingCanonicalJSON.encode(plan)
    #expect(output == expected)
    #expect(ShapeSamplingURLProtocol.startCount == 0)
    #expect(
      plan.requestIdentitySHA256
        == "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d")
    #expect(plan.policySHA256 == "e7ebc929ac6a6d25dc16c0d58bbaa67cfd15d7dda394b30bd150fd819cf220e4")
    #expect(plan.reportPolicyVersion == 1)
    #expect(plan.knownKeyNames == SafeJSONShapeReportPolicyV1.knownKeyNames)
    #expect(plan.priorShapeSHA256 == BranchShapeDiscoveryProfile.priorShapeSHA256)
    #expect(plan.stopPolicy == "receiptOnlyNoCapabilityNoFollowup")
    #expect(
      BranchShapeDiscoveryProfile.matchesPriorShape(
        policyVersion: plan.priorShapePolicyVersion,
        sha256: plan.priorShapeSHA256,
        gameBranchEntryCount: plan.priorGameBranchEntryCount
      )
    )
    #expect(
      !BranchShapeDiscoveryProfile.matchesPriorShape(
        policyVersion: plan.priorShapePolicyVersion,
        sha256: String(repeating: "0", count: 64),
        gameBranchEntryCount: plan.priorGameBranchEntryCount
      )
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(text.contains(#""knownKeyNames":["biz","branch""#))
    #expect(text.contains(#""password""#))
    #expect(!text.contains("game_ids"))
    #expect(!text.contains("launcher_id"))
    #expect(!text.contains("1Z8W5NHUQb"))
    #expect(!text.contains("jGHBHlcOq1"))
  }

  @Test
  func shapeCommandRequiresItsOwnGateAndAckBeforeNetwork() async throws {
    ShapeSamplingURLProtocol.reset()
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(ShapeSamplingURLProtocol.self)
    )
    let plan = BranchDiscoveryClient.shapeReportPlan()
    let cases: [([String], [String: String])] = [
      (["sample-branches-shape-cn", "--ack", plan.policySHA256], [:]),
      (
        ["sample-branches-shape-cn", "--ack", plan.policySHA256],
        [
          BranchDiscoveryClient.networkGateEnvironmentKey:
            BranchDiscoveryClient.requiredNetworkGate
        ]
      ),
      (
        ["sample-branches-shape-cn", "--ack", "wrong"],
        [
          BranchDiscoveryClient.networkGateEnvironmentKey:
            BranchDiscoveryClient.requiredShapeReportNetworkGate
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
    #expect(ShapeSamplingURLProtocol.startCount == 0)
  }

  @Test
  func emitsOnlySafeShapeAndStopsAfterOneFixedRequest() async throws {
    ShapeSamplingURLProtocol.reset()
    let unknownKey = "unknown-key-canary"
    let unknownValue = "unknown-value-canary"
    let body = Data(
      """
      {"retcode":0,"message":"\(unknownValue)","data":{"game_branches":[{"game":{"id":"game-id-canary","biz":"biz-canary","\(unknownKey)":true},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}
      """.utf8
    )
    ShapeSamplingURLProtocol.handler = { request in
      #expect(request.url?.path == "/hyp/hyp-connect/api/getGameBranches")
      return .response(
        mockHTTPResponse(
          request: request,
          headers: [
            "Content-Type": "application/json",
            "Content-Length": "\(body.count)",
            "Set-Cookie": "cookie-canary=secret",
          ]
        ),
        body,
        chunkSize: 11
      )
    }
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(ShapeSamplingURLProtocol.self),
      now: { Date(timeIntervalSince1970: 42) }
    )
    let plan = BranchDiscoveryClient.shapeReportPlan()
    let output = try await ManifestSampleCommandRunner.execute(
      arguments: ["sample-branches-shape-cn", "--ack", plan.policySHA256],
      environment: [
        BranchDiscoveryClient.networkGateEnvironmentKey:
          BranchDiscoveryClient.requiredShapeReportNetworkGate
      ],
      client: client
    )
    let text = String(decoding: output, as: UTF8.self)
    #expect(ShapeSamplingURLProtocol.startCount == 1)
    #expect(text.contains(#""reportPolicyVersion":1"#))
    #expect(text.contains(#""matchesPriorShape":false"#))
    #expect(text.contains(#""name":"game""#))
    #expect(text.contains(#""name":"password""#))
    #expect(text.contains(sha256(Data(unknownKey.utf8))))
    for forbidden in [
      unknownKey, unknownValue, "game-id-canary", "biz-canary", "tag-canary",
      "branch-canary", "package-canary", "password-canary", "cookie-canary",
      "getBuild", "manifest", "payload",
    ] {
      #expect(!text.contains(forbidden))
    }
    #expect(output.count <= BranchShapeDiscoveryProfile.maximumCanonicalReceiptBytes)
    #expect(!(BranchShapeReportPlan.self is any Decodable.Type))
    #expect(!(BranchShapeReportReceipt.self is any Decodable.Type))
    var dumped = ""
    dump(plan, to: &dumped)
    #expect(dumped.contains("redacted"))
    #expect(!dumped.contains("mihoyo"))
  }
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class ShapeSamplingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> SamplingMockResult)?
  nonisolated(unsafe) private static var starts = 0

  static func reset() {
    lock.lock()
    handler = nil
    starts = 0
    lock.unlock()
  }

  static var startCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return starts
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.starts += 1
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
