import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

@Suite(.serialized)
struct VersionedRuntimeStoreTests {
  let artifactSHA256 = String(repeating: "a", count: 64)

  struct Fixture {
    let runtime: RuntimeDefinition
    let plan: SafeArchivePlan
    let descriptors: [ArchiveEntryDescriptor]
    let artifactSHA256: String

    func source(
      readerFactory: (() -> any ArchiveEntryContentReading)? = nil
    ) -> StoreArchiveSource {
      StoreArchiveSource(
        artifactSHA256: artifactSHA256,
        descriptors: descriptors,
        contents: [storeSHA256(Data("bin/tool".utf8)): Data("tool".utf8)],
        readerFactory: readerFactory
      )
    }
  }

  struct ActivationInputs {
    let catalog: VerifiedCatalog
    let request: CompatibilityRequest
  }

  struct ActiveFixture {
    let store: VersionedRuntimeStore
    let installed: InstalledRuntimeVersion
    let activation: ActivationInputs
    let current: RuntimeActivationRecord
  }

  func prepareFirstActivation(in root: URL) throws -> ActiveFixture {
    let fixture = try makeFixture()
    let store = VersionedRuntimeStore(rootURL: root)
    let installed = try store.install(
      runtime: fixture.runtime,
      plan: fixture.plan,
      source: fixture.source()
    )
    let activation = try activationInputs(for: fixture.runtime)
    let current = try store.activateFirst(
      installed: installed,
      verifiedCatalog: activation.catalog,
      request: activation.request
    )
    return ActiveFixture(
      store: store,
      installed: installed,
      activation: activation,
      current: current
    )
  }

  func activationInputs(for runtime: RuntimeDefinition) throws -> ActivationInputs {
    let profile = CatalogTestFixtures.standardProfile(runtime: runtime)
    let catalog = CatalogTestFixtures.catalog(runtimes: [runtime], profiles: [profile])
    return ActivationInputs(
      catalog: CatalogTestFixtures.verifiedCatalog(catalog),
      request: CatalogTestFixtures.request(mode: .standard)
    )
  }

  func activationReplacingInstallID(
    _ value: RuntimeActivationRecord,
    installID: String
  ) -> RuntimeActivationRecord {
    func copy(_ activationID: String) -> RuntimeActivationRecord {
      RuntimeActivationRecord(
        schemaVersion: value.schemaVersion, activationID: activationID,
        generation: value.generation, catalogRevision: value.catalogRevision,
        catalogPayloadSHA256: value.catalogPayloadSHA256,
        catalogChannel: value.catalogChannel, selectionMode: value.selectionMode,
        acknowledgementSHA256: value.acknowledgementSHA256,
        profileID: value.profileID, profileRevision: value.profileRevision,
        profileDefinitionSHA256: value.profileDefinitionSHA256,
        disclosureSHA256: value.disclosureSHA256, gameID: value.gameID,
        gameVersion: value.gameVersion, gameBuildFingerprint: value.gameBuildFingerprint,
        runtimeID: value.runtimeID,
        runtimeDefinitionSHA256: value.runtimeDefinitionSHA256,
        installID: installID, artifactSHA256: value.artifactSHA256,
        planPolicyVersion: value.planPolicyVersion, planSHA256: value.planSHA256,
        treeSealVersion: value.treeSealVersion, treeSHA256: value.treeSHA256,
        compatibilityTier: value.compatibilityTier
      )
    }
    let unsigned = copy("")
    return copy(RuntimeActivationIdentityBuilder.activationID(unsigned))
  }

  func copyCatalog(
    _ catalog: CompatibilityCatalog,
    runtimes: [RuntimeDefinition],
    profiles: [CompatibilityProfile]? = nil,
    revocations: RevocationList = .init()
  ) -> CompatibilityCatalog {
    CompatibilityCatalog(
      schemaVersion: catalog.schemaVersion, revision: catalog.revision,
      catalogVersion: catalog.catalogVersion, channel: catalog.channel,
      issuedAt: catalog.issuedAt, expiresAt: catalog.expiresAt,
      minimumClientVersion: catalog.minimumClientVersion, games: catalog.games,
      runtimes: runtimes, profiles: profiles ?? catalog.profiles, revocations: revocations
    )
  }

  func makeFixture(runtime suppliedRuntime: RuntimeDefinition? = nil) throws -> Fixture {
    let descriptors = [
      ArchiveEntryDescriptor(
        path: "bin/", kind: .directory, declaredSize: 0, permissions: 0o755),
      ArchiveEntryDescriptor(
        path: "bin/tool", kind: .regularFile, declaredSize: 4, permissions: 0o755),
    ]
    let runtime =
      suppliedRuntime
      ?? RuntimeDefinition(
        id: "runtime.test",
        backend: .dxmt,
        version: "1.2.3",
        verification: .candidate,
        acquisition: .managedDownload,
        sourceURL: "https://example.invalid/runtime.zip",
        byteSize: 20,
        sha256: artifactSHA256,
        license: "MIT",
        redistributable: true
      )
    return Fixture(
      runtime: runtime,
      plan: try SafeArchivePlanner.plan(
        entries: descriptors,
        archiveByteSize: try #require(runtime.byteSize)
      ),
      descriptors: descriptors,
      artifactSHA256: try #require(runtime.sha256?.lowercased())
    )
  }

  func expectCorrupt(
    _ store: VersionedRuntimeStore,
    fixture: Fixture,
    installID: String
  ) throws {
    #expect(throws: VersionedRuntimeStoreError.corruptExistingVersion(installID)) {
      try store.install(
        runtime: fixture.runtime,
        plan: fixture.plan,
        source: fixture.source()
      )
    }
  }

  func withPrivateRoot<T>(_ body: (URL) throws -> T) throws -> T {
    let root = try makePrivateRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
  }

  func withPrivateRootAsync<T>(_ body: (URL) async throws -> T) async throws -> T {
    let root = try makePrivateRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(root)
  }

  func makePrivateRoot() throws -> URL {
    var canonicalPath = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(FileManager.default.temporaryDirectory.path, &canonicalPath) != nil else {
      throw currentStoreTestPOSIXError()
    }
    let terminator = canonicalPath.firstIndex(of: 0) ?? canonicalPath.endIndex
    let root = URL(
      fileURLWithPath: String(
        decoding: canonicalPath[..<terminator].map { UInt8(bitPattern: $0) },
        as: UTF8.self
      ),
      isDirectory: true
    )
    .appendingPathComponent("MacGameBridgeRuntimeStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    return root
  }

  func directoryNames(_ url: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
  }

  func permissions(_ url: URL) throws -> mode_t {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw currentStoreTestPOSIXError() }
    return metadata.st_mode & 0o777
  }

  func device(_ url: URL) throws -> dev_t {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else { throw currentStoreTestPOSIXError() }
    return metadata.st_dev
  }
}

final class StoreArchiveSource: ArchivePlannedContentSource {
  let artifactSHA256: String
  let entryCount: Int
  private let descriptors: [String: ArchiveEntryDescriptor]
  private let contents: [String: Data]
  private let readerFactory: (() -> any ArchiveEntryContentReading)?
  private var requested = Set<String>()

  init(
    artifactSHA256: String,
    descriptors: [ArchiveEntryDescriptor],
    contents: [String: Data],
    readerFactory: (() -> any ArchiveEntryContentReading)? = nil
  ) {
    self.artifactSHA256 = artifactSHA256
    entryCount = descriptors.count
    self.descriptors = Dictionary(
      uniqueKeysWithValues: descriptors.map { (storeSHA256(Data($0.path.utf8)), $0) }
    )
    self.contents = contents
    self.readerFactory = readerFactory
  }

  func descriptor(forSourcePathSHA256 digest: String) throws -> ArchiveEntryDescriptor {
    requested.insert(digest)
    guard let descriptor = descriptors[digest] else { throw StoreTestError.missing }
    return descriptor
  }

  func reader(for entry: PlannedArchiveEntry) throws -> any ArchiveEntryContentReading {
    if let readerFactory { return readerFactory() }
    guard let data = contents[entry.sourcePathSHA256] else { throw StoreTestError.missing }
    return StoreDataReader(data)
  }

  func finish() throws {
    guard requested.count == entryCount else { throw StoreTestError.missing }
  }
}

final class StoreDataReader: ArchiveEntryContentReading {
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

final class StoreThrowingReader: ArchiveEntryContentReading {
  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    throw StoreTestError.readerFailed
  }
}

final class StoreCancellingReader: ArchiveEntryContentReading {
  private var emitted = false

  func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
    guard !emitted else { return 0 }
    emitted = true
    withUnsafeCurrentTask { $0?.cancel() }
    let bytes = Data("tool".utf8)
    _ = bytes.copyBytes(to: buffer.bindMemory(to: UInt8.self))
    return bytes.count
  }
}

enum StoreTestError: Error, Equatable {
  case missing
  case readerFailed
  case postRenameFailed
}

func storeSHA256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func overwriteStoreFile(_ url: URL, with data: Data) throws {
  let descriptor = open(url.path, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC)
  guard descriptor >= 0 else { throw currentStoreTestPOSIXError() }
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
      guard count > 0 else { throw currentStoreTestPOSIXError() }
      offset += count
    }
  }
  guard fsync(descriptor) == 0 else { throw currentStoreTestPOSIXError() }
}

func currentStoreTestPOSIXError() -> POSIXError {
  POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
