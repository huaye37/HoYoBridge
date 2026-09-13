import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

struct StrictBranchSemanticDecoderTests {
  private let requestIdentity =
    "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d"
  private let transportPolicy =
    "e7ebc929ac6a6d25dc16c0d58bbaa67cfd15d7dda394b30bd150fd819cf220e4"

  @Test
  func decodesPinnedShapeIntoRedactedCapabilityAndKnownBinding() throws {
    let body = validSemanticBody()
    let policy = try syntheticPolicy(for: body)
    let capability = try StrictCNBranchSemanticDecoder.decode(
      body,
      requestIdentitySHA256: requestIdentity,
      transportPolicySHA256: transportPolicy,
      semanticPolicy: policy
    )

    #expect(capability.semanticPolicyVersion == 1)
    #expect(capability.requestIdentitySHA256 == requestIdentity)
    #expect(capability.transportPolicySHA256 == transportPolicy)
    #expect(capability.bodySHA256 == sha256(body))
    #expect(capability.valueFreeShapeSHA256 == policy.expectedShapeSHA256)
    #expect(capability.safeReportSHA256 == policy.expectedReportSHA256)
    #expect(
      capability.bindingSHA256 == "eb384daf5d26045d903896957c1e07913855f418650a9b3f5332fb29e696e373"
    )
    #expect(capability.gameID.rawValue == "1Z8W5NHUQb")
    #expect(capability.main.tag.rawValue == "tag-canary")
    #expect(
      BranchSemanticPolicy.observedCNV1.expectedShapeSHA256
        == BranchShapeDiscoveryProfile.priorShapeSHA256)
    #expect(
      BranchSemanticPolicy.observedCNV1.expectedReportSHA256
        == "bb82a7b942898063b3d5abc09d9e7e62a372dfba5c7e30181658aab683de6b25"
    )
    #expect(!(ValidatedCNBranchCapability.self is any Encodable.Type))
    #expect(!(ValidatedCNBranchCapability.self is any Decodable.Type))

    var dumped = ""
    dump(capability, to: &dumped)
    dump(capability.main, to: &dumped)
    dump(capability.main.password, to: &dumped)
    #expect(dumped.contains("redacted"))
    for canary in semanticCanaries {
      #expect(!dumped.contains(canary))
    }
  }

  @Test
  func rejectsShapeIdentityAndValueMismatches() throws {
    let body = validSemanticBody()
    let policy = try syntheticPolicy(for: body)
    #expect(throws: ManifestSamplingError.semanticShapeRejected) {
      try StrictCNBranchSemanticDecoder.decode(
        body,
        requestIdentitySHA256: requestIdentity,
        transportPolicySHA256: transportPolicy
      )
    }
    #expect(throws: ManifestSamplingError.semanticShapeRejected) {
      try StrictCNBranchSemanticDecoder.decode(
        body,
        requestIdentitySHA256: String(repeating: "0", count: 64),
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }
    #expect(throws: ManifestSamplingError.semanticShapeRejected) {
      try StrictCNBranchSemanticDecoder.decode(
        body,
        requestIdentitySHA256: requestIdentity,
        transportPolicySHA256: "uppercase-not-a-hash",
        semanticPolicy: policy
      )
    }
    #expect(throws: ManifestSamplingError.semanticShapeRejected) {
      try StrictCNBranchSemanticDecoder.decode(
        data(
          #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null,"new_field":true}]}}"#
        ),
        requestIdentitySHA256: requestIdentity,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }

    let wrongGame = data(
      #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"wrong-game","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
    )
    #expect(throws: ManifestSamplingError.semanticValueRejected) {
      try StrictCNBranchSemanticDecoder.decode(
        wrongGame,
        requestIdentitySHA256: requestIdentity,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }
    let emptyPassword = data(
      #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":""},"pre_download":null}]}}"#
    )
    #expect(throws: ManifestSamplingError.semanticValueRejected) {
      try StrictCNBranchSemanticDecoder.decode(
        emptyPassword,
        requestIdentitySHA256: requestIdentity,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }

    let baseText = String(decoding: body, as: UTF8.self)
    let invalidTexts = [
      baseText.replacingOccurrences(of: "tag-canary", with: " tag-canary"),
      baseText.replacingOccurrences(of: "branch-canary", with: #"branch\u0000canary"#),
      baseText.replacingOccurrences(
        of: "package-canary",
        with: String(repeating: "p", count: 257)
      ),
      baseText.replacingOccurrences(of: "biz-canary", with: ""),
    ]
    for invalidText in invalidTexts {
      #expect(throws: ManifestSamplingError.semanticValueRejected) {
        try StrictCNBranchSemanticDecoder.decode(
          data(invalidText),
          requestIdentitySHA256: requestIdentity,
          transportPolicySHA256: transportPolicy,
          semanticPolicy: policy
        )
      }
    }
  }

  @Test
  func snapshotsMutableInputAndBindsSameShapeValueChanges() throws {
    let original = validSemanticBody()
    let mutable = NSMutableData(data: original)
    let aliased = Data(referencing: mutable)
    let policy = try syntheticPolicy(for: original)
    let first = try StrictCNBranchSemanticDecoder.decode(
      aliased,
      requestIdentitySHA256: requestIdentity,
      transportPolicySHA256: transportPolicy,
      semanticPolicy: policy
    )
    mutable.replaceBytes(
      in: NSRange(location: 0, length: mutable.length),
      withBytes: [UInt8](repeating: 0, count: mutable.length))
    #expect(first.bodySHA256 == sha256(original))
    #expect(first.main.password.rawValue == "password-canary")

    let changed = data(
      #"{"retcode":0,"message":"changed","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"different-biz"},"main":{"tag":"different-tag","branch":"different-branch","package_id":"different-package","password":"different-password"},"pre_download":null}]}}"#
    )
    let second = try StrictCNBranchSemanticDecoder.decode(
      changed,
      requestIdentitySHA256: requestIdentity,
      transportPolicySHA256: transportPolicy,
      semanticPolicy: policy
    )
    #expect(first.valueFreeShapeSHA256 == second.valueFreeShapeSHA256)
    #expect(first.safeReportSHA256 == second.safeReportSHA256)
    #expect(first.bodySHA256 != second.bodySHA256)
    #expect(first.bindingSHA256 != second.bindingSHA256)
  }

  @Test
  func preservesCancellationAndConcurrentDeterminism() async throws {
    let body = validSemanticBody()
    let policy = try syntheticPolicy(for: body)
    let probe = SemanticCancellationProbe(cancelOnCall: 3)
    #expect(throws: CancellationError.self) {
      try StrictCNBranchSemanticDecoder.decode(
        body,
        requestIdentitySHA256: requestIdentity,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy,
        cancellationCheck: probe.check
      )
    }

    let bindings = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<16 {
        group.addTask {
          try StrictCNBranchSemanticDecoder.decode(
            body,
            requestIdentitySHA256: requestIdentity,
            transportPolicySHA256: transportPolicy,
            semanticPolicy: policy
          ).bindingSHA256
        }
      }
      var values: [String] = []
      for try await value in group { values.append(value) }
      return values
    }
    #expect(Set(bindings).count == 1)
  }

  private func syntheticPolicy(for body: Data) throws -> BranchSemanticPolicy {
    let shape = try StrictJSONSchemaScanner.scan(body, reportLimits: .standard)
    let report = try #require(shape.safeReport)
    return BranchSemanticPolicy(
      policyVersion: 1,
      expectedRequestIdentitySHA256: requestIdentity,
      expectedShapePolicyVersion: shape.policyVersion,
      expectedShapeSHA256: shape.sha256,
      expectedGameBranchEntryCount: shape.gameBranchEntryCount,
      expectedReportPolicyVersion: report.policyVersion,
      expectedReportSHA256: report.sha256,
      expectedCanonicalReportByteSize: report.canonicalByteSize,
      expectedGameID: "1Z8W5NHUQb"
    )
  }
}

private let semanticCanaries = [
  "1Z8W5NHUQb", "biz-canary", "tag-canary", "branch-canary", "package-canary",
  "password-canary",
]

private func validSemanticBody() -> Data {
  data(
    #"{"retcode":0,"message":"message-canary","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
  )
}

private func data(_ value: String) -> Data {
  Data(value.utf8)
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class SemanticCancellationProbe: @unchecked Sendable {
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
