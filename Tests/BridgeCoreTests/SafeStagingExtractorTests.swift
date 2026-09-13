import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

@Suite(.serialized)
struct SafeStagingExtractorTests {
  private let artifactSHA256 = String(repeating: "a", count: 64)

  @Test
  func writesValidatedTreeWithImplicitParentsAndNormalizedModes() throws {
    try withPrivateParent { parent in
      let descriptors = [
        descriptor("runtime/", kind: .directory, permissions: 0o755),
        descriptor("runtime/bin/tool", size: 4, permissions: 0o755),
        descriptor("runtime/config.json", size: 6, permissions: 0o644),
      ]
      let plan = try SafeArchivePlanner.plan(entries: descriptors, archiveByteSize: 10)
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: descriptors,
        contents: [
          digest("runtime/bin/tool"): Data("tool".utf8),
          digest("runtime/config.json"): Data("config".utf8),
        ],
        chunkSize: 2
      )
      let root = parent.appendingPathComponent("staging", isDirectory: true)

      let result = try SafeStagingExtractor.extract(
        plan: plan,
        expectedArtifactSHA256: artifactSHA256,
        toNewRoot: root,
        source: source
      )

      #expect(result.rootURL == root)
      #expect(result.regularFileCount == 2)
      #expect(result.totalBytes == 10)
      #expect(
        try Data(contentsOf: root.appendingPathComponent("runtime/bin/tool")) == Data("tool".utf8))
      #expect(
        try Data(contentsOf: root.appendingPathComponent("runtime/config.json"))
          == Data("config".utf8))
      #expect(try permissions(root.appendingPathComponent("runtime/bin/tool")) == 0o700)
      #expect(try permissions(root.appendingPathComponent("runtime/config.json")) == 0o600)
      #expect(try permissions(root.appendingPathComponent("runtime")) == 0o700)
      #expect(source.finishCallCount == 1)
      #expect(source.readerRequestCount == 2)
    }
  }

  @Test
  func rejectsShortAndOversizedContentAndCleansOnlyNewRoot() throws {
    try withPrivateParent { parent in
      let sibling = parent.appendingPathComponent("keep.txt")
      try Data("keep".utf8).write(to: sibling)
      for content in [Data("abc".utf8), Data("abcde".utf8)] {
        let descriptor = descriptor("file", size: 4)
        let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
        let source = MemoryArchiveSource(
          artifactSHA256: artifactSHA256,
          descriptors: [descriptor],
          contents: [digest("file"): content]
        )
        let root = parent.appendingPathComponent("staging-\(content.count)", isDirectory: true)

        #expect(throws: (any Error).self) {
          try SafeStagingExtractor.extract(
            plan: plan,
            expectedArtifactSHA256: artifactSHA256,
            toNewRoot: root,
            source: source
          )
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try Data(contentsOf: sibling) == Data("keep".utf8))
      }
    }
  }

  @Test
  func readerErrorAndInvalidCountCleanStaging() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let failing = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        readerFactories: [digest("file"): { ThrowingReader() }]
      )
      let failingRoot = parent.appendingPathComponent("failing", isDirectory: true)
      #expect(throws: ReaderTestError.failed) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: failingRoot,
          source: failing
        )
      }
      #expect(!FileManager.default.fileExists(atPath: failingRoot.path))

      let invalid = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        readerFactories: [digest("file"): { InvalidCountReader() }]
      )
      let invalidRoot = parent.appendingPathComponent("invalid", isDirectory: true)
      #expect(throws: SafeStagingExtractionError.invalidReaderCount(1_048_577)) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: invalidRoot,
          source: invalid
        )
      }
      #expect(!FileManager.default.fileExists(atPath: invalidRoot.path))
    }
  }

  @Test
  func rejectsExistingRootAndUnsafeOrSymlinkParent() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file")
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data()]
      )
      let existing = parent.appendingPathComponent("existing", isDirectory: true)
      try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
      #expect(throws: SafeStagingExtractionError.stagingRootAlreadyExists) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: existing,
          source: source
        )
      }
      #expect(FileManager.default.fileExists(atPath: existing.path))

      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
      #expect(throws: SafeStagingExtractionError.unsafeParentDirectory) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: parent.appendingPathComponent("unsafe"),
          source: source
        )
      }

      let nonCanonical = URL(
        fileURLWithPath: parent.path + "/missing/../noncanonical",
        isDirectory: true
      )
      #expect(throws: SafeStagingExtractionError.invalidStagingRoot) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: nonCanonical,
          source: source
        )
      }
    }

    try withPrivateParent { parent in
      let actualParent = parent.appendingPathComponent("actual", isDirectory: true)
      try FileManager.default.createDirectory(at: actualParent, withIntermediateDirectories: false)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: actualParent.path)
      let link = parent.appendingPathComponent("parent-link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actualParent)
      let plan = try SafeArchivePlanner.plan(entries: [], archiveByteSize: 1)
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [],
        contents: [:]
      )
      #expect(throws: SafeStagingExtractionError.unsafeParentDirectory) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: link.appendingPathComponent("staging"),
          source: source
        )
      }
    }
  }

  @Test
  func rejectsArtifactCountAndDescriptorIdentityBeforePublishing() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let wrongArtifact = MemoryArchiveSource(
        artifactSHA256: String(repeating: "b", count: 64),
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])]
      )
      #expect(throws: SafeStagingExtractionError.invalidArtifactIdentity) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: parent.appendingPathComponent("artifact"),
          source: wrongArtifact
        )
      }

      let wrongCount = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        entryCountOverride: 2
      )
      #expect(throws: SafeStagingExtractionError.sourceEntryCountMismatch(expected: 1, actual: 2)) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: parent.appendingPathComponent("count"),
          source: wrongCount
        )
      }

      let changedDescriptor = self.descriptor("other", size: 1)
      let mismatch = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        descriptorOverrides: [digest("file"): changedDescriptor]
      )
      let mismatchRoot = parent.appendingPathComponent("descriptor")
      #expect(throws: SafeStagingExtractionError.sourceDescriptorMismatch) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: mismatchRoot,
          source: mismatch
        )
      }
      #expect(!FileManager.default.fileExists(atPath: mismatchRoot.path))
    }
  }

  @Test
  func finishFailureAndCancellationCleanStaging() async throws {
    try await withPrivateParentAsync { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let finishFailure = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        finishError: ReaderTestError.failed
      )
      let finishRoot = parent.appendingPathComponent("finish")
      #expect(throws: ReaderTestError.failed) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: finishRoot,
          source: finishFailure
        )
      }
      #expect(!FileManager.default.fileExists(atPath: finishRoot.path))

      let cancelledSource = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])]
      )
      let cancelRoot = parent.appendingPathComponent("cancel")
      let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        return try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: self.artifactSHA256,
          toNewRoot: cancelRoot,
          source: cancelledSource
        )
      }
      task.cancel()
      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(!FileManager.default.fileExists(atPath: cancelRoot.path))
    }
  }

  @Test
  func cleanupUnlinksInjectedSymlinkWithoutTouchingTarget() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let outside = parent.appendingPathComponent("outside.txt")
      try Data("outside".utf8).write(to: outside)
      let staging = parent.appendingPathComponent("staging")
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        readerFactories: [
          digest("file"): {
            HookReader {
              try FileManager.default.createSymbolicLink(
                at: staging.appendingPathComponent("injected-link"),
                withDestinationURL: outside
              )
              throw ReaderTestError.failed
            }
          }
        ]
      )

      #expect(throws: ReaderTestError.failed) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: staging,
          source: source
        )
      }
      #expect(!FileManager.default.fileExists(atPath: staging.path))
      #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }
  }

  @Test
  func inFlightCancellationCleansPartiallyWrittenTree() async throws {
    try await withPrivateParentAsync { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let root = parent.appendingPathComponent("cancel-in-flight")
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        readerFactories: [digest("file"): { CancellingReader() }]
      )
      let task = Task {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: root,
          source: source
        )
      }

      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(!FileManager.default.fileExists(atPath: root.path))
    }
  }

  @Test
  func cleanupFailurePreservesBothPrimaryAndSecondaryErrors() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let root = parent.appendingPathComponent("cleanup-failure")
      let outside = parent.appendingPathComponent("outside")
      try Data("outside".utf8).write(to: outside)
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        readerFactories: [
          digest("file"): {
            HookReader {
              let injected = root.appendingPathComponent("injected-hardlink")
              guard link(outside.path, injected.path) == 0 else { throw currentTestPOSIXError() }
              throw ReaderTestError.failed
            }
          }
        ]
      )

      do {
        _ = try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: root,
          source: source
        )
        Issue.record("Expected extraction and cleanup to fail")
      } catch let error as SafeStagingExtractionAndCleanupError {
        #expect(error.extractionError as? ReaderTestError == .failed)
        #expect(error.cleanupError as? SafeStagingExtractionError == .cleanupFailed)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
      #expect(FileManager.default.fileExists(atPath: root.path))
      #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }
  }

  @Test
  func finalInventoryRejectsExtraFileAndChangedRootMode() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)

      let extraRoot = parent.appendingPathComponent("extra-root")
      let extraSource = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        finishHook: {
          let extra = extraRoot.appendingPathComponent("extra")
          try Data([2]).write(to: extra)
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: extra.path
          )
        }
      )
      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: extraRoot,
          source: extraSource
        )
      }
      #expect(!FileManager.default.fileExists(atPath: extraRoot.path))

      let modeRoot = parent.appendingPathComponent("mode-root")
      let modeSource = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        finishHook: {
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: modeRoot.path
          )
        }
      )
      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: modeRoot,
          source: modeSource
        )
      }
      #expect(!FileManager.default.fileExists(atPath: modeRoot.path))
    }
  }

  @Test
  func finalSyncFailureReenumeratesAndCleansInjectedSymlink() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let root = parent.appendingPathComponent("final-symlink")
      let outside = parent.appendingPathComponent("outside-final")
      try Data("outside".utf8).write(to: outside)
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        finishHook: {
          try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("extra-link"),
            withDestinationURL: outside
          )
        }
      )

      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
        try SafeStagingExtractor.extract(
          plan: plan,
          expectedArtifactSHA256: artifactSHA256,
          toNewRoot: root,
          source: source
        )
      }
      #expect(!FileManager.default.fileExists(atPath: root.path))
      #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }
  }

  @Test
  func finalInventoryRejectsSameShapeFileReplacement() throws {
    try withPrivateParent { parent in
      let descriptor = descriptor("file", size: 1)
      let plan = try SafeArchivePlanner.plan(entries: [descriptor], archiveByteSize: 1)
      let root = parent.appendingPathComponent("replaced-file")
      let source = MemoryArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: [descriptor],
        contents: [digest("file"): Data([1])],
        finishHook: {
          let file = root.appendingPathComponent("file")
          guard unlink(file.path) == 0 else { throw currentTestPOSIXError() }
          try Data([2]).write(to: file)
          try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path
          )
        }
      )

      #expect(throws: SafeStagingExtractionError.unsafeFilesystemEntry) {
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

  private func descriptor(
    _ path: String,
    kind: ArchiveEntryKind = .regularFile,
    size: UInt64 = 0,
    permissions: UInt32 = 0o644
  ) -> ArchiveEntryDescriptor {
    .init(
      path: path,
      kind: kind,
      declaredSize: size,
      permissions: permissions
    )
  }

  private func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func permissions(_ url: URL) throws -> mode_t {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw currentTestPOSIXError() }
    return metadata.st_mode & 0o777
  }

  private func withPrivateParent<T>(_ body: (URL) throws -> T) throws -> T {
    let parent = try makePrivateParent()
    defer { try? FileManager.default.removeItem(at: parent) }
    return try body(parent)
  }

  private func withPrivateParentAsync<T>(_ body: (URL) async throws -> T) async throws -> T {
    let parent = try makePrivateParent()
    defer { try? FileManager.default.removeItem(at: parent) }
    return try await body(parent)
  }

  private func makePrivateParent() throws -> URL {
    var canonicalPath = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(FileManager.default.temporaryDirectory.path, &canonicalPath) != nil else {
      throw currentTestPOSIXError()
    }
    let terminator = canonicalPath.firstIndex(of: 0) ?? canonicalPath.endIndex
    let parent = URL(
      fileURLWithPath: String(
        decoding: canonicalPath[..<terminator].map { UInt8(bitPattern: $0) },
        as: UTF8.self
      ),
      isDirectory: true
    )
    .appendingPathComponent(
      "MacGameBridgeStagingTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
    return parent
  }
}

private enum ReaderTestError: Error, Equatable {
  case failed
  case missingDescriptor
  case missingContent
  case unfinishedSource
}

private final class MemoryArchiveSource: ArchivePlannedContentSource, @unchecked Sendable {
  let artifactSHA256: String
  let entryCount: Int
  private let descriptors: [String: ArchiveEntryDescriptor]
  private let descriptorOverrides: [String: ArchiveEntryDescriptor]
  private let contents: [String: Data]
  private let readerFactories: [String: () -> any ArchiveEntryContentReading]
  private let chunkSize: Int
  private let finishError: (any Error)?
  private let finishHook: (() throws -> Void)?
  private(set) var finishCallCount = 0
  private(set) var readerRequestCount = 0
  private var descriptorRequests = Set<String>()

  init(
    artifactSHA256: String,
    descriptors: [ArchiveEntryDescriptor],
    contents: [String: Data] = [:],
    readerFactories: [String: () -> any ArchiveEntryContentReading] = [:],
    chunkSize: Int = 1_024,
    entryCountOverride: Int? = nil,
    descriptorOverrides: [String: ArchiveEntryDescriptor] = [:],
    finishError: (any Error)? = nil,
    finishHook: (() throws -> Void)? = nil
  ) {
    self.artifactSHA256 = artifactSHA256
    entryCount = entryCountOverride ?? descriptors.count
    self.descriptors = Dictionary(
      uniqueKeysWithValues: descriptors.map { (Self.digest($0.path), $0) }
    )
    self.descriptorOverrides = descriptorOverrides
    self.contents = contents
    self.readerFactories = readerFactories
    self.chunkSize = chunkSize
    self.finishError = finishError
    self.finishHook = finishHook
  }

  func descriptor(forSourcePathSHA256 digest: String) throws -> ArchiveEntryDescriptor {
    descriptorRequests.insert(digest)
    if let overridden = descriptorOverrides[digest] { return overridden }
    guard let descriptor = descriptors[digest] else { throw ReaderTestError.missingDescriptor }
    return descriptor
  }

  func reader(for entry: PlannedArchiveEntry) throws -> any ArchiveEntryContentReading {
    readerRequestCount += 1
    if let factory = readerFactories[entry.sourcePathSHA256] { return factory() }
    guard let data = contents[entry.sourcePathSHA256] else {
      throw ReaderTestError.missingContent
    }
    return DataChunkReader(data: data, chunkSize: chunkSize)
  }

  func finish() throws {
    finishCallCount += 1
    try finishHook?()
    if let finishError { throw finishError }
    guard descriptorRequests.count == entryCount else { throw ReaderTestError.unfinishedSource }
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

private final class DataChunkReader: ArchiveEntryContentReading {
  private let data: Data
  private let chunkSize: Int
  private var offset = 0

  init(data: Data, chunkSize: Int) {
    self.data = data
    self.chunkSize = max(1, chunkSize)
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard offset < data.count else { return 0 }
    let count = min(chunkSize, buffer.count, data.count - offset)
    data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: offset..<(offset + count))
    offset += count
    return count
  }
}

private final class ThrowingReader: ArchiveEntryContentReading {
  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    throw ReaderTestError.failed
  }
}

private final class InvalidCountReader: ArchiveEntryContentReading {
  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    buffer.count + 1
  }
}

private final class HookReader: ArchiveEntryContentReading {
  private let hook: () throws -> Void
  private var invoked = false

  init(hook: @escaping () throws -> Void) {
    self.hook = hook
  }

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard !invoked else { return 0 }
    invoked = true
    try hook()
    return 0
  }
}

private final class CancellingReader: ArchiveEntryContentReading {
  private var emitted = false

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard !emitted else { return 0 }
    emitted = true
    withUnsafeCurrentTask { $0?.cancel() }
    guard !buffer.isEmpty else { return 0 }
    buffer[0] = 1
    return 1
  }
}

private func currentTestPOSIXError() -> POSIXError {
  POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
