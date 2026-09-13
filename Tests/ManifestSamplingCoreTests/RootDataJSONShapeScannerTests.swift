import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

struct RootDataJSONShapeScannerTests {
  @Test
  func scansRootDataWithoutRequiringBranchArrayAndMatchesKnownVector() throws {
    let input = data(
      #"{"retcode":0,"message":"secret-value","data":{"tag":"tag-secret","manifests":[{"matching_field":"game"}]}}"#
    )
    let shape = try StrictJSONSchemaScanner.scanRootData(
      input,
      reportLimits: .standard
    )
    let report = try #require(shape.safeReport)
    let text = String(
      decoding: try ManifestSamplingCanonicalJSON.encode(report.root),
      as: UTF8.self
    )

    #expect(shape.policyVersion == 1)
    #expect(shape.sha256 == "141247612e305690c6b31b4b11a6358ace4664a31b3de24ff955eeedaac26f90")
    #expect(report.sha256 == "240a5697a684e84fcc1b14e99dd8f1fb3849447c26cb30b032f4b08e6f1cfd0b")
    #expect(report.canonicalByteSize == 620)
    #expect(text.contains(#""name":"tag""#))
    #expect(text.contains(sha256(Data("manifests".utf8))))
    #expect(text.contains(sha256(Data("matching_field".utf8))))
    #expect(!text.contains("secret-value"))
    #expect(!text.contains("tag-secret"))
    #expect(!text.contains("manifests"))
    #expect(!(JSONRootDataValueFreeShape.self is any Decodable.Type))
  }

  @Test
  func rejectsMissingOrInvalidRootDataAnchors() {
    let candidates = [
      #"{"message":"ok","data":{}}"#,
      #"{"retcode":1,"data":{}}"#,
      #"{"retcode":0}"#,
      #"{"retcode":0,"data":[]}"#,
      #"{"retcode":0,"retcode":0,"data":{}}"#,
    ]
    for candidate in candidates {
      #expect(throws: (any Error).self) {
        try StrictJSONSchemaScanner.scanRootData(data(candidate))
      }
    }
  }

  @Test
  func rootDataReportPreservesCancellationAndValueFreeDeterminism() throws {
    let first = data(
      #"{"retcode":0,"message":"one","data":{"tag":"short","future":[1,1]}}"#
    )
    let changed = data(
      #"{"data":{"future":[999],"tag":"a much longer secret"},"message":"another","retcode":0}"#
    )
    let firstShape = try StrictJSONSchemaScanner.scanRootData(
      first,
      reportLimits: .standard
    )
    let changedShape = try StrictJSONSchemaScanner.scanRootData(
      changed,
      reportLimits: .standard
    )
    #expect(firstShape.sha256 == changedShape.sha256)
    #expect(firstShape.safeReport?.sha256 == changedShape.safeReport?.sha256)

    let probe = RootDataCancellationProbe(cancelOnCall: 2)
    #expect(throws: CancellationError.self) {
      try StrictJSONSchemaScanner.scanRootData(
        first,
        reportLimits: .standard,
        cancellationCheck: probe.check
      )
    }
  }

  @Test
  func enforcesIndependentEightMiBInputBoundary() throws {
    let base = data(#"{"retcode":0,"data":{}}"#)
    var exact = base
    exact.append(
      Data(
        repeating: 0x20,
        count: StrictJSONSchemaScanner.maximumRootDataInputBytes - base.count
      )
    )
    #expect(try StrictJSONSchemaScanner.scanRootData(exact).sha256.count == 64)
    exact.append(0x20)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scanRootData(exact)
    }
  }
}

private func data(_ value: String) -> Data {
  Data(value.utf8)
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class RootDataCancellationProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let cancelOnCall: Int
  private var calls = 0

  init(cancelOnCall: Int) {
    self.cancelOnCall = cancelOnCall
  }

  func check() throws {
    lock.lock()
    defer { lock.unlock() }
    calls += 1
    if calls == cancelOnCall { throw CancellationError() }
  }
}
