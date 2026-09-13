import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

@Suite(.serialized)
struct ManagedArtifactDownloaderTests {
  @Test
  func downloadsVerifiesAndStoresFreshArtifact() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data("downloaded runtime".utf8)
      let runtime = runtime(for: data)
      let downloader = downloader(in: directory) { request in
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
        return response(for: request, status: 200, data: data)
      }

      let result = try await downloader.download(
        runtime: runtime,
        into: ContentAddressedArtifactStore(
          rootURL: directory.appendingPathComponent("cache", isDirectory: true)
        )
      )

      #expect(result.disposition == .stored)
      #expect(try Data(contentsOf: result.url) == data)
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  @Test
  func streamsMultipleTransportChunks() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data(repeating: 0x5A, count: 4_097)
      let runtime = runtime(for: data)
      let downloader = downloader(in: directory) { request in
        response(for: request, status: 200, data: data)
      }
      MockURLProtocol.chunkSize = 17

      let result = try await downloader.download(
        runtime: runtime,
        into: .init(rootURL: directory.appendingPathComponent("cache"))
      )

      #expect(try Data(contentsOf: result.url) == data)
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  @Test
  func interruptedTransferCheckpointsThenResumesWithStrict206() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data(repeating: 0x41, count: 32_769)
      let sourceURL = "https://downloads.example.invalid/runtime.bin?token=do-not-store"
      let runtime = runtime(for: data, sourceURL: sourceURL)
      let downloader = resumableDownloader(in: directory, data: data) {
        request, prefixCount in
        #expect(request.value(forHTTPHeaderField: "Range") == "bytes=\(prefixCount)-")
        #expect(request.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        let remaining = Data(data.dropFirst(prefixCount))
        return self.response(
          for: request,
          status: 206,
          data: remaining,
          headers: [
            "Content-Range": "bytes \(prefixCount)-\(data.count - 1)/\(data.count)",
            "ETag": "\"v1\"",
          ]
        )
      }

      await expectInitialInterruption(
        downloader: downloader,
        runtime: runtime,
        directory: directory
      )
      let entries = try partialEntries(in: directory).sorted()
      #expect(entries == ["\(digest(data)).part", "\(digest(data)).resume.json"])
      let metadata = try String(
        contentsOf: directory.appendingPathComponent(
          "downloads/.partial/\(digest(data)).resume.json"
        ),
        encoding: .utf8
      )
      #expect(!metadata.contains(sourceURL))
      #expect(!metadata.contains("do-not-store"))

      let result = try await downloader.download(
        runtime: runtime,
        into: .init(rootURL: directory.appendingPathComponent("cache"))
      )
      #expect(try Data(contentsOf: result.url) == data)
      #expect((try? partialEntries(in: directory)) == [])
    }
  }

  @Test
  func resumeReceiving200TruncatesBeforeWritingFreshBody() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data(repeating: 0x42, count: 32_769)
      let runtime = runtime(for: data)
      let downloader = resumableDownloader(in: directory, data: data) { request, _ in
        #expect(request.value(forHTTPHeaderField: "Range") != nil)
        return self.response(
          for: request,
          status: 200,
          data: data,
          headers: ["ETag": "\"v2\""]
        )
      }

      await expectInitialInterruption(
        downloader: downloader,
        runtime: runtime,
        directory: directory
      )
      let result = try await downloader.download(
        runtime: runtime,
        into: .init(rootURL: directory.appendingPathComponent("cache"))
      )

      #expect(try Data(contentsOf: result.url) == data)
      #expect((try? partialEntries(in: directory)) == [])
    }
  }

  @Test
  func rejectsBadContentRangeAndDeletesResumeState() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data(repeating: 0x43, count: 32_769)
      let runtime = runtime(for: data)
      let downloader = resumableDownloader(in: directory, data: data) {
        request, prefixCount in
        let remaining = Data(data.dropFirst(prefixCount))
        return self.response(
          for: request,
          status: 206,
          data: remaining,
          headers: [
            "Content-Range": "bytes \(prefixCount + 1)-\(data.count - 1)/\(data.count)",
            "ETag": "\"v1\"",
          ]
        )
      }
      await expectInitialInterruption(
        downloader: downloader,
        runtime: runtime,
        directory: directory
      )

      var rejectedBadRange = false
      do {
        _ = try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache"))
        )
      } catch let error as ManagedArtifactDownloadError {
        if case .invalidContentRange = error { rejectedBadRange = true }
      }
      #expect(rejectedBadRange)
      #expect((try? partialEntries(in: directory)) == [])
    }
  }

  @Test
  func rejectsChangedResumeValidatorAndDeletesResumeState() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data(repeating: 0x44, count: 32_769)
      let runtime = runtime(for: data)
      let downloader = resumableDownloader(in: directory, data: data) {
        request, prefixCount in
        let remaining = Data(data.dropFirst(prefixCount))
        return self.response(
          for: request,
          status: 206,
          data: remaining,
          headers: [
            "Content-Range": "bytes \(prefixCount)-\(data.count - 1)/\(data.count)",
            "ETag": "\"v2\"",
          ]
        )
      }
      await expectInitialInterruption(
        downloader: downloader,
        runtime: runtime,
        directory: directory
      )

      await #expect(throws: ManagedArtifactDownloadError.resumeValidatorChanged) {
        try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache"))
        )
      }
      #expect((try? partialEntries(in: directory)) == [])
    }
  }

  @Test
  func concurrentSameArtifactFailsFastOnKernelLease() async throws {
    try await withTemporaryDirectory { directory in
      BlockingURLProtocol.reset()
      let data = Data("one artifact one active transfer".utf8)
      let runtime = runtime(for: data)
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [BlockingURLProtocol.self]
      let downloader = ManagedArtifactDownloader(
        downloadRootURL: directory.appendingPathComponent("downloads", isDirectory: true),
        allowedHosts: ["downloads.example.invalid"],
        configuration: configuration,
        capacitySafetyMarginBytes: 0,
        capacityProvider: testCapacityProvider
      )
      let first = Task {
        try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache-a"))
        )
      }
      for _ in 0..<1_000 where !BlockingURLProtocol.hasStarted {
        try await Task.sleep(for: .milliseconds(1))
      }
      #expect(BlockingURLProtocol.hasStarted)

      await #expect(throws: ManagedArtifactDownloadError.artifactBusy(digest(data))) {
        try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache-b"))
        )
      }
      first.cancel()
      await #expect(throws: CancellationError.self) { try await first.value }
      #expect(try partialEntries(in: directory).isEmpty)
    }
  }

  @Test
  func rejectsUnexpectedStatusAndCleansPartial() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data("not found".utf8)
      let runtime = runtime(for: data)
      let downloader = downloader(in: directory) { request in
        response(for: request, status: 404, data: data)
      }

      await #expect(throws: ManagedArtifactDownloadError.unexpectedStatus(404)) {
        try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache"))
        )
      }
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  @Test
  func rejectsWrongContentLengthAndEncoding() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data("expected".utf8)
      let runtime = runtime(for: data)

      let short = downloader(in: directory) { request in
        response(
          for: request,
          status: 200,
          data: data,
          headers: ["Content-Length": "1"]
        )
      }
      await #expect(throws: ManagedArtifactDownloadError.invalidContentLength("1")) {
        try await short.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache-a"))
        )
      }

      let encoded = downloader(in: directory) { request in
        response(
          for: request,
          status: 200,
          data: data,
          headers: ["Content-Encoding": "gzip"]
        )
      }
      await #expect(throws: ManagedArtifactDownloadError.unsupportedContentEncoding("gzip")) {
        try await encoded.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache-b"))
        )
      }
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  @Test
  func rejectsHashMismatchAndCleansPartial() async throws {
    try await withTemporaryDirectory { directory in
      let expected = Data("expected".utf8)
      let changed = Data("changedd".utf8)
      let runtime = runtime(for: expected)
      let downloader = downloader(in: directory) { request in
        response(for: request, status: 200, data: changed)
      }

      await #expect(
        throws: ArtifactVerificationError.hashMismatch(
          expected: digest(expected),
          actual: digest(changed)
        )
      ) {
        try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache"))
        )
      }
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  @Test
  func rejectsShortAndOversizedBodies() async throws {
    try await withTemporaryDirectory { directory in
      let expected = Data("expected".utf8)
      let runtime = runtime(for: expected)

      let shortBody = Data(expected.dropLast())
      let short = downloader(in: directory) { request in
        response(
          for: request,
          status: 200,
          data: shortBody,
          headers: ["Content-Length": String(expected.count)]
        )
      }
      var shortFailed = false
      do {
        _ = try await short.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache-short"))
        )
      } catch {
        shortFailed = true
      }
      #expect(shortFailed)

      let oversizedBody = expected + Data([0])
      let oversized = downloader(in: directory) { request in
        response(
          for: request,
          status: 200,
          data: oversizedBody,
          headers: ["Content-Length": String(expected.count)]
        )
      }
      var oversizedFailed = false
      do {
        _ = try await oversized.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache-oversized"))
        )
      } catch {
        oversizedFailed = true
      }
      #expect(oversizedFailed)

      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  @Test
  func rejectsUnsafeInitialAndRedirectURLs() throws {
    let policy = DownloadURLPolicy(
      allowedHosts: ["downloads.example.invalid", "cdn.example.invalid"],
      maximumRedirects: 3
    )

    #expect(throws: ManagedArtifactDownloadError.disallowedURL("http://downloads.example.invalid"))
    {
      try policy.validate(URL(string: "http://downloads.example.invalid/file")!)
    }
    #expect(throws: ManagedArtifactDownloadError.disallowedURL("https://localhost")) {
      try DownloadURLPolicy(allowedHosts: ["localhost"], maximumRedirects: 3)
        .validate(URL(string: "https://localhost/file")!)
    }
    #expect(throws: ManagedArtifactDownloadError.disallowedURL("https://127.0.0.1")) {
      try DownloadURLPolicy(allowedHosts: ["127.0.0.1"], maximumRedirects: 3)
        .validate(URL(string: "https://127.0.0.1/file")!)
    }
    #expect(throws: ManagedArtifactDownloadError.disallowedURL("https://evil.example.invalid")) {
      try policy.validate(URL(string: "https://evil.example.invalid/file")!)
    }
    #expect(
      throws: ManagedArtifactDownloadError.redirectRejected("http://downloads.example.invalid")
    ) {
      try policy.validateRedirect(
        URL(string: "http://downloads.example.invalid/file")!,
        number: 1
      )
    }
    #expect(
      throws: ManagedArtifactDownloadError.redirectRejected("https://evil.example.invalid")
    ) {
      try policy.validateRedirect(
        URL(string: "https://evil.example.invalid/file")!,
        number: 1
      )
    }
    #expect(throws: ManagedArtifactDownloadError.tooManyRedirects(3)) {
      try policy.validateRedirect(
        URL(string: "https://cdn.example.invalid/file")!,
        number: 4
      )
    }

    for rawURL in [
      "https://127.1/file",
      "https://127.0.1/file",
      "https://0x7f.0.0.1/file",
      "https://localhost./file",
      "https://foo.local./file",
    ] {
      let url = URL(string: rawURL)!
      let localPolicy = DownloadURLPolicy(
        allowedHosts: [url.host!],
        maximumRedirects: 3
      )
      #expect(
        throws: ManagedArtifactDownloadError.disallowedURL(
          DownloadURLPolicy.redactedOrigin(url)
        )
      ) {
        try localPolicy.validate(url)
      }
    }
  }

  @Test
  func redirectDelegateAppliesPolicyAndPreservesIdentityEncoding() throws {
    let sourceURL = URL(string: "https://downloads.example.invalid/runtime.bin")!
    let response = HTTPURLResponse(
      url: sourceURL,
      statusCode: 302,
      httpVersion: "HTTP/1.1",
      headerFields: nil
    )!
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: sourceURL)
    let policy = DownloadURLPolicy(
      allowedHosts: ["downloads.example.invalid", "cdn.example.invalid"],
      maximumRedirects: 3
    )

    let allowedDelegate = RedirectDelegate(
      policy: policy,
      rangeHeader: "bytes=4-",
      ifRangeHeader: "\"v1\""
    )
    let allowedBox = LockedRequestBox()
    var allowed = URLRequest(url: URL(string: "https://cdn.example.invalid/runtime.bin")!)
    allowed.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
    allowedDelegate.urlSession(
      session,
      task: task,
      willPerformHTTPRedirection: response,
      newRequest: allowed
    ) { allowedBox.set($0) }
    #expect(allowedBox.value?.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
    #expect(allowedBox.value?.value(forHTTPHeaderField: "Range") == "bytes=4-")
    #expect(allowedBox.value?.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
    #expect(allowedDelegate.rejection == nil)

    let rejectedDelegate = RedirectDelegate(policy: policy)
    let rejectedBox = LockedRequestBox()
    rejectedDelegate.urlSession(
      session,
      task: task,
      willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: URL(string: "http://cdn.example.invalid/runtime.bin")!)
    ) { rejectedBox.set($0) }
    #expect(rejectedBox.value == nil)
    #expect(
      rejectedDelegate.rejection
        == .redirectRejected("http://cdn.example.invalid")
    )

    let cappedDelegate = RedirectDelegate(
      policy: .init(allowedHosts: ["cdn.example.invalid"], maximumRedirects: 0)
    )
    let cappedBox = LockedRequestBox()
    cappedDelegate.urlSession(
      session,
      task: task,
      willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: URL(string: "https://cdn.example.invalid/runtime.bin")!)
    ) { cappedBox.set($0) }
    #expect(cappedBox.value == nil)
    #expect(cappedDelegate.rejection == .tooManyRedirects(0))
  }

  @Test
  func byteCounterReportsExactShortAndOversizedErrors() throws {
    var short = DownloadByteCounter(expectedSize: 2)
    try short.consume()
    #expect(
      throws: ManagedArtifactDownloadError.sizeMismatch(expected: 2, actual: 1)
    ) {
      try short.finish()
    }

    var full = DownloadByteCounter(expectedSize: 1)
    try full.consume()
    try full.finish()
    #expect(throws: ManagedArtifactDownloadError.sizeExceeded(expected: 1)) {
      try full.consume()
    }
  }

  @Test
  func rangeParserRejectsOverflowAndMultipleRanges() {
    #expect(
      ManagedArtifactDownloader.parseContentRange(
        "bytes 0-1/18446744073709551616"
      ) == nil
    )
    #expect(
      ManagedArtifactDownloader.parseContentRange("bytes 0-1/4, 2-3/4") == nil
    )
  }

  @Test
  func weakETagAndWeakLastModifiedCannotCheckpoint() {
    #expect(!ManagedArtifactDownloader.isStrongETag("W/\"v1\""))
    #expect(ManagedArtifactDownloader.isStrongETag("\"v1\""))

    let url = URL(string: "https://downloads.example.invalid/runtime.bin")!
    let weakDate = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Date": "Wed, 19 Aug 2026 04:00:59 GMT"]
    )!
    let strongDate = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Date": "Wed, 19 Aug 2026 04:01:00 GMT"]
    )!
    let lastModified = "Wed, 19 Aug 2026 04:00:00 GMT"

    #expect(!ManagedArtifactDownloader.isStrongLastModified(lastModified, in: weakDate))
    #expect(ManagedArtifactDownloader.isStrongLastModified(lastModified, in: strongDate))
  }

  @Test
  func cancelledDownloadCreatesNoPartialOrFinal() async throws {
    try await withTemporaryDirectory { directory in
      let data = Data("cancelled".utf8)
      let runtime = runtime(for: data)
      let downloader = downloader(in: directory) { request in
        response(for: request, status: 200, data: data)
      }
      let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        return try await downloader.download(
          runtime: runtime,
          into: .init(rootURL: directory.appendingPathComponent("cache"))
        )
      }
      task.cancel()

      await #expect(throws: CancellationError.self) { try await task.value }
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
      let cachePath = directory.appendingPathComponent("cache").path
      #expect(!FileManager.default.fileExists(atPath: cachePath))
    }
  }

  @Test
  func inFlightCancellationStopsTransportAndCleansPartial() async throws {
    try await withTemporaryDirectory { directory in
      BlockingURLProtocol.reset()
      let data = Data("in-flight".utf8)
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [BlockingURLProtocol.self]
      let downloader = ManagedArtifactDownloader(
        downloadRootURL: directory.appendingPathComponent("downloads", isDirectory: true),
        allowedHosts: ["downloads.example.invalid"],
        configuration: configuration,
        capacitySafetyMarginBytes: 0,
        capacityProvider: testCapacityProvider
      )
      let task = Task {
        try await downloader.download(
          runtime: runtime(for: data),
          into: .init(rootURL: directory.appendingPathComponent("cache"))
        )
      }

      for _ in 0..<1_000 where !BlockingURLProtocol.hasStarted {
        try await Task.sleep(for: .milliseconds(1))
      }
      #expect(BlockingURLProtocol.hasStarted)
      task.cancel()
      await #expect(throws: CancellationError.self) { try await task.value }
      for _ in 0..<1_000 where !BlockingURLProtocol.wasStopped {
        try await Task.sleep(for: .milliseconds(1))
      }
      #expect(BlockingURLProtocol.wasStopped)
      let entries = try partialEntries(in: directory)
      #expect(entries.isEmpty)
    }
  }

  private func downloader(
    in directory: URL,
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  ) -> ManagedArtifactDownloader {
    MockURLProtocol.handler = handler
    MockURLProtocol.chunkSize = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return ManagedArtifactDownloader(
      downloadRootURL: directory.appendingPathComponent("downloads", isDirectory: true),
      allowedHosts: ["downloads.example.invalid"],
      configuration: configuration,
      capacitySafetyMarginBytes: 0,
      capacityProvider: testCapacityProvider
    )
  }

  private var testCapacityProvider: DownloadCapacityProvider {
    DownloadCapacityProvider { _ in
      DownloadFileSystemCapacity(
        deviceID: 1,
        availableBlocks: 1_000_000_000_000,
        blockSize: 1
      )
    }
  }

  private func resumableDownloader(
    in directory: URL,
    data: Data,
    resumeHandler:
      @escaping @Sendable (URLRequest, Int) throws -> (
        HTTPURLResponse, Data
      )
  ) -> ManagedArtifactDownloader {
    let downloader = downloader(in: directory) { request in
      if request.value(forHTTPHeaderField: "Range") == nil {
        return self.response(
          for: request,
          status: 200,
          data: data,
          headers: [
            "Content-Length": String(data.count),
            "ETag": "\"v1\"",
          ]
        )
      }
      let range = request.value(forHTTPHeaderField: "Range")!
      let prefixCount = Int(range.dropFirst("bytes=".count).dropLast())!
      MockURLProtocol.chunkSize = nil
      return try resumeHandler(request, prefixCount)
    }
    MockURLProtocol.chunkSize = 1
    return downloader
  }

  private func expectInitialInterruption(
    downloader: ManagedArtifactDownloader,
    runtime: RuntimeDefinition,
    directory: URL
  ) async {
    let task = Task {
      try await downloader.download(
        runtime: runtime,
        into: .init(rootURL: directory.appendingPathComponent("cache-first"))
      )
    }
    let partialURL = directory.appendingPathComponent(
      "downloads/.partial/\(runtime.sha256!).part"
    )
    var partialSize: UInt64 = 0
    for _ in 0..<2_000 where partialSize == 0 {
      if let attributes = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
        let size = attributes[.size] as? NSNumber
      {
        partialSize = size.uint64Value
      }
      if partialSize == 0 { try? await Task.sleep(for: .milliseconds(1)) }
    }
    #expect(partialSize > 0 && partialSize < runtime.byteSize!)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  private func runtime(
    for data: Data,
    sourceURL: String = "https://downloads.example.invalid/runtime.bin"
  ) -> RuntimeDefinition {
    RuntimeDefinition(
      id: "download-runtime",
      backend: .dxmt,
      version: "1.0.0",
      verification: .candidate,
      acquisition: .managedDownload,
      sourceURL: sourceURL,
      byteSize: UInt64(data.count),
      sha256: digest(data),
      license: "MIT",
      redistributable: true
    )
  }

  private func response(
    for request: URLRequest,
    status: Int,
    data: Data,
    headers: [String: String] = [:]
  ) -> (HTTPURLResponse, Data) {
    var responseHeaders = ["Content-Length": String(data.count)]
    responseHeaders.merge(headers) { _, replacement in replacement }
    return (
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: responseHeaders
      )!,
      data
    )
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func partialEntries(in directory: URL) throws -> [String] {
    let partial = directory.appendingPathComponent("downloads/.partial", isDirectory: true)
    guard FileManager.default.fileExists(atPath: partial.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: partial.path)
  }

  private func withTemporaryDirectory<T>(
    _ body: (URL) async throws -> T
  ) async throws -> T {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacGameBridgeDownloadTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
  }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var chunkSize: Int?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      if let chunkSize = Self.chunkSize, chunkSize > 0 {
        for offset in stride(from: 0, to: data.count, by: chunkSize) {
          let end = min(offset + chunkSize, data.count)
          client?.urlProtocol(self, didLoad: data.subdata(in: offset..<end))
        }
      } else {
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class BlockingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var started = false
  nonisolated(unsafe) private static var stopped = false

  static var hasStarted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return started
  }

  static var wasStopped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }

  static func reset() {
    lock.lock()
    started = false
    stopped = false
    lock.unlock()
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.started = true
    Self.lock.unlock()
  }

  override func stopLoading() {
    Self.lock.lock()
    Self.stopped = true
    Self.lock.unlock()
  }
}

private final class LockedRequestBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: URLRequest?

  var value: URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }

  func set(_ value: URLRequest?) {
    lock.lock()
    storedValue = value
    lock.unlock()
  }
}
