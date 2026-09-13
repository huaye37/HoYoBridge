import CryptoKit
import Foundation
import Testing

@testable import ManifestSamplingCore

struct StrictMainBuildSemanticDecoderTests {
  private let transportPolicy =
    "dd0ab612aee8d025894e7f43269a287434844ecc29c2dbe03e70ea887844277d"

  @Test
  func decodesUniqueGameManifestIntoRedactedCapability() throws {
    let branch = try makeBranchCapability()
    let body = validMainBuildBody()
    let policy = try syntheticBuildPolicy(for: body)
    let capability = try StrictMainBuildSemanticDecoder.decode(
      body,
      branchCapability: branch,
      transportPolicySHA256: transportPolicy,
      semanticPolicy: policy
    )

    #expect(capability.semanticPolicyVersion == 1)
    #expect(capability.branchCapabilityBindingSHA256 == branch.bindingSHA256)
    #expect(capability.bodySHA256 == sha256(body))
    #expect(capability.tag.rawValue == "tag-canary")
    #expect(capability.matchingField.rawValue == "game")
    #expect(capability.manifest.id.rawValue == "manifest-id-canary")
    #expect(
      capability.bindingSHA256 == "8f1de67aaa2985979839b932dfa1868dd4e1bc1bc6ebb37afdcbabf311643a44"
    )
    #expect(
      MainBuildSemanticPolicy.observedCNV1.expectedShapeSHA256
        == "21e89e02cc735be6296f7ab41763875a8b7ff86db2e3fcefec32453e131db851"
    )
    #expect(!(ValidatedMainBuildCapability.self is any Encodable.Type))
    #expect(!(ValidatedMainBuildCapability.self is any Decodable.Type))
    var dumped = ""
    dump(capability, to: &dumped)
    dump(capability.manifest, to: &dumped)
    dump(capability.manifestDownload, to: &dumped)
    #expect(dumped.contains("redacted"))
    for canary in buildSemanticCanaries {
      #expect(!dumped.contains(canary))
    }
  }

  @Test
  func rejectsShapeTagCategoryAndValueMismatches() throws {
    let branch = try makeBranchCapability()
    let body = validMainBuildBody()
    let policy = try syntheticBuildPolicy(for: body)
    #expect(throws: ManifestSamplingError.semanticShapeRejected) {
      try StrictMainBuildSemanticDecoder.decode(
        body,
        branchCapability: branch,
        transportPolicySHA256: transportPolicy
      )
    }
    #expect(throws: ManifestSamplingError.semanticShapeRejected) {
      try StrictMainBuildSemanticDecoder.decode(
        body,
        branchCapability: branch,
        transportPolicySHA256: "not-a-hash",
        semanticPolicy: policy
      )
    }

    let wrongTag = String(decoding: body, as: UTF8.self)
      .replacingOccurrences(of: #""tag":"tag-canary""#, with: #""tag":"wrong-tag""#)
    #expect(throws: ManifestSamplingError.buildHeaderRejected) {
      try StrictMainBuildSemanticDecoder.decode(
        data(wrongTag),
        branchCapability: branch,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }
    let wrongField = String(decoding: body, as: UTF8.self)
      .replacingOccurrences(of: #""matching_field":"game""#, with: #""matching_field":"audio""#)
    #expect(throws: ManifestSamplingError.buildSelectionRejected) {
      try StrictMainBuildSemanticDecoder.decode(
        data(wrongField),
        branchCapability: branch,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }
    let emptyID = String(decoding: body, as: UTF8.self)
      .replacingOccurrences(of: "manifest-id-canary", with: "")
    #expect(throws: ManifestSamplingError.buildManifestReferenceRejected) {
      try StrictMainBuildSemanticDecoder.decode(
        data(emptyID),
        branchCapability: branch,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }
    let emptyDownloadPassword = String(decoding: body, as: UTF8.self)
      .replacingOccurrences(of: "download-password-canary", with: "")
    #expect(throws: ManifestSamplingError.buildDownloadReferenceRejected) {
      try StrictMainBuildSemanticDecoder.decode(
        data(emptyDownloadPassword),
        branchCapability: branch,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy
      )
    }
  }

  @Test
  func snapshotsMutableInputAndBindsSameShapeChanges() throws {
    let branch = try makeBranchCapability()
    let original = validMainBuildBody()
    let policy = try syntheticBuildPolicy(for: original)
    let mutable = NSMutableData(data: original)
    let first = try StrictMainBuildSemanticDecoder.decode(
      Data(referencing: mutable),
      branchCapability: branch,
      transportPolicySHA256: transportPolicy,
      semanticPolicy: policy
    )
    mutable.replaceBytes(
      in: NSRange(location: 0, length: mutable.length),
      withBytes: [UInt8](repeating: 0, count: mutable.length)
    )
    #expect(first.bodySHA256 == sha256(original))
    #expect(first.manifestDownload.urlPrefix.rawValue == "https://example.invalid/base")

    let changed = String(decoding: original, as: UTF8.self)
      .replacingOccurrences(of: "manifest-id-canary", with: "different-manifest")
      .replacingOccurrences(of: "checksum-canary", with: "different-checksum")
    let second = try StrictMainBuildSemanticDecoder.decode(
      data(changed),
      branchCapability: branch,
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
    let branch = try makeBranchCapability()
    let body = validMainBuildBody()
    let policy = try syntheticBuildPolicy(for: body)
    let probe = MainBuildCancellationProbe(cancelOnCall: 3)
    #expect(throws: CancellationError.self) {
      try StrictMainBuildSemanticDecoder.decode(
        body,
        branchCapability: branch,
        transportPolicySHA256: transportPolicy,
        semanticPolicy: policy,
        cancellationCheck: probe.check
      )
    }

    let bindings = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<16 {
        group.addTask {
          try StrictMainBuildSemanticDecoder.decode(
            body,
            branchCapability: branch,
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

  private func syntheticBuildPolicy(for body: Data) throws -> MainBuildSemanticPolicy {
    let shape = try StrictJSONSchemaScanner.scanRootData(body, reportLimits: .standard)
    let report = try #require(shape.safeReport)
    return MainBuildSemanticPolicy(
      policyVersion: 1,
      expectedShapePolicyVersion: shape.policyVersion,
      expectedShapeSHA256: shape.sha256,
      expectedReportPolicyVersion: report.policyVersion,
      expectedReportSHA256: report.sha256,
      expectedCanonicalReportByteSize: report.canonicalByteSize,
      expectedMatchingField: "game"
    )
  }

  private func makeBranchCapability() throws -> ValidatedCNBranchCapability {
    let body = validBranchBodyForBuildDecoder()
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
    return try StrictCNBranchSemanticDecoder.decode(
      body,
      requestIdentitySHA256:
        "dd86fd2a02f70a6188cdf0e471455617ecdfc5c359f1b198168468b4a896ee5d",
      transportPolicySHA256: transportPolicy,
      semanticPolicy: policy
    )
  }
}

private let buildSemanticCanaries = [
  "tag-canary", "build-id-canary", "category-name-canary", "manifest-id-canary",
  "checksum-canary", "download-password-canary", "https://example.invalid/base",
]

private func validBranchBodyForBuildDecoder() -> Data {
  data(
    #"{"retcode":0,"message":"ok","data":{"game_branches":[{"game":{"id":"1Z8W5NHUQb","biz":"biz-canary"},"main":{"tag":"tag-canary","branch":"branch-canary","package_id":"package-canary","password":"password-canary"},"pre_download":null}]}}"#
  )
}

private func validMainBuildBody() -> Data {
  data(
    #"{"retcode":0,"message":"ok","data":{"tag":"tag-canary","build_id":"build-id-canary","manifests":[{"category_id":"game","category_name":"category-name-canary","matching_field":"game","manifest":{"id":"manifest-id-canary","checksum":"checksum-canary","compressed_size":"123","uncompressed_size":"456"},"manifest_download":{"password":"download-password-canary","url_prefix":"https://example.invalid/base"}}]}}"#
  )
}

private func data(_ value: String) -> Data {
  Data(value.utf8)
}

private func sha256(_ value: Data) -> String {
  SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
}

private final class MainBuildCancellationProbe: @unchecked Sendable {
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
