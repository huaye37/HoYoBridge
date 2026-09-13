import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

struct SafeJSONShapeReportTests {
  @Test
  func matchesCanonicalKnownVectorWithoutExposingValues() throws {
    let unknownKey = "future-key-canary"
    let secretValue = "secret-value-canary"
    let input = data(
      """
      {"retcode":0,"message":"\(secretValue)","data":{"game_branches":[{"main":{"tag":"a","branch":"b","package_id":"c","password":"d"},"\(unknownKey)":true}]}}
      """
    )

    let shape = try StrictJSONSchemaScanner.scan(
      input,
      reportLimits: .standard
    )
    let report = try #require(shape.safeReport)
    let canonical = try ManifestSamplingCanonicalJSON.encode(report.root)
    let text = String(decoding: canonical, as: UTF8.self)
    let unknownDigest = sha256(Data(unknownKey.utf8))

    #expect(report.policyVersion == 1)
    #expect(
      SafeJSONShapeReportPolicyV1.knownKeyNames
        == SafeJSONShapeReportPolicyV1.knownKeyNames.sorted())
    #expect(report.canonicalByteSize == 843)
    #expect(report.canonicalByteSize == UInt64(canonical.count))
    #expect(report.sha256 == "ac0cf9aec292bf18212c55b1bead6c9d41783a8806dd60c1da87163ab07b0d13")
    #expect(text.contains(#""name":"main""#))
    #expect(text.contains(#""name":"password""#))
    #expect(text.contains(unknownDigest))
    #expect(!text.contains(unknownKey))
    #expect(!text.contains(secretValue))
    #expect(!(SafeJSONShapeReport.self is any Decodable.Type))
    #expect(!(SafeJSONShapeNode.self is any Decodable.Type))
    var dumped = ""
    dump(report, to: &dumped)
    dump(report.root, to: &dumped)
    #expect(dumped.contains("redacted"))
    #expect(!dumped.contains(unknownKey))
    #expect(!dumped.contains(secretValue))
  }

  @Test
  func ignoresValuesOrderAndMultiplicityButPreservesElementCorrelation() throws {
    let first = data(
      #"{"retcode":0,"message":"one","data":{"game_branches":[{"main":{"tag":"1"}},{"pre_download":null}]}}"#
    )
    let permuted = data(
      #"{"data":{"game_branches":[{"pre_download":null},{"main":{"tag":"a much longer secret"}},{"main":{"tag":"another value"}}]},"message":"a different length","retcode":0}"#
    )
    let merged = data(
      #"{"retcode":0,"message":"three","data":{"game_branches":[{"main":{"tag":"4"},"pre_download":null},{}]}}"#
    )

    let firstReport = try report(for: first)
    let permutedReport = try report(for: permuted)
    let mergedReport = try report(for: merged)
    #expect(firstReport.sha256 == permutedReport.sha256)
    #expect(firstReport.root == permutedReport.root)
    #expect(firstReport.sha256 != mergedReport.sha256)
  }

  @Test
  func hashesDecodedUnknownUnicodeKeysWithoutReturningTheirSpelling() throws {
    let rawKey = "未来字段"
    let raw = data(
      #"{"retcode":0,"data":{"game_branches":[]},"未来字段":null}"#
    )
    let escaped = data(
      #"{"retcode":0,"data":{"game_branches":[]},"\u672a\u6765\u5b57\u6bb5":null}"#
    )

    let rawReport = try report(for: raw)
    let escapedReport = try report(for: escaped)
    let encoded = try ManifestSamplingCanonicalJSON.encode(rawReport.root)
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(rawReport == escapedReport)
    #expect(text.contains(sha256(Data(rawKey.utf8))))
    #expect(!text.contains(rawKey))
    #expect(!text.contains("672a"))
  }

  @Test
  func enforcesEveryReportLimitWithoutReturningPartialOutput() throws {
    let base = data(#"{"retcode":0,"data":{"game_branches":[]}}"#)
    let exact = try report(
      for: base,
      limits: SafeJSONShapeReportLimits(
        maximumNodeCount: 4,
        maximumArrayElementShapes: 0,
        maximumUnknownKeyCount: 0,
        maximumCanonicalBytes: SafeJSONShapeReportLimits.standard.maximumCanonicalBytes
      )
    )
    #expect(exact.root.description == "<redacted>")

    #expect(throws: ManifestSamplingError.shapeReportLimit) {
      try report(
        for: base,
        limits: SafeJSONShapeReportLimits(
          maximumNodeCount: 3,
          maximumArrayElementShapes: 0,
          maximumUnknownKeyCount: 0,
          maximumCanonicalBytes: SafeJSONShapeReportLimits.standard.maximumCanonicalBytes
        )
      )
    }
    #expect(throws: ManifestSamplingError.shapeReportLimit) {
      try report(
        for: data(#"{"retcode":0,"data":{"game_branches":[null]}}"#),
        limits: SafeJSONShapeReportLimits(
          maximumNodeCount: 5,
          maximumArrayElementShapes: 0,
          maximumUnknownKeyCount: 0,
          maximumCanonicalBytes: SafeJSONShapeReportLimits.standard.maximumCanonicalBytes
        )
      )
    }
    #expect(throws: ManifestSamplingError.shapeReportLimit) {
      try report(
        for: data(#"{"retcode":0,"data":{"game_branches":[]},"unknown":null}"#),
        limits: SafeJSONShapeReportLimits(
          maximumNodeCount: 5,
          maximumArrayElementShapes: 0,
          maximumUnknownKeyCount: 0,
          maximumCanonicalBytes: SafeJSONShapeReportLimits.standard.maximumCanonicalBytes
        )
      )
    }

    let canonicalCount = Int(exact.canonicalByteSize)
    _ = try report(
      for: base,
      limits: SafeJSONShapeReportLimits(
        maximumNodeCount: 4,
        maximumArrayElementShapes: 0,
        maximumUnknownKeyCount: 0,
        maximumCanonicalBytes: canonicalCount
      )
    )
    #expect(throws: ManifestSamplingError.shapeReportLimit) {
      try report(
        for: base,
        limits: SafeJSONShapeReportLimits(
          maximumNodeCount: 4,
          maximumArrayElementShapes: 0,
          maximumUnknownKeyCount: 0,
          maximumCanonicalBytes: canonicalCount - 1
        )
      )
    }
    #expect(throws: ManifestSamplingError.shapeReportLimit) {
      try report(
        for: base,
        limits: SafeJSONShapeReportLimits(
          maximumNodeCount: SafeJSONShapeReportLimits.standard.maximumNodeCount + 1,
          maximumArrayElementShapes: 0,
          maximumUnknownKeyCount: 0,
          maximumCanonicalBytes: canonicalCount
        )
      )
    }
  }

  @Test
  func defaultScanDoesNotIssueAReportAndConcurrentReportsAreDeterministic() async throws {
    let input = data(#"{"retcode":0,"data":{"game_branches":[{"main":null}]}}"#)
    #expect(try StrictJSONSchemaScanner.scan(input).safeReport == nil)

    let reports = try await withThrowingTaskGroup(of: SafeJSONShapeReport.self) { group in
      for _ in 0..<16 {
        group.addTask { try report(for: input) }
      }
      var values: [SafeJSONShapeReport] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(Set(reports.map(\.sha256)).count == 1)
  }

  @Test
  func reportConstructionPreservesCancellation() throws {
    let input = data(#"{"retcode":0,"data":{"game_branches":[{"main":null}]}}"#)
    let baseline = try report(for: input)
    let probe = ShapeReportCancellationProbe(cancelOnCall: 2)

    #expect(throws: CancellationError.self) {
      try SafeJSONShapeReportPolicyV1.make(
        root: baseline.root,
        limits: .standard,
        cancellationCheck: probe.check
      )
    }
  }
}

private func report(
  for input: Data,
  limits: SafeJSONShapeReportLimits = .standard
) throws -> SafeJSONShapeReport {
  let shape = try StrictJSONSchemaScanner.scan(input, reportLimits: limits)
  return try #require(shape.safeReport)
}

private func data(_ value: String) -> Data {
  Data(value.utf8)
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class ShapeReportCancellationProbe: @unchecked Sendable {
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
