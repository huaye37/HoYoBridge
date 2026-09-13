import Foundation

@testable import ManifestSamplingCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class SamplingMockURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> SamplingMockResult)?
  nonisolated(unsafe) static var startCount = 0
  nonisolated(unsafe) static var stopCount = 0

  static func reset() {
    lock.lock()
    handler = nil
    startCount = 0
    stopCount = 0
    lock.unlock()
  }

  static var counts: (start: Int, stop: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (startCount, stopCount)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    Self.startCount += 1
    let handler = Self.handler
    Self.lock.unlock()
    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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

  override func stopLoading() {
    Self.lock.lock()
    Self.stopCount += 1
    Self.lock.unlock()
  }
}

enum SamplingMockResult: @unchecked Sendable {
  case response(HTTPURLResponse, Data, chunkSize: Int?)
  case redirect(HTTPURLResponse, URLRequest)
  case failure(any Error)
  case block
}

final class SamplingTripwireURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var starts = 0

  static func reset() {
    lock.lock()
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
    Self.lock.unlock()
    client?.urlProtocol(self, didFailWithError: URLError(.dataNotAllowed))
  }

  override func stopLoading() {}
}

func samplingConfiguration(_ protocolClass: AnyClass) -> URLSessionConfiguration {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [protocolClass]
  return configuration
}

func validBranchBody() -> Data {
  Data(
    #"{"retcode":0,"data":{"game_branches":[{"main":{"tag":"canary-tag","branch":"canary-branch","package_id":"canary-package","password":"canary-password"}}]}}"#
      .utf8
  )
}

func mockHTTPResponse(
  request: URLRequest,
  url: URL? = nil,
  status: Int = 200,
  headers: [String: String] = ["Content-Type": "application/json"]
) -> HTTPURLResponse {
  HTTPURLResponse(
    url: url ?? request.url!,
    statusCode: status,
    httpVersion: "HTTP/1.1",
    headerFields: headers
  )!
}
