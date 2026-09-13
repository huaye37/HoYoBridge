import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct ArtifactStoreTests {
  @Test
  func verifierChecksSizeAndHash() throws {
    try withTemporaryDirectory { directory in
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("hello".utf8)
      try data.write(to: source)
      let expectedRuntime = runtime(for: data)

      let verified = try ArtifactVerifier.verify(fileAt: source, for: expectedRuntime)
      #expect(verified.byteSize == 5)
      #expect(verified.sha256 == digest(data))

      let wrongSize = runtime(for: data, byteSize: 6)
      #expect(throws: ArtifactVerificationError.sizeMismatch(expected: 6, actual: 5)) {
        try ArtifactVerifier.verify(fileAt: source, for: wrongSize)
      }

      let wrongHash = runtime(for: data, sha256: String(repeating: "0", count: 64))
      #expect(
        throws: ArtifactVerificationError.hashMismatch(
          expected: String(repeating: "0", count: 64), actual: digest(data))
      ) {
        try ArtifactVerifier.verify(fileAt: source, for: wrongHash)
      }
    }
  }

  @Test
  func storeCommitsVerifiedArtifactAndReusesIt() throws {
    try withTemporaryDirectory { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("verified runtime archive".utf8)
      try data.write(to: source)
      let runtime = runtime(for: data)
      let store = ContentAddressedArtifactStore(rootURL: cache)

      let first = try store.store(fileAt: source, for: runtime)
      let second = try store.store(fileAt: source, for: runtime)

      #expect(first.disposition == .stored)
      #expect(second.disposition == .reused)
      #expect(first.url == second.url)
      #expect(try Data(contentsOf: first.url) == data)
      #expect(first.url.lastPathComponent == digest(data))
      #expect(
        first.url.deletingLastPathComponent().lastPathComponent == String(digest(data).prefix(2)))
    }
  }

  @Test
  func failedVerificationLeavesNoCommittedOrStagingArtifact() throws {
    try withTemporaryDirectory { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let source = directory.appendingPathComponent("source.bin")
      let expected = Data("expected".utf8)
      let damaged = Data("damagede".utf8)
      try damaged.write(to: source)
      let runtime = runtime(for: expected)
      let store = ContentAddressedArtifactStore(rootURL: cache)

      #expect(
        throws: ArtifactVerificationError.hashMismatch(
          expected: digest(expected), actual: digest(damaged))
      ) {
        try store.store(fileAt: source, for: runtime)
      }

      let stagingDirectory = cache.appendingPathComponent(".staging", isDirectory: true)
      let stagingEntries = try FileManager.default.contentsOfDirectory(
        atPath: stagingDirectory.path)
      #expect(stagingEntries.isEmpty)
      let destination =
        cache
        .appendingPathComponent("objects/sha256/\(digest(expected).prefix(2))/\(digest(expected))")
      #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
  }

  @Test
  func corruptCacheEntryFailsClosedWithoutOverwrite() throws {
    try withTemporaryDirectory { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("correct".utf8)
      let corrupt = Data("corrupt".utf8)
      try data.write(to: source)
      let runtime = runtime(for: data)
      let store = ContentAddressedArtifactStore(rootURL: cache)

      let first = try store.store(fileAt: source, for: runtime)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: first.url.path)
      try corrupt.write(to: first.url)
      #expect(throws: ArtifactStoreError.corruptExistingObject(first.url.path)) {
        try store.store(fileAt: source, for: runtime)
      }
      #expect(try Data(contentsOf: first.url) == corrupt)
    }
  }

  @Test
  func cacheRootMustBePrivate() throws {
    try withTemporaryDirectory { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      try FileManager.default.createDirectory(
        at: cache,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: cache.path
      )
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("private cache".utf8)
      try data.write(to: source)

      #expect(throws: ArtifactStoreError.unsafeCacheDirectory(cache.path)) {
        try ContentAddressedArtifactStore(rootURL: cache).store(
          fileAt: source,
          for: runtime(for: data)
        )
      }
    }
  }

  @Test
  func concurrentStoresProduceOneArtifact() async throws {
    try await withTemporaryDirectoryAsync { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("concurrent verified archive".utf8)
      try data.write(to: source)
      let runtime = runtime(for: data)
      let store = ContentAddressedArtifactStore(rootURL: cache)

      let dispositions = try await withThrowingTaskGroup(of: ArtifactStoreDisposition.self) {
        group in
        for _ in 0..<8 {
          group.addTask {
            try store.store(fileAt: source, for: runtime).disposition
          }
        }
        var values: [ArtifactStoreDisposition] = []
        for try await value in group { values.append(value) }
        return values
      }

      #expect(dispositions.filter { $0 == .stored }.count == 1)
      #expect(dispositions.filter { $0 == .reused || $0 == .concurrentCacheHit }.count == 7)
      #expect(
        try FileManager.default.contentsOfDirectory(
          atPath: cache.appendingPathComponent(".staging").path
        ).isEmpty
      )

      let destination =
        cache
        .appendingPathComponent("objects/sha256/\(digest(data).prefix(2))/\(digest(data))")
      #expect(try Data(contentsOf: destination) == data)
    }
  }

  @Test
  func cancelledStoreLeavesNoStagingOrCommittedArtifact() async throws {
    try await withTemporaryDirectoryAsync { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let staging = cache.appendingPathComponent(".staging", isDirectory: true)
      try FileManager.default.createDirectory(
        at: staging,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("cancelled archive".utf8)
      try data.write(to: source)
      let runtime = runtime(for: data)
      let store = ContentAddressedArtifactStore(rootURL: cache)

      let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        return try store.store(fileAt: source, for: runtime)
      }
      task.cancel()

      await #expect(throws: CancellationError.self) {
        try await task.value
      }
      #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
      let destination =
        cache
        .appendingPathComponent("objects/sha256/\(digest(data).prefix(2))/\(digest(data))")
      #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
  }

  @Test
  func cancelledReuseLeavesExistingObjectUntouched() async throws {
    try await withTemporaryDirectoryAsync { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("reusable archive".utf8)
      try data.write(to: source)
      let runtime = runtime(for: data)
      let store = ContentAddressedArtifactStore(rootURL: cache)
      let stored = try store.store(fileAt: source, for: runtime)

      let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        return try store.store(fileAt: source, for: runtime)
      }
      task.cancel()

      await #expect(throws: CancellationError.self) {
        try await task.value
      }
      #expect(try Data(contentsOf: stored.url) == data)
    }
  }

  @Test
  func danglingFinalEntryWinsRenameButFailsClosed() throws {
    try withTemporaryDirectory { directory in
      let cache = directory.appendingPathComponent("cache", isDirectory: true)
      let source = directory.appendingPathComponent("source.bin")
      let data = Data("correct candidate".utf8)
      try data.write(to: source)
      let hash = digest(data)
      let objectDirectory = cache.appendingPathComponent(
        "objects/sha256/\(hash.prefix(2))",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: objectDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      let destination = objectDirectory.appendingPathComponent(hash)
      try FileManager.default.createSymbolicLink(
        atPath: destination.path,
        withDestinationPath: "missing-winner"
      )

      #expect(throws: ArtifactStoreError.corruptExistingObject(destination.path)) {
        try ContentAddressedArtifactStore(rootURL: cache).store(
          fileAt: source,
          for: runtime(for: data)
        )
      }
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
          == "missing-winner"
      )
      let staging = cache.appendingPathComponent(".staging", isDirectory: true)
      #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }
  }

  @Test
  func symbolicLinkSourceIsRejected() throws {
    try withTemporaryDirectory { directory in
      let target = directory.appendingPathComponent("target.bin")
      let link = directory.appendingPathComponent("source-link.bin")
      let data = Data("linked archive".utf8)
      try data.write(to: target)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

      #expect(throws: ArtifactVerificationError.sourceIsNotRegularFile(link.path)) {
        try ArtifactVerifier.verify(fileAt: link, for: runtime(for: data))
      }
    }
  }

  @Test
  func danglingSymbolicLinkDoesNotLeaveStagingFile() throws {
    try withTemporaryDirectory { directory in
      let link = directory.appendingPathComponent("dangling.bin")
      try FileManager.default.createSymbolicLink(
        atPath: link.path,
        withDestinationPath: "missing.bin"
      )
      let data = Data("expected bytes".utf8)
      let cache = directory.appendingPathComponent("cache", isDirectory: true)

      #expect(throws: ArtifactVerificationError.sourceIsNotRegularFile(link.path)) {
        try ContentAddressedArtifactStore(rootURL: cache).store(
          fileAt: link,
          for: runtime(for: data)
        )
      }
      let staging = cache.appendingPathComponent(".staging", isDirectory: true)
      #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }
  }

  private func runtime(
    for data: Data,
    byteSize: UInt64? = nil,
    sha256: String? = nil
  ) -> RuntimeDefinition {
    RuntimeDefinition(
      id: "runtime-test",
      backend: .dxmt,
      version: "1.0.0",
      verification: .candidate,
      acquisition: .managedDownload,
      sourceURL: "https://downloads.example.invalid/runtime-1.0.zip",
      byteSize: byteSize ?? UInt64(data.count),
      sha256: sha256 ?? digest(data),
      license: "MIT",
      redistributable: true
    )
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacGameBridgeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
  }

  private func withTemporaryDirectoryAsync<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacGameBridgeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
  }
}
