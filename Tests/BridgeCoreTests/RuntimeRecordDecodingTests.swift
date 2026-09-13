import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct RuntimeRecordDecodingTests {
  @Test
  func canonicalInstallAndActivationRecordsDecodeToTrustedValues() throws {
    let install = try makeInstall()
    let activation = try makeActivation(installed: install)
    let installData = try canonicalData(install.record)
    let activationData = try canonicalData(activation)

    #expect(try RuntimeRecordDecoder.decodeInstall(installData) == install.record)
    #expect(try RuntimeRecordDecoder.decodeActivation(activationData) == activation)
  }

  @Test
  func singleFieldTamperingInvalidatesCanonicalIDs() throws {
    let install = try makeInstall()
    let installData = try canonicalData(install.record)
    let damagedInstall = try replacing(
      installData,
      "\"totalBytes\":4",
      with: "\"totalBytes\":5"
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeInstall(damagedInstall)
    }

    let activation = try makeActivation(installed: install)
    let activationData = try canonicalData(activation)
    let damagedActivation = try replacing(
      activationData,
      "\"generation\":1",
      with: "\"generation\":2"
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeActivation(damagedActivation)
    }
  }

  @Test
  func rejectsWhitespaceUnknownDuplicateAndDeepJSON() throws {
    let install = try makeInstall()
    let canonical = try canonicalData(install.record)
    var whitespace = Data([0x20])
    whitespace.append(canonical)
    #expect(throws: RuntimeRecordDecodingError.nonCanonical) {
      try RuntimeRecordDecoder.decodeInstall(whitespace)
    }

    let text = try #require(String(data: canonical, encoding: .utf8))
    let unknown = Data(("{\"unknown\":0," + text.dropFirst()).utf8)
    #expect(throws: RuntimeRecordDecodingError.nonCanonical) {
      try RuntimeRecordDecoder.decodeInstall(unknown)
    }
    let duplicate = Data(("{\"schemaVersion\":1," + text.dropFirst()).utf8)
    #expect(throws: (any Error).self) {
      try RuntimeRecordDecoder.decodeInstall(duplicate)
    }
    let deep = Data(
      ("{\"unknown\":" + String(repeating: "[", count: 65) + "0"
        + String(repeating: "]", count: 65) + "," + text.dropFirst()).utf8
    )
    #expect(throws: RuntimeRecordDecodingError.malformed) {
      try RuntimeRecordDecoder.decodeInstall(deep)
    }
  }

  @Test
  func rejectsBadSchemaAndOversizedInput() throws {
    let install = try makeInstall()
    let badSchema = try replacing(
      canonicalData(install.record),
      "\"schemaVersion\":1",
      with: "\"schemaVersion\":2"
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeInstall(badSchema)
    }
    #expect(
      throws: RuntimeRecordDecodingError.oversized
    ) {
      try RuntimeRecordDecoder.decodeActivation(
        Data(repeating: 0x20, count: RuntimeRecordDecoder.maximumActivationBytes + 1)
      )
    }
    #expect(RuntimeRecordDecoder.maximumInstallBytes == 128 * 1_024 * 1_024)
  }

  @Test
  func rejectsAcknowledgementAndTierContradictions() throws {
    let standardInstall = try makeInstall()
    let standard = try makeActivation(installed: standardInstall)
    let standardText = try #require(
      String(data: canonicalData(standard), encoding: .utf8)
    )
    let injectedAck = Data(
      ("{\"acknowledgementSHA256\":\"\(String(repeating: "a", count: 64))\","
        + standardText.dropFirst()).utf8
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeActivation(injectedAck)
    }

    let experimentalInstall = try makeInstall(experimental: true)
    let experimental = try makeActivation(
      installed: experimentalInstall,
      experimental: true
    )
    let missingAck = try replacing(
      canonicalData(experimental),
      "\"acknowledgementSHA256\":\"\(try #require(experimental.acknowledgementSHA256))\"",
      with: "\"acknowledgementSHA256\":null"
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeActivation(missingAck)
    }
    let wrongMode = try replacing(
      canonicalData(experimental),
      "\"selectionMode\":\"experimental\"",
      with: "\"selectionMode\":\"standard\""
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeActivation(wrongMode)
    }
  }

  @Test
  func rejectsSelfConsistentUnsafePathsAndCasefoldCollision() throws {
    let base = try makeInstall().record
    let contentSHA256 = sha256(Data("tool".utf8))
    for path in ["a:b", "a\\b"] {
      let record = rebuiltInstall(
        base,
        entries: [
          RuntimeInstallEntryRecord(
            relativePath: path,
            kind: .regularFile,
            size: 4,
            mode: 0o700,
            contentSHA256: contentSHA256
          )
        ]
      )
      #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
        try RuntimeRecordDecoder.decodeInstall(try canonicalData(record))
      }
    }

    let collision = rebuiltInstall(
      base,
      entries: [
        RuntimeInstallEntryRecord(
          relativePath: "A", kind: .directory, size: 0, mode: 0o700,
          contentSHA256: nil),
        RuntimeInstallEntryRecord(
          relativePath: "a", kind: .directory, size: 0, mode: 0o700,
          contentSHA256: nil),
      ]
    )
    #expect(throws: RuntimeRecordDecodingError.invalidRecord) {
      try RuntimeRecordDecoder.decodeInstall(try canonicalData(collision))
    }
  }

  private func makeInstall(experimental: Bool = false) throws -> InstalledRuntimeVersion {
    let runtime = CatalogTestFixtures.runtime(
      id: experimental ? "runtime-candidate" : "runtime-stable",
      verification: experimental ? .candidate : .verified
    )
    let descriptors = [
      ArchiveEntryDescriptor(
        path: "Bin/", kind: .directory, declaredSize: 0, permissions: 0o755),
      ArchiveEntryDescriptor(
        path: "Bin/Tool", kind: .regularFile, declaredSize: 4, permissions: 0o755),
    ]
    let plan = try SafeArchivePlanner.plan(
      entries: descriptors,
      archiveByteSize: try #require(runtime.byteSize)
    )
    let entries = [
      StagingTreeSealEntry(
        relativePath: "Bin", kind: .directory, size: 0, mode: 0o700,
        contentSHA256: nil),
      StagingTreeSealEntry(
        relativePath: "Bin/Tool", kind: .regularFile, size: 4, mode: 0o700,
        contentSHA256: sha256(Data("tool".utf8))),
    ]
    let candidate = ExtractedStagingTree(
      rootURL: URL(fileURLWithPath: "/private/tmp/unused"),
      regularFileCount: 1, totalBytes: 4,
      artifactSHA256: try #require(runtime.sha256?.lowercased()),
      planSHA256: plan.canonicalSHA256, planPolicyVersion: plan.policyVersion,
      treeSealVersion: SafeStagingTreeSealer.currentVersion,
      rootDevice: 1, rootInode: 2, entries: entries,
      treeSHA256: SafeStagingTreeSealer.canonicalSHA256(for: entries)
    )
    let record = try RuntimeInstallIdentityBuilder.build(
      runtime: runtime, plan: plan, candidate: candidate)
    return InstalledRuntimeVersion(
      versionURL: URL(
        fileURLWithPath: "/versions/\(record.installID.prefix(2))/\(record.installID)"),
      record: record,
      disposition: .published
    )
  }

  private func makeActivation(
    installed: InstalledRuntimeVersion,
    experimental: Bool = false
  ) throws -> RuntimeActivationRecord {
    let runtimeID = installed.record.runtimeID
    let runtime = CatalogTestFixtures.runtime(
      id: runtimeID,
      verification: experimental ? .candidate : .verified
    )
    let profile =
      experimental
      ? CatalogTestFixtures.experimentalProfile(runtimeID: runtimeID)
      : CatalogTestFixtures.standardProfile(runtime: runtime)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    let verified = CatalogTestFixtures.verifiedCatalog(catalog)
    let acknowledgement = CompatibilitySelector.acknowledgement(for: profile, in: verified)
    return try RuntimeActivationIdentityBuilder.build(
      installed: installed,
      verifiedCatalog: verified,
      request: CatalogTestFixtures.request(
        mode: experimental ? .experimental : .standard,
        preferredProfileID: experimental ? profile.id : nil,
        acknowledgements: experimental ? [acknowledgement] : []
      ),
      generation: 1
    )
  }

  private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private func rebuiltInstall(
    _ base: RuntimeInstallRecord,
    entries: [RuntimeInstallEntryRecord]
  ) -> RuntimeInstallRecord {
    let sealEntries = entries.map {
      StagingTreeSealEntry(
        relativePath: $0.relativePath, kind: $0.kind, size: $0.size,
        mode: $0.mode, contentSHA256: $0.contentSHA256)
    }
    let treeSHA256 = SafeStagingTreeSealer.canonicalSHA256(for: sealEntries)
    let regularFiles = entries.filter { $0.kind == .regularFile }
    let totalBytes = regularFiles.reduce(UInt64(0)) { $0 + $1.size }
    let installID = RuntimeInstallIdentityBuilder.makeInstallID(
      runtimeID: base.runtimeID,
      runtimeDefinitionSHA256: base.runtimeDefinitionSHA256,
      artifactSHA256: base.artifactSHA256,
      planPolicyVersion: base.planPolicyVersion,
      planSHA256: base.planSHA256,
      treeSealVersion: base.treeSealVersion,
      treeSHA256: treeSHA256,
      entryCount: entries.count,
      regularFileCount: regularFiles.count,
      totalBytes: totalBytes
    )
    return RuntimeInstallRecord(
      schemaVersion: base.schemaVersion, installID: installID,
      runtimeID: base.runtimeID, runtimeDefinitionSHA256: base.runtimeDefinitionSHA256,
      artifactSHA256: base.artifactSHA256, planPolicyVersion: base.planPolicyVersion,
      planSHA256: base.planSHA256, treeSealVersion: base.treeSealVersion,
      treeSHA256: treeSHA256, entryCount: entries.count,
      regularFileCount: regularFiles.count, totalBytes: totalBytes, entries: entries
    )
  }

  private func replacing(_ data: Data, _ target: String, with replacement: String) throws -> Data {
    let value = try #require(String(data: data, encoding: .utf8))
    let changed = value.replacingOccurrences(of: target, with: replacement)
    #expect(changed != value)
    return Data(changed.utf8)
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
