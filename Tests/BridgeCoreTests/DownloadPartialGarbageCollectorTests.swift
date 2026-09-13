import Darwin
import Foundation
import Testing

@testable import BridgeCore

struct DownloadPartialGarbageCollectorTests {
  private let cutoff = Date(timeIntervalSince1970: 2_000_000_000)

  @Test
  func removesExpiredPairAndKeepsLease() throws {
    try withFixture { fixture in
      let hash = String(repeating: "a", count: 64)
      try fixture.createCandidate(hash: hash, suffix: ".part", modified: oldDate)
      try fixture.createCandidate(hash: hash, suffix: ".resume.json", modified: oldDate)
      let lease = try fixture.createLease(hash: hash)
      let leaseIdentity = try identity(of: lease)

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report.cleaned == [hash])
      #expect(report.skippedBusy.isEmpty)
      #expect(report.unsafe.isEmpty)
      #expect(!fixture.candidateExists(hash: hash, suffix: ".part"))
      #expect(!fixture.candidateExists(hash: hash, suffix: ".resume.json"))
      #expect(try identity(of: lease) == leaseIdentity)
    }
  }

  @Test
  func retainsFreshPair() throws {
    try withFixture { fixture in
      let hash = String(repeating: "b", count: 64)
      try fixture.createCandidate(hash: hash, suffix: ".part", modified: freshDate)
      try fixture.createCandidate(hash: hash, suffix: ".resume.json", modified: freshDate)

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report == .init(cleaned: [], skippedBusy: [], unsafe: []))
      #expect(fixture.candidateExists(hash: hash, suffix: ".part"))
      #expect(fixture.candidateExists(hash: hash, suffix: ".resume.json"))
    }
  }

  @Test
  func skipsBusyLease() throws {
    try withFixture { fixture in
      let hash = String(repeating: "c", count: 64)
      try fixture.createCandidate(hash: hash, suffix: ".part", modified: oldDate)
      try fixture.createCandidate(hash: hash, suffix: ".resume.json", modified: oldDate)
      let lease = try fixture.createLease(hash: hash)
      let descriptor = open(lease.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw currentPOSIXError() }
      defer {
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
      }
      guard flock(descriptor, LOCK_EX) == 0 else { throw currentPOSIXError() }

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report.cleaned.isEmpty)
      #expect(report.skippedBusy == [hash])
      #expect(report.unsafe.isEmpty)
      #expect(fixture.candidateExists(hash: hash, suffix: ".part"))
      #expect(fixture.candidateExists(hash: hash, suffix: ".resume.json"))
      #expect(FileManager.default.fileExists(atPath: lease.path))
    }
  }

  @Test
  func unsafeSymbolicLinkFailsClosed() throws {
    try withFixture { fixture in
      let hash = String(repeating: "d", count: 64)
      let target = fixture.parent.appendingPathComponent("outside.bin")
      try Data("outside".utf8).write(to: target)
      let part = fixture.candidate(hash: hash, suffix: ".part")
      try FileManager.default.createSymbolicLink(at: part, withDestinationURL: target)
      try fixture.createCandidate(hash: hash, suffix: ".resume.json", modified: oldDate)
      let lease = try fixture.createLease(hash: hash)

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report.cleaned.isEmpty)
      #expect(report.skippedBusy.isEmpty)
      #expect(report.unsafe == [hash])
      #expect(try FileManager.default.destinationOfSymbolicLink(atPath: part.path) == target.path)
      #expect(fixture.candidateExists(hash: hash, suffix: ".resume.json"))
      #expect(try Data(contentsOf: target) == Data("outside".utf8))
      #expect(FileManager.default.fileExists(atPath: lease.path))
    }
  }

  @Test
  func removesExpiredOrphanAndPersistsNewLease() throws {
    try withFixture { fixture in
      let hash = String(repeating: "e", count: 64)
      try fixture.createCandidate(hash: hash, suffix: ".part", modified: oldDate)
      let lease = fixture.lease(hash: hash)

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report.cleaned == [hash])
      #expect(!fixture.candidateExists(hash: hash, suffix: ".part"))
      #expect(FileManager.default.fileExists(atPath: lease.path))
      #expect(try permissions(of: lease) == 0o600)
      #expect(try linkCount(of: lease) == 1)
    }
  }

  @Test
  func removesExpiredAtomicMetadataTemporaryFileUnderPersistentLease() throws {
    try withFixture { fixture in
      let hash = String(repeating: "f", count: 64)
      let temporaryName = ".\(hash).resume.json.\(UUID().uuidString).tmp"
      try fixture.createNamedCandidate(temporaryName, modified: oldDate)

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report.cleaned == [hash])
      #expect(
        !FileManager.default.fileExists(
          atPath: fixture.partial.appendingPathComponent(temporaryName).path))
      #expect(FileManager.default.fileExists(atPath: fixture.lease(hash: hash).path))
    }
  }

  @Test
  func ignoresNamesOutsideLowercaseSHAContract() throws {
    try withFixture { fixture in
      let uppercaseHash = String(repeating: "A", count: 64)
      let malformedHash = String(repeating: "f", count: 63)
      try fixture.createCandidate(hash: uppercaseHash, suffix: ".part", modified: oldDate)
      try fixture.createCandidate(hash: malformedHash, suffix: ".resume.json", modified: oldDate)

      let report = try fixture.collector.collect(staleBefore: cutoff)

      #expect(report == .init(cleaned: [], skippedBusy: [], unsafe: []))
      #expect(fixture.candidateExists(hash: uppercaseHash, suffix: ".part"))
      #expect(fixture.candidateExists(hash: malformedHash, suffix: ".resume.json"))
      #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.leases.path).isEmpty)
    }
  }

  @Test
  func rejectsUnsafeMaintenanceDirectory() throws {
    try withFixture { fixture in
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: fixture.partial.path
      )

      #expect(
        throws: DownloadPartialGarbageCollectorError.unsafeDirectory(.partial)
      ) {
        try fixture.collector.collect(staleBefore: cutoff)
      }
    }
  }

  private var oldDate: Date { cutoff.addingTimeInterval(-3_600) }
  private var freshDate: Date { cutoff.addingTimeInterval(3_600) }

  private func withFixture<T>(_ body: (GarbageCollectorFixture) throws -> T) throws -> T {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MacGameBridgePartialGCTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: parent) }
    let fixture = try GarbageCollectorFixture(parent: parent)
    return try body(fixture)
  }

  private func identity(of url: URL) throws -> FileIdentity {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw currentPOSIXError() }
    return FileIdentity(device: metadata.st_dev, inode: metadata.st_ino)
  }

  private func permissions(of url: URL) throws -> mode_t {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw currentPOSIXError() }
    return metadata.st_mode & 0o777
  }

  private func linkCount(of url: URL) throws -> nlink_t {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw currentPOSIXError() }
    return metadata.st_nlink
  }
}

private struct FileIdentity: Equatable {
  let device: dev_t
  let inode: ino_t
}

private struct GarbageCollectorFixture {
  let parent: URL
  let root: URL
  let partial: URL
  let leases: URL

  init(parent: URL) throws {
    self.parent = parent
    root = parent.appendingPathComponent("downloads", isDirectory: true)
    partial = root.appendingPathComponent(".partial", isDirectory: true)
    leases = root.appendingPathComponent(".leases", isDirectory: true)
    for directory in [root, partial, leases] {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path
      )
    }
  }

  var collector: DownloadPartialGarbageCollector {
    DownloadPartialGarbageCollector(downloadRootURL: root)
  }

  func candidate(hash: String, suffix: String) -> URL {
    partial.appendingPathComponent("\(hash)\(suffix)")
  }

  func lease(hash: String) -> URL {
    leases.appendingPathComponent("\(hash).lock")
  }

  func createCandidate(hash: String, suffix: String, modified: Date) throws {
    try createNamedCandidate("\(hash)\(suffix)", modified: modified)
  }

  func createNamedCandidate(_ name: String, modified: Date) throws {
    let url = partial.appendingPathComponent(name)
    try Data("checkpoint".utf8).write(to: url)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600, .modificationDate: modified],
      ofItemAtPath: url.path
    )
  }

  @discardableResult
  func createLease(hash: String) throws -> URL {
    let url = lease(hash: hash)
    let descriptor = open(
      url.path,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else { throw currentPOSIXError() }
    defer { _ = close(descriptor) }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw currentPOSIXError()
    }
    return url
  }

  func candidateExists(hash: String, suffix: String) -> Bool {
    FileManager.default.fileExists(atPath: candidate(hash: hash, suffix: suffix).path)
  }
}

private func currentPOSIXError() -> POSIXError {
  POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
