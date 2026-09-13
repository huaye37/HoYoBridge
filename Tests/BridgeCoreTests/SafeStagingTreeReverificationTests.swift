import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

@Suite(.serialized)
struct SafeStagingTreeReverificationTests {
  private let artifactSHA256 = String(repeating: "a", count: 64)

  @Test
  func reverifiesUnchangedSealedTree() throws {
    try withPrivateParent { parent in
      let candidate = try makeCandidate(in: parent, name: "valid")
      try SafeStagingExtractor.reverify(candidate)
    }
  }

  @Test
  func rejectsSameSizeContentMutation() throws {
    try withPrivateParent { parent in
      let candidate = try makeCandidate(in: parent, name: "content")
      try overwrite(
        candidate.rootURL.appendingPathComponent("bin/tool"),
        with: Data("evil".utf8)
      )

      #expect(throws: (any Error).self) {
        try SafeStagingExtractor.reverify(candidate)
      }
    }
  }

  @Test
  func rejectsRootReplacement() throws {
    try withPrivateParent { parent in
      let candidate = try makeCandidate(in: parent, name: "root")
      let original = parent.appendingPathComponent("original-root")
      guard rename(candidate.rootURL.path, original.path) == 0 else {
        throw currentReverificationTestPOSIXError()
      }
      try FileManager.default.createDirectory(
        at: candidate.rootURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: candidate.rootURL.path
      )

      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.reverify(candidate)
      }
    }
  }

  @Test
  func rejectsExtraAndMissingEntries() throws {
    try withPrivateParent { parent in
      let extra = try makeCandidate(in: parent, name: "extra")
      let extraFile = extra.rootURL.appendingPathComponent("extra")
      try Data([1]).write(to: extraFile)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: extraFile.path
      )
      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.reverify(extra)
      }

      let missing = try makeCandidate(in: parent, name: "missing")
      guard unlink(missing.rootURL.appendingPathComponent("bin/tool").path) == 0 else {
        throw currentReverificationTestPOSIXError()
      }
      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.reverify(missing)
      }
    }
  }

  @Test
  func rejectsSymlinkReplacingPlannedFile() throws {
    try withPrivateParent { parent in
      let candidate = try makeCandidate(in: parent, name: "symlink")
      let file = candidate.rootURL.appendingPathComponent("bin/tool")
      let outside = parent.appendingPathComponent("outside")
      try Data("tool".utf8).write(to: outside)
      guard unlink(file.path) == 0 else { throw currentReverificationTestPOSIXError() }
      try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)

      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.reverify(candidate)
      }
      #expect(try Data(contentsOf: outside) == Data("tool".utf8))
    }
  }

  private func makeCandidate(in parent: URL, name: String) throws -> ExtractedStagingTree {
    let descriptors = [
      ArchiveEntryDescriptor(
        path: "bin/",
        kind: .directory,
        declaredSize: 0,
        permissions: 0o755
      ),
      ArchiveEntryDescriptor(
        path: "bin/tool",
        kind: .regularFile,
        declaredSize: 4,
        permissions: 0o755
      ),
    ]
    let plan = try SafeArchivePlanner.plan(entries: descriptors, archiveByteSize: 4)
    let source = ReverificationArchiveSource(
      artifactSHA256: artifactSHA256,
      descriptors: descriptors,
      contents: [reverificationSHA256(Data("bin/tool".utf8)): Data("tool".utf8)]
    )
    return try SafeStagingExtractor.extract(
      plan: plan,
      expectedArtifactSHA256: artifactSHA256,
      toNewRoot: parent.appendingPathComponent(name),
      source: source
    )
  }

  private func withPrivateParent<T>(_ body: (URL) throws -> T) throws -> T {
    var canonicalPath = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(FileManager.default.temporaryDirectory.path, &canonicalPath) != nil else {
      throw currentReverificationTestPOSIXError()
    }
    let terminator = canonicalPath.firstIndex(of: 0) ?? canonicalPath.endIndex
    let parent = URL(
      fileURLWithPath: String(
        decoding: canonicalPath[..<terminator].map { UInt8(bitPattern: $0) },
        as: UTF8.self
      ),
      isDirectory: true
    )
    .appendingPathComponent("MacGameBridgeReverifyTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
    defer { try? FileManager.default.removeItem(at: parent) }
    return try body(parent)
  }
}

private final class ReverificationArchiveSource: ArchivePlannedContentSource {
  let artifactSHA256: String
  let entryCount: Int
  private let descriptors: [String: ArchiveEntryDescriptor]
  private let contents: [String: Data]
  private var requested = Set<String>()

  init(
    artifactSHA256: String,
    descriptors: [ArchiveEntryDescriptor],
    contents: [String: Data]
  ) {
    self.artifactSHA256 = artifactSHA256
    entryCount = descriptors.count
    self.descriptors = Dictionary(
      uniqueKeysWithValues: descriptors.map {
        (reverificationSHA256(Data($0.path.utf8)), $0)
      }
    )
    self.contents = contents
  }

  func descriptor(forSourcePathSHA256 digest: String) throws -> ArchiveEntryDescriptor {
    requested.insert(digest)
    guard let descriptor = descriptors[digest] else { throw ReverificationTestError.missing }
    return descriptor
  }

  func reader(for entry: PlannedArchiveEntry) throws -> any ArchiveEntryContentReading {
    guard let data = contents[entry.sourcePathSHA256] else {
      throw ReverificationTestError.missing
    }
    return ReverificationDataReader(data)
  }

  func finish() throws {
    guard requested.count == entryCount else { throw ReverificationTestError.missing }
  }
}

private final class ReverificationDataReader: ArchiveEntryContentReading {
  private let data: Data
  private var offset = 0

  init(_ data: Data) {
    self.data = data
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard offset < data.count else { return 0 }
    let count = min(buffer.count, data.count - offset)
    data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: offset..<(offset + count))
    offset += count
    return count
  }
}

private enum ReverificationTestError: Error {
  case missing
}

private func overwrite(_ url: URL, with data: Data) throws {
  let descriptor = open(url.path, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC)
  guard descriptor >= 0 else { throw currentReverificationTestPOSIXError() }
  defer { _ = close(descriptor) }
  try data.withUnsafeBytes { bytes in
    var offset = 0
    while offset < bytes.count {
      let count = write(
        descriptor,
        bytes.baseAddress?.advanced(by: offset),
        bytes.count - offset
      )
      if count < 0, errno == EINTR { continue }
      guard count > 0 else { throw currentReverificationTestPOSIXError() }
      offset += count
    }
  }
  guard fsync(descriptor) == 0 else { throw currentReverificationTestPOSIXError() }
}

private func reverificationSHA256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func currentReverificationTestPOSIXError() -> POSIXError {
  POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
