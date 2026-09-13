import Testing

@testable import BridgeCore

struct ManifestReferenceDigestTests {
  @Test
  func matchesIndependentKnownVector() throws {
    let digest = try ManifestReferenceDigest.make(
      release: .genshinOfficialCN,
      category: .game,
      manifestID: try ManifestReferenceID("manifest-123"),
      profileRevision: 7,
      kind: .chunk
    )

    #expect(ManifestReferenceDigest.currentVersion == 1)
    #expect(
      digest.lowercaseHex
        == "1e7e1a7feeb4b275b18d5f596d309050b7ef4a188dab2f2d8f3dc309dfbcde37")
  }

  @Test
  func bindsEveryVariableFieldAndLengthFramesOpaqueID() throws {
    func digest(
      id: String,
      revision: UInt64 = 7,
      kind: ManifestReferenceKind = .chunk
    ) throws -> ManifestReferenceDigest {
      try ManifestReferenceDigest.make(
        release: .genshinOfficialCN,
        category: .game,
        manifestID: ManifestReferenceID(id),
        profileRevision: revision,
        kind: kind
      )
    }

    let baseline = try digest(id: "ab-c")
    #expect(try digest(id: "a-bc") != baseline)
    #expect(try digest(id: "ab-c", revision: 8) != baseline)
    #expect(try digest(id: "ab-c", kind: .ldiff) != baseline)
    #expect(try digest(id: "ab-c") == baseline)
    #expect(try ManifestReferenceDigest.parseLowercaseHex(baseline.lowercaseHex) == baseline)
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReferenceDigest.parseLowercaseHex(baseline.lowercaseHex.uppercased())
    }
  }

  @Test
  func rejectsUnsafeOpaqueIDAndZeroRevisionWithoutEchoingInput() throws {
    let canary = "https://example.invalid/path?token=secret=value"
    for invalidID in [
      "", ".", "..", " id", "id ", "a/b", "a?b", "a=b", "secret\nvalue", canary,
    ] {
      #expect(throws: ManifestAdapterError.invalidManifest) {
        try ManifestReferenceID(invalidID)
      }
    }
    do {
      _ = try ManifestReferenceID(canary)
      Issue.record("Unsafe identifier unexpectedly passed validation")
    } catch {
      #expect(!String(describing: error).contains(canary))
      #expect(!String(reflecting: error).contains(canary))
    }
    let identifier = try ManifestReferenceID("safe-id_1.2")
    var dumped = ""
    dump(identifier, to: &dumped)
    #expect(!dumped.contains("safe-id_1.2"))
    #expect(!dumped.contains(canary))
    #expect(!String(describing: identifier).contains("safe-id_1.2"))
    #expect(!String(reflecting: identifier).contains("safe-id_1.2"))
    #expect(Mirror(reflecting: identifier).children.first?.label == "redacted")
    #expect(throws: ManifestAdapterError.invalidManifest) {
      try ManifestReferenceDigest.make(
        release: .genshinOfficialCN,
        category: .game,
        manifestID: identifier,
        profileRevision: 0,
        kind: .chunk
      )
    }
  }
}
