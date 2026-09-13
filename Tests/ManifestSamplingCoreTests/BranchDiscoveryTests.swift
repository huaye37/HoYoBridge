import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite(.serialized)
struct BranchDiscoveryTests {
  @Test
  func sendsExactFixedRequestAndReturnsValueFreeReceipt() async throws {
    SamplingMockURLProtocol.reset()
    let body = validBranchBody()
    SamplingMockURLProtocol.handler = { request in
      #expect(request.httpMethod == "GET")
      #expect(request.httpBody == nil)
      #expect(!request.httpShouldHandleCookies)
      #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
      #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
      #expect(request.url?.scheme == "https")
      #expect(request.url?.host == "hyp-api.mihoyo.com")
      #expect(request.url?.path == "/hyp/hyp-connect/api/getGameBranches")
      let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
      #expect(items?.map(\.name) == ["game_ids[]", "launcher_id"])
      #expect(items?.map(\.value) == ["1Z8W5NHUQb", "jGHBHlcOq1"])
      return .response(
        mockHTTPResponse(
          request: request,
          headers: [
            "Content-Type": "application/json; charset=utf-8",
            "Content-Length": "\(body.count)",
            "Set-Cookie": "canary-cookie=secret",
          ]
        ),
        body,
        chunkSize: 7
      )
    }
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingMockURLProtocol.self),
      now: { Date(timeIntervalSince1970: 123) }
    )
    let receipt = try await sample(client)
    #expect(receipt.statusCode == 200)
    #expect(receipt.observedAtUnixSeconds == 123)
    #expect(receipt.byteSize == UInt64(body.count))
    #expect(receipt.bodySHA256 == digest(body))
    #expect(receipt.policySHA256 == BranchDiscoveryClient.plan().policySHA256)
    #expect(receipt.valueFreeShapePolicyVersion == 1)
    #expect(receipt.valueFreeShapeSHA256.count == 64)
    #expect(receipt.gameBranchEntryCount == 1)
    let encoded = try ManifestSamplingCanonicalJSON.encode(receipt)
    let text = String(decoding: encoded, as: UTF8.self)
    for forbidden in [
      "mihoyo", "game_ids", "launcher_id", "1Z8W5NHUQb", "jGHBHlcOq1",
      "canary-tag", "canary-branch", "canary-package", "canary-password",
      "canary-cookie",
    ] {
      #expect(!text.contains(forbidden))
    }
    #expect(!(BranchDiscoveryReceipt.self is any Decodable.Type))
  }

  @Test
  func rejectsResponseIdentityStatusAndHeaders() async throws {
    let cases: [(Int, URL?, [String: String], ManifestSamplingError)] = [
      (500, nil, ["Content-Type": "application/json"], .statusRejected),
      (
        200, URL(string: "https://example.invalid/wrong")!, ["Content-Type": "application/json"],
        .responseIdentityMismatch
      ),
      (200, nil, ["Content-Type": "text/html"], .contentTypeRejected),
      (
        200, nil, ["Content-Type": "application/json", "Content-Encoding": "gzip"],
        .contentEncodingRejected
      ),
      (
        200, nil, ["Content-Type": "text/html", "Content-Encoding": "gzip"],
        .contentTypeAndEncodingRejected
      ),
      (
        200, nil, ["Content-Type": "text/html", "Content-Length": "bad"],
        .contentTypeAndLengthRejected
      ),
      (
        200, nil,
        ["Content-Type": "application/json", "Content-Encoding": "gzip", "Content-Length": "bad"],
        .contentEncodingAndLengthRejected
      ),
      (
        200, nil,
        ["Content-Type": "text/html", "Content-Encoding": "gzip", "Content-Length": "bad"],
        .contentTypeEncodingAndLengthRejected
      ),
    ]
    for (index, item) in cases.enumerated() {
      SamplingMockURLProtocol.reset()
      SamplingMockURLProtocol.handler = { request in
        .response(
          mockHTTPResponse(
            request: request,
            url: item.1,
            status: item.0,
            headers: item.2
          ),
          validBranchBody(),
          chunkSize: nil
        )
      }
      let client = BranchDiscoveryClient(
        configuration: samplingConfiguration(SamplingMockURLProtocol.self))
      await #expect(throws: item.3, Comment(rawValue: "case \(index)")) {
        try await sample(client)
      }
    }
  }

  @Test
  func enforcesStreamingCapAndContentLength() async throws {
    SamplingMockURLProtocol.reset()
    let oversized = Data(
      repeating: 0x20, count: Int(BranchDiscoveryClient.maximumResponseBytes + 1))
    SamplingMockURLProtocol.handler = { request in
      .response(
        mockHTTPResponse(
          request: request,
          headers: ["Content-Type": "application/json"]
        ),
        oversized,
        chunkSize: 64 * 1_024
      )
    }
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingMockURLProtocol.self))
    await #expect(throws: ManifestSamplingError.oversized) { try await sample(client) }

    SamplingMockURLProtocol.reset()
    let body = validBranchBody()
    SamplingMockURLProtocol.handler = { request in
      .response(
        mockHTTPResponse(
          request: request,
          headers: [
            "Content-Type": "application/json", "Content-Length": "\(body.count + 1)",
          ]
        ),
        body,
        chunkSize: nil
      )
    }
    await #expect(throws: ManifestSamplingError.contentLengthRejected) {
      try await sample(client)
    }

    for rawLength in ["0", "01", "abc", "1,1"] {
      SamplingMockURLProtocol.reset()
      SamplingMockURLProtocol.handler = { request in
        .response(
          mockHTTPResponse(
            request: request,
            headers: [
              "Content-Type": "application/json", "Content-Length": rawLength,
            ]
          ),
          body,
          chunkSize: nil
        )
      }
      await #expect(throws: ManifestSamplingError.contentLengthRejected) {
        try await sample(client)
      }
    }

    SamplingMockURLProtocol.reset()
    SamplingMockURLProtocol.handler = { request in
      .response(
        mockHTTPResponse(
          request: request,
          headers: ["Content-Type": "application/json", "Content-Length": "1048577"]
        ),
        body,
        chunkSize: nil
      )
    }
    await #expect(throws: ManifestSamplingError.oversized) {
      try await sample(client)
    }
  }

  @Test
  func rejectsRedirectAndDoesNotRetryTransportFailure() async throws {
    SamplingMockURLProtocol.reset()
    SamplingMockURLProtocol.handler = { request in
      let response = mockHTTPResponse(
        request: request,
        status: 302,
        headers: ["Location": "https://example.invalid/redirect"]
      )
      return .redirect(
        response,
        URLRequest(url: URL(string: "https://example.invalid/redirect")!)
      )
    }
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingMockURLProtocol.self))
    await #expect(throws: ManifestSamplingError.redirectRejected) { try await sample(client) }
    #expect(SamplingMockURLProtocol.counts.start == 1)

    SamplingMockURLProtocol.reset()
    SamplingMockURLProtocol.handler = { _ in .failure(URLError(.timedOut)) }
    await #expect(throws: ManifestSamplingError.transportFailure) { try await sample(client) }
    #expect(SamplingMockURLProtocol.counts.start == 1)
  }

  @Test
  func cancellationStopsSingleTask() async throws {
    SamplingMockURLProtocol.reset()
    SamplingMockURLProtocol.handler = { _ in .block }
    let client = BranchDiscoveryClient(
      configuration: samplingConfiguration(SamplingMockURLProtocol.self))
    let task = Task { try await sample(client) }
    for _ in 0..<100 where SamplingMockURLProtocol.counts.start == 0 {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(SamplingMockURLProtocol.counts.start == 1)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    for _ in 0..<100 where SamplingMockURLProtocol.counts.stop == 0 {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(SamplingMockURLProtocol.counts.stop > 0)
  }

  @Test
  func configurationAndAuthenticationPoliciesAreClosed() {
    let configuration = BranchDiscoveryClient.makeSessionConfiguration(.default)
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.httpAdditionalHeaders == nil)
    #expect(!configuration.httpShouldSetCookies)
    #expect(!configuration.waitsForConnectivity)
    #expect(configuration.httpMaximumConnectionsPerHost == 1)
    #expect(configuration.tlsMinimumSupportedProtocolVersion == .TLSv12)
    #expect(
      BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodServerTrust,
        host: "hyp-api.mihoyo.com",
        protocolName: "https",
        port: 443,
        previousFailureCount: 0
      ))
    #expect(
      !BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
        host: "hyp-api.mihoyo.com",
        protocolName: "https",
        port: 443,
        previousFailureCount: 0
      ))
    #expect(
      !BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodServerTrust,
        host: "example.invalid",
        protocolName: "https",
        port: 443,
        previousFailureCount: 0
      ))
    #expect(
      !BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodServerTrust,
        host: "hyp-api.mihoyo.com",
        protocolName: "https",
        port: 443,
        previousFailureCount: 1
      ))
    #expect(
      !BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodServerTrust,
        host: "hyp-api.mihoyo.com",
        protocolName: "http",
        port: 443,
        previousFailureCount: 0
      ))
    #expect(
      !BranchDiscoveryAuthenticationPolicy.allowsDefaultHandling(
        authenticationMethod: NSURLAuthenticationMethodServerTrust,
        host: "hyp-api.mihoyo.com",
        protocolName: "https",
        port: 80,
        previousFailureCount: 0
      ))
    #expect(ManifestSamplingError.contentTypeRejected.safeCode == "content-type-rejected")
    #expect(
      ManifestSamplingError.contentEncodingRejected.safeCode == "content-encoding-rejected")
    #expect(ManifestSamplingError.contentLengthRejected.safeCode == "content-length-rejected")
    #expect(
      ManifestSamplingError.contentTypeAndEncodingRejected.safeCode
        == "content-type-and-encoding-rejected")
    #expect(
      ManifestSamplingError.contentTypeEncodingAndLengthRejected.safeCode
        == "content-type-encoding-and-length-rejected")
  }

  @Test
  func rejectsInvalidObservationTimesAndRedactsCapabilities() async throws {
    for (index, value) in [
      -1.0, Double.infinity, Double.nan, 253_402_300_800,
    ].enumerated() {
      SamplingMockURLProtocol.reset()
      SamplingMockURLProtocol.handler = { request in
        .response(mockHTTPResponse(request: request), validBranchBody(), chunkSize: nil)
      }
      let client = BranchDiscoveryClient(
        configuration: samplingConfiguration(SamplingMockURLProtocol.self),
        now: { Date(timeIntervalSince1970: value) }
      )
      await #expect(
        throws: ManifestSamplingError.transportFailure, Comment(rawValue: "time \(index)")
      ) {
        try await sample(client)
      }
      var dumped = ""
      dump(client, to: &dumped)
      #expect(dumped.contains("redacted"))
      #expect(!dumped.contains("mihoyo"))
    }

    var planDump = ""
    dump(BranchDiscoveryClient.plan(), to: &planDump)
    #expect(planDump.contains("redacted"))
    var errorDump = ""
    dump(ManifestSamplingError.transportFailure, to: &errorDump)
    #expect(errorDump.contains("redacted"))
  }

  private func sample(_ client: BranchDiscoveryClient) async throws -> BranchDiscoveryReceipt {
    try await client.sampleCN(
      acknowledgedPlanSHA256: BranchDiscoveryClient.plan().policySHA256,
      networkGate: BranchDiscoveryClient.requiredNetworkGate
    )
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
