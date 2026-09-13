import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct RuntimeInstallIdentityTests {
  private let artifactSHA256 = String(repeating: "a", count: 64)

  @Test
  func buildsKnownMGBInstallVector() throws {
    let plan = try makePlan()
    let candidate = makeCandidate(plan: plan)
    let record = try RuntimeInstallIdentityBuilder.build(
      runtime: makeRuntime(),
      plan: plan,
      candidate: candidate
    )

    #expect(record.schemaVersion == 1)
    #expect(
      record.runtimeDefinitionSHA256
        == "33a8527542ef6ce461530951b5237985b045def8284ec11b0a4e1142fd53cbfb")
    #expect(record.installID == "a3d954dceb0a27dc20619b326e79cf9b0a5f63d0329825c6742f0fd489dfa575")
    #expect(record.planSHA256 == plan.canonicalSHA256)
    #expect(record.entryCount == 2)
    #expect(record.regularFileCount == 1)
    #expect(record.totalBytes == 4)
    #expect(record.entries.map(\.relativePath) == ["Bin", "Bin/Tool"])
  }

  @Test
  func identityChangesWhenBoundFieldsChange() throws {
    let basePlan = try makePlan()
    let base = try build(runtime: makeRuntime(), plan: basePlan)

    let runtimeID = try build(
      runtime: makeRuntime(id: "runtime.other"),
      plan: basePlan
    )
    let runtimeDefinition = try build(
      runtime: makeRuntime(version: "1.2.4"),
      plan: basePlan
    )
    let otherArtifact = String(repeating: "c", count: 64)
    let artifact = try build(
      runtime: makeRuntime(artifactSHA256: otherArtifact),
      plan: basePlan,
      artifactSHA256: otherArtifact
    )
    let uppercaseArtifact = try build(
      runtime: makeRuntime(artifactSHA256: artifactSHA256.uppercased()),
      plan: basePlan
    )
    let otherPlan = try makePlan(archiveByteSize: 21)
    let plan = try build(
      runtime: makeRuntime(byteSize: 21),
      plan: otherPlan
    )
    let tree = try build(
      runtime: makeRuntime(),
      plan: basePlan,
      content: Data("fool".utf8)
    )

    #expect(uppercaseArtifact.artifactSHA256 == artifactSHA256)
    let installIDs = [
      base, runtimeID, runtimeDefinition, artifact, uppercaseArtifact, plan, tree,
    ].map(\.installID)
    #expect(Set(installIDs).count == installIDs.count)
  }

  @Test
  func rejectsRuntimeArtifactPlanAndCandidateMismatches() throws {
    let plan = try makePlan()
    let candidate = makeCandidate(plan: plan)

    #expect(throws: RuntimeInstallIdentityError.runtimeIsNotManagedDownload) {
      try RuntimeInstallIdentityBuilder.build(
        runtime: makeRuntime(acquisition: .detectOnly),
        plan: plan,
        candidate: candidate
      )
    }
    #expect(throws: RuntimeInstallIdentityError.artifactMismatch) {
      try RuntimeInstallIdentityBuilder.build(
        runtime: makeRuntime(artifactSHA256: String(repeating: "c", count: 64)),
        plan: plan,
        candidate: candidate
      )
    }
    #expect(throws: RuntimeInstallIdentityError.planMismatch) {
      try RuntimeInstallIdentityBuilder.build(
        runtime: makeRuntime(byteSize: 21),
        plan: plan,
        candidate: candidate
      )
    }
    #expect(throws: RuntimeInstallIdentityError.planMismatch) {
      try RuntimeInstallIdentityBuilder.build(
        runtime: makeRuntime(),
        plan: plan,
        candidate: copy(candidate, planSHA256: String(repeating: "c", count: 64))
      )
    }
    #expect(throws: RuntimeInstallIdentityError.invalidCandidate) {
      try RuntimeInstallIdentityBuilder.build(
        runtime: makeRuntime(),
        plan: plan,
        candidate: copy(candidate, treeSHA256: String(repeating: "c", count: 64))
      )
    }
    #expect(throws: RuntimeInstallIdentityError.invalidRuntimeIdentity) {
      try RuntimeInstallIdentityBuilder.build(
        runtime: makeRuntime(license: " "),
        plan: plan,
        candidate: candidate
      )
    }
  }

  @Test
  func encodesValidatedRecordForAuditWithoutProvidingTrustedDecode() throws {
    let plan = try makePlan()
    let record = try build(runtime: makeRuntime(), plan: plan)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(record)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["schemaVersion"] as? Int == 1)
    #expect(object["installID"] as? String == record.installID)
    #expect((object["entries"] as? [[String: Any]])?.count == 2)
  }

  private func build(
    runtime: RuntimeDefinition,
    plan: SafeArchivePlan,
    artifactSHA256: String? = nil,
    content: Data = Data("tool".utf8)
  ) throws -> RuntimeInstallRecord {
    try RuntimeInstallIdentityBuilder.build(
      runtime: runtime,
      plan: plan,
      candidate: makeCandidate(
        plan: plan,
        artifactSHA256: artifactSHA256 ?? self.artifactSHA256,
        content: content
      )
    )
  }

  private func makePlan(archiveByteSize: UInt64 = 20) throws -> SafeArchivePlan {
    try SafeArchivePlanner.plan(
      entries: [
        ArchiveEntryDescriptor(
          path: "Bin/", kind: .directory, declaredSize: 0, permissions: 0o755),
        ArchiveEntryDescriptor(
          path: "Bin/Tool", kind: .regularFile, declaredSize: 4, permissions: 0o755),
      ],
      archiveByteSize: archiveByteSize
    )
  }

  private func makeCandidate(
    plan: SafeArchivePlan,
    artifactSHA256: String? = nil,
    content: Data = Data("tool".utf8)
  ) -> ExtractedStagingTree {
    let entries = [
      StagingTreeSealEntry(
        relativePath: "Bin", kind: .directory, size: 0, mode: 0o700,
        contentSHA256: nil),
      StagingTreeSealEntry(
        relativePath: "Bin/Tool", kind: .regularFile, size: 4, mode: 0o700,
        contentSHA256: sha256(content)),
    ]
    return ExtractedStagingTree(
      rootURL: URL(fileURLWithPath: "/private/tmp/unused"),
      regularFileCount: 1,
      totalBytes: 4,
      artifactSHA256: artifactSHA256 ?? self.artifactSHA256,
      planSHA256: plan.canonicalSHA256,
      planPolicyVersion: plan.policyVersion,
      treeSealVersion: SafeStagingTreeSealer.currentVersion,
      rootDevice: 1,
      rootInode: 2,
      entries: entries,
      treeSHA256: SafeStagingTreeSealer.canonicalSHA256(for: entries)
    )
  }

  private func copy(
    _ candidate: ExtractedStagingTree,
    planSHA256: String? = nil,
    treeSHA256: String? = nil
  ) -> ExtractedStagingTree {
    ExtractedStagingTree(
      rootURL: candidate.rootURL,
      regularFileCount: candidate.regularFileCount,
      totalBytes: candidate.totalBytes,
      artifactSHA256: candidate.artifactSHA256,
      planSHA256: planSHA256 ?? candidate.planSHA256,
      planPolicyVersion: candidate.planPolicyVersion,
      treeSealVersion: candidate.treeSealVersion,
      rootDevice: candidate.rootDevice,
      rootInode: candidate.rootInode,
      entries: candidate.entries,
      treeSHA256: treeSHA256 ?? candidate.treeSHA256
    )
  }

  private func makeRuntime(
    id: String = "runtime.test",
    version: String = "1.2.3",
    acquisition: RuntimeAcquisition = .managedDownload,
    byteSize: UInt64 = 20,
    artifactSHA256: String? = nil,
    license: String = "MIT"
  ) -> RuntimeDefinition {
    RuntimeDefinition(
      id: id,
      backend: .dxmt,
      version: version,
      verification: .candidate,
      acquisition: acquisition,
      sourceURL: "https://example.invalid/runtime.zip",
      byteSize: byteSize,
      sha256: artifactSHA256 ?? self.artifactSHA256,
      license: license,
      redistributable: true
    )
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
