import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

@Suite(.serialized)
struct SafeStagingTreeSealTests {
  private let artifactSHA256 = String(repeating: "a", count: 64)

  @Test
  func planDigestMatchesKnownVectorsAndInputPermutations() throws {
    let empty = try SafeArchivePlanner.plan(entries: [], archiveByteSize: 1)
    #expect(
      empty.canonicalSHA256
        == "8ca631e36c78314db94656735e1d853c963f4d7d82cc0ac77df644ad83829880"
    )

    let descriptors = [
      descriptor("Bin/", kind: .directory, permissions: 0o755),
      descriptor("Bin/Tool", size: 4, permissions: 0o755),
    ]
    let forward = try SafeArchivePlanner.plan(entries: descriptors, archiveByteSize: 20)
    let reverse = try SafeArchivePlanner.plan(
      entries: descriptors.reversed(),
      archiveByteSize: 20
    )

    #expect(forward.canonicalSHA256 == reverse.canonicalSHA256)
    #expect(
      forward.canonicalSHA256
        == "eaab5dcf8493d6ec6fef1656fdd12629a87faf32651f2436e6d7b5039c79f7a1"
    )
  }

  @Test
  func treeDigestIsStableAcrossChunksAndChangesWithContent() throws {
    try withPrivateParent { parent in
      let descriptors = [
        descriptor("Bin/", kind: .directory, permissions: 0o755),
        descriptor("Bin/Tool", size: 4, permissions: 0o755),
      ]
      let plan = try SafeArchivePlanner.plan(entries: descriptors, archiveByteSize: 20)
      let first = try extract(
        plan: plan,
        descriptors: descriptors,
        content: Data("tool".utf8),
        chunkSize: 1,
        root: parent.appendingPathComponent("first")
      )
      let second = try extract(
        plan: plan,
        descriptors: descriptors,
        content: Data("tool".utf8),
        chunkSize: 4,
        root: parent.appendingPathComponent("second")
      )
      let changed = try extract(
        plan: plan,
        descriptors: descriptors,
        content: Data("fool".utf8),
        chunkSize: 2,
        root: parent.appendingPathComponent("changed")
      )

      #expect(first.treeSHA256 == second.treeSHA256)
      #expect(first.treeSHA256 != changed.treeSHA256)
      #expect(
        first.treeSHA256
          == "63bf77c931e37d821c450502a25348e821450d3afa18fd679a6310b23a4b3080"
      )
      #expect(
        SafeStagingTreeSealer.canonicalSHA256(for: [])
          == "1cb82f1701473f210370cfb93aae5590a8d94627ad75fffe0b8724958a8b2854"
      )
      #expect(first.artifactSHA256 == artifactSHA256)
      #expect(first.planSHA256 == plan.canonicalSHA256)
      #expect(first.planPolicyVersion == SafeArchivePlanner.currentPolicyVersion)
      #expect(first.treeSealVersion == SafeStagingTreeSealer.currentVersion)
      #expect(first.entries.map(\.relativePath) == ["Bin", "Bin/Tool"])
      #expect(first.entries[0].contentSHA256 == nil)
      #expect(first.entries[1].contentSHA256 == sha256(Data("tool".utf8)))

      var metadata = stat()
      #expect(lstat(first.rootURL.path, &metadata) == 0)
      #expect(first.rootDevice == UInt64(exactly: metadata.st_dev))
      #expect(first.rootInode == UInt64(exactly: metadata.st_ino))
    }
  }

  @Test
  func finalScanRejectsSameInodeSameSizeContentReplacement() throws {
    try withPrivateParent { parent in
      let item = descriptor("file", size: 4)
      let plan = try SafeArchivePlanner.plan(entries: [item], archiveByteSize: 4)
      let root = parent.appendingPathComponent("mutated")
      let source = SealArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [item],
        contents: [pathDigest("file"): Data("good".utf8)],
        chunkSize: 2,
        finishHook: {
          try overwriteInPlace(root.appendingPathComponent("file"), with: Data("evil".utf8))
        }
      )

      #expect(throws: SafeStagingExtractionError.fileContentChanged) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: root,
          source: source
        )
      }
      #expect(!FileManager.default.fileExists(atPath: root.path))
    }
  }

  @Test
  func canonicalDigestsFrameAndCoverEveryField() {
    let zeroHash = String(repeating: "0", count: 64)
    let oneHash = String(repeating: "1", count: 64)
    let baseEntry = PlannedArchiveEntry(
      relativePath: "a",
      sourcePathSHA256: zeroHash,
      kind: .regularFile,
      declaredSize: 1,
      sourcePermissions: 0o644,
      normalizedPermissions: 0o600
    )
    let plans = [
      SafeArchivePlan(
        policyVersion: 1, entries: [baseEntry], archiveByteSize: 1,
        totalRegularFileBytes: 1),
      SafeArchivePlan(
        policyVersion: 2, entries: [baseEntry], archiveByteSize: 1,
        totalRegularFileBytes: 1),
      SafeArchivePlan(
        policyVersion: 1,
        entries: [
          PlannedArchiveEntry(
            relativePath: "aa", sourcePathSHA256: zeroHash, kind: .regularFile,
            declaredSize: 1, sourcePermissions: 0o644, normalizedPermissions: 0o600)
        ],
        archiveByteSize: 1,
        totalRegularFileBytes: 1
      ),
      SafeArchivePlan(
        policyVersion: 1,
        entries: [
          PlannedArchiveEntry(
            relativePath: "a", sourcePathSHA256: oneHash, kind: .regularFile,
            declaredSize: 1, sourcePermissions: 0o644, normalizedPermissions: 0o600)
        ],
        archiveByteSize: 1,
        totalRegularFileBytes: 1
      ),
      SafeArchivePlan(
        policyVersion: 1,
        entries: [
          PlannedArchiveEntry(
            relativePath: "a", sourcePathSHA256: zeroHash, kind: .regularFile,
            declaredSize: 2, sourcePermissions: 0o644, normalizedPermissions: 0o600)
        ],
        archiveByteSize: 1,
        totalRegularFileBytes: 1
      ),
      SafeArchivePlan(
        policyVersion: 1,
        entries: [
          PlannedArchiveEntry(
            relativePath: "a", sourcePathSHA256: zeroHash, kind: .regularFile,
            declaredSize: 1, sourcePermissions: 0o645, normalizedPermissions: 0o600)
        ],
        archiveByteSize: 1,
        totalRegularFileBytes: 1
      ),
      SafeArchivePlan(
        policyVersion: 1,
        entries: [
          PlannedArchiveEntry(
            relativePath: "a", sourcePathSHA256: zeroHash, kind: .regularFile,
            declaredSize: 1, sourcePermissions: 0o644, normalizedPermissions: 0o700)
        ],
        archiveByteSize: 1,
        totalRegularFileBytes: 1
      ),
      SafeArchivePlan(
        policyVersion: 1, entries: [baseEntry], archiveByteSize: 2,
        totalRegularFileBytes: 1),
      SafeArchivePlan(
        policyVersion: 1, entries: [baseEntry], archiveByteSize: 1,
        totalRegularFileBytes: 2),
    ]
    #expect(Set(plans.map(\.canonicalSHA256)).count == plans.count)

    let baseTreeEntry = StagingTreeSealEntry(
      relativePath: "a", kind: .regularFile, size: 1, mode: 0o600,
      contentSHA256: zeroHash)
    let treeEntries = [
      baseTreeEntry,
      StagingTreeSealEntry(
        relativePath: "aa", kind: .regularFile, size: 1, mode: 0o600,
        contentSHA256: zeroHash),
      StagingTreeSealEntry(
        relativePath: "a", kind: .regularFile, size: 2, mode: 0o600,
        contentSHA256: zeroHash),
      StagingTreeSealEntry(
        relativePath: "a", kind: .regularFile, size: 1, mode: 0o700,
        contentSHA256: zeroHash),
      StagingTreeSealEntry(
        relativePath: "a", kind: .regularFile, size: 1, mode: 0o600,
        contentSHA256: oneHash),
      StagingTreeSealEntry(
        relativePath: "a", kind: .directory, size: 0, mode: 0o700,
        contentSHA256: nil),
    ]
    let treeDigests = treeEntries.map {
      SafeStagingTreeSealer.canonicalSHA256(for: [$0])
    }
    #expect(Set(treeDigests).count == treeEntries.count)
  }

  private func extract(
    plan: SafeArchivePlan,
    descriptors: [ArchiveEntryDescriptor],
    content: Data,
    chunkSize: Int,
    root: URL
  ) throws -> ExtractedStagingTree {
    let source = SealArchiveSource(
      artifactSHA256: artifactSHA256,
      descriptors: descriptors,
      contents: [pathDigest("Bin/Tool"): content],
      chunkSize: chunkSize
    )
    return try SafeStagingExtractor.extract(
      plan: plan,
      expectedArtifactSHA256: artifactSHA256,
      toNewRoot: root,
      source: source
    )
  }

  private func descriptor(
    _ path: String,
    kind: ArchiveEntryKind = .regularFile,
    size: UInt64 = 0,
    permissions: UInt32 = 0o644
  ) -> ArchiveEntryDescriptor {
    .init(path: path, kind: kind, declaredSize: size, permissions: permissions)
  }

  private func pathDigest(_ value: String) -> String {
    sha256(Data(value.utf8))
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func withPrivateParent<T>(_ body: (URL) throws -> T) throws -> T {
    var canonicalPath = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(FileManager.default.temporaryDirectory.path, &canonicalPath) != nil else {
      throw currentSealTestPOSIXError()
    }
    let terminator = canonicalPath.firstIndex(of: 0) ?? canonicalPath.endIndex
    let parent = URL(
      fileURLWithPath: String(
        decoding: canonicalPath[..<terminator].map { UInt8(bitPattern: $0) },
        as: UTF8.self
      ),
      isDirectory: true
    )
    .appendingPathComponent("MacGameBridgeSealTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
    defer { try? FileManager.default.removeItem(at: parent) }
    return try body(parent)
  }
}

private final class SealArchiveSource: ArchivePlannedContentSource {
  let artifactSHA256: String
  let entryCount: Int
  private let descriptors: [String: ArchiveEntryDescriptor]
  private let contents: [String: Data]
  private let chunkSize: Int
  private let finishHook: (() throws -> Void)?
  private var requested = Set<String>()

  init(
    artifactSHA256: String,
    descriptors: [ArchiveEntryDescriptor],
    contents: [String: Data],
    chunkSize: Int,
    finishHook: (() throws -> Void)? = nil
  ) {
    self.artifactSHA256 = artifactSHA256
    entryCount = descriptors.count
    self.descriptors = Dictionary(
      uniqueKeysWithValues: descriptors.map { (sealSHA256(Data($0.path.utf8)), $0) }
    )
    self.contents = contents
    self.chunkSize = chunkSize
    self.finishHook = finishHook
  }

  func descriptor(forSourcePathSHA256 digest: String) throws -> ArchiveEntryDescriptor {
    requested.insert(digest)
    guard let descriptor = descriptors[digest] else { throw SealTestError.missing }
    return descriptor
  }

  func reader(for entry: PlannedArchiveEntry) throws -> any ArchiveEntryContentReading {
    guard let content = contents[entry.sourcePathSHA256] else { throw SealTestError.missing }
    return SealDataReader(data: content, chunkSize: chunkSize)
  }

  func finish() throws {
    try finishHook?()
    guard requested.count == entryCount else { throw SealTestError.missing }
  }
}

private final class SealDataReader: ArchiveEntryContentReading {
  private let data: Data
  private let chunkSize: Int
  private var offset = 0

  init(data: Data, chunkSize: Int) {
    self.data = data
    self.chunkSize = max(1, chunkSize)
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard offset < data.count else { return 0 }
    let count = min(buffer.count, chunkSize, data.count - offset)
    data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: offset..<(offset + count))
    offset += count
    return count
  }
}

private enum SealTestError: Error {
  case missing
}

private func sealSHA256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func overwriteInPlace(_ url: URL, with data: Data) throws {
  let descriptor = open(url.path, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC)
  guard descriptor >= 0 else { throw currentSealTestPOSIXError() }
  defer { _ = close(descriptor) }
  try data.withUnsafeBytes { bytes in
    var offset = 0
    while offset < bytes.count {
      let count = write(
        descriptor,
        bytes.baseAddress?.advanced(by: offset),
        bytes.count - offset
      )
      guard count > 0 else { throw currentSealTestPOSIXError() }
      offset += count
    }
  }
  guard fsync(descriptor) == 0 else { throw currentSealTestPOSIXError() }
}

private func currentSealTestPOSIXError() -> POSIXError {
  POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
