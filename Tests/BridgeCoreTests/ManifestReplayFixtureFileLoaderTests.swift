import CryptoKit
import Darwin
import Foundation
import Testing

@testable import BridgeCore

@Suite(.serialized)
struct ManifestReplayFixtureFileLoaderTests {
  @Test
  func loadsRepresentativeFlatLayoutsAndAllowedModes() async throws {
    for shape in LoaderFixtureShape.allCases {
      let fixture = try makeFixture(shape: shape, id: "loader-\(shape.rawValue)")
      defer { fixture.remove() }
      let bundle: ValidatedReplayArtifactBundle
      do {
        bundle = try loader(fixture).load(
          id: fixture.id,
          expectedDescriptorSHA256: fixture.descriptorSHA256
        )
      } catch {
        throw error
      }
      #expect(bundle.descriptor.fixtureID == fixture.id)
      #expect(bundle.externalArtifacts.map(\.kind) == shape.kinds)
      #expect(bundle.externalArtifacts.map(\.data) == shape.kinds.map { fixture.data[$0]! })
      #expect(bundle.totalByteSize == UInt64(fixture.descriptorData.count + fixture.dataSize))
    }

    let privateFixture = try makeFixture(shape: .full, id: "loader-private")
    defer { privateFixture.remove() }
    try chmodChecked(privateFixture.rootURL, 0o700)
    try chmodChecked(privateFixture.fixtureURL, 0o700)
    for url in privateFixture.fileURLs.values { try chmodChecked(url, 0o600) }
    try chmodChecked(privateFixture.descriptorURL, 0o600)
    _ = try loader(privateFixture).load(
      id: privateFixture.id,
      expectedDescriptorSHA256: privateFixture.descriptorSHA256
    )
  }

  @Test
  func requiresPinnedCanonicalDescriptorAndMatchingFixtureID() throws {
    let fixture = try makeFixture(shape: .full, id: "loader-pin")
    defer { fixture.remove() }
    #expect(throws: ManifestReplayFixtureFileLoadingError.descriptorMismatch) {
      try loader(fixture).load(
        id: fixture.id,
        expectedDescriptorSHA256: ManifestSHA256(String(repeating: "f", count: 64))
      )
    }

    var nonCanonical = fixture.descriptorData
    nonCanonical.append(0x0A)
    try nonCanonical.write(to: fixture.descriptorURL)
    try chmodChecked(fixture.descriptorURL, 0o644)
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidDescriptor) {
      try loader(fixture).load(
        id: fixture.id,
        expectedDescriptorSHA256: ManifestSHA256(sha256(nonCanonical))
      )
    }

    let mismatch = try makeFixture(
      shape: .branchOnly,
      id: "loader-requested",
      descriptorID: "loader-other"
    )
    defer { mismatch.remove() }
    #expect(throws: ManifestReplayFixtureFileLoadingError.descriptorMismatch) {
      try loader(mismatch).load(
        id: mismatch.id,
        expectedDescriptorSHA256: mismatch.descriptorSHA256
      )
    }
  }

  @Test
  func rejectsExtraMissingAndChangedArtifactBytes() throws {
    let extra = try makeFixture(shape: .full, id: "loader-extra")
    defer { extra.remove() }
    try Data("extra".utf8).write(
      to: extra.fixtureURL.appendingPathComponent("unexpected"))
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidInventory) {
      try loader(extra).load(
        id: extra.id,
        expectedDescriptorSHA256: extra.descriptorSHA256
      )
    }

    let missing = try makeFixture(shape: .full, id: "loader-missing")
    defer { missing.remove() }
    try FileManager.default.removeItem(at: missing.fileURLs[.chunkManifest]!)
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidInventory) {
      try loader(missing).load(
        id: missing.id,
        expectedDescriptorSHA256: missing.descriptorSHA256
      )
    }

    let changed = try makeFixture(shape: .full, id: "loader-changed")
    defer { changed.remove() }
    let branchURL = changed.fileURLs[.branchResponse]!
    let original = changed.data[.branchResponse]!
    try Data(repeating: 0x78, count: original.count).write(to: branchURL)
    try chmodChecked(branchURL, 0o644)
    #expect(throws: ManifestReplayFixtureFileLoadingError.artifactMismatch) {
      try loader(changed).load(
        id: changed.id,
        expectedDescriptorSHA256: changed.descriptorSHA256
      )
    }

    let wrongSize = try makeFixture(shape: .full, id: "loader-size")
    defer { wrongSize.remove() }
    try Data("longer-artifact".utf8).write(to: wrongSize.fileURLs[.branchResponse]!)
    try chmodChecked(wrongSize.fileURLs[.branchResponse]!, 0o644)
    #expect(throws: ManifestReplayFixtureFileLoadingError.artifactMismatch) {
      try loader(wrongSize).load(
        id: wrongSize.id,
        expectedDescriptorSHA256: wrongSize.descriptorSHA256
      )
    }
  }

  @Test
  func rejectsUnsafeModesSymlinksHardlinksAndSpecialTypes() throws {
    let unsafeRoot = try makeFixture(shape: .branchOnly, id: "loader-root-mode")
    defer { unsafeRoot.remove() }
    try chmodChecked(unsafeRoot.rootURL, 0o775)
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidRoot) {
      try loader(unsafeRoot).load(
        id: unsafeRoot.id,
        expectedDescriptorSHA256: unsafeRoot.descriptorSHA256
      )
    }

    let unsafeFixture = try makeFixture(shape: .branchOnly, id: "loader-fixture-mode")
    defer { unsafeFixture.remove() }
    try chmodChecked(unsafeFixture.fixtureURL, 0o775)
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try loader(unsafeFixture).load(
        id: unsafeFixture.id,
        expectedDescriptorSHA256: unsafeFixture.descriptorSHA256
      )
    }

    for mode in [mode_t(0o664), mode_t(0o755)] {
      let fixture = try makeFixture(shape: .branchOnly, id: "loader-file-mode-\(mode)")
      defer { fixture.remove() }
      try chmodChecked(fixture.fileURLs[.branchResponse]!, mode)
      #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
        try loader(fixture).load(
          id: fixture.id,
          expectedDescriptorSHA256: fixture.descriptorSHA256
        )
      }
    }

    let symlinkFile = try makeFixture(shape: .branchOnly, id: "loader-symlink-file")
    defer { symlinkFile.remove() }
    let symlinkPath = symlinkFile.fileURLs[.branchResponse]!.path
    try FileManager.default.removeItem(atPath: symlinkPath)
    guard symlink(symlinkFile.descriptorURL.path, symlinkPath) == 0 else {
      throw POSIXError(.EIO)
    }
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try loader(symlinkFile).load(
        id: symlinkFile.id,
        expectedDescriptorSHA256: symlinkFile.descriptorSHA256
      )
    }

    let hardlink = try makeFixture(shape: .branchOnly, id: "loader-hardlink")
    defer { hardlink.remove() }
    let hardlinkURL = hardlink.rootURL.appendingPathComponent("outside-hardlink")
    guard link(hardlink.fileURLs[.branchResponse]!.path, hardlinkURL.path) == 0 else {
      throw POSIXError(.EIO)
    }
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try loader(hardlink).load(
        id: hardlink.id,
        expectedDescriptorSHA256: hardlink.descriptorSHA256
      )
    }

    let fifo = try makeFixture(shape: .branchOnly, id: "loader-fifo")
    defer { fifo.remove() }
    let fifoPath = fifo.fileURLs[.branchResponse]!.path
    try FileManager.default.removeItem(atPath: fifoPath)
    guard mkfifo(fifoPath, 0o600) == 0 else { throw POSIXError(.EIO) }
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try loader(fifo).load(
        id: fifo.id,
        expectedDescriptorSHA256: fifo.descriptorSHA256
      )
    }

    let directory = try makeFixture(shape: .branchOnly, id: "loader-directory")
    defer { directory.remove() }
    let directoryURL = directory.fileURLs[.branchResponse]!
    try FileManager.default.removeItem(at: directoryURL)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try loader(directory).load(
        id: directory.id,
        expectedDescriptorSHA256: directory.descriptorSHA256
      )
    }
  }

  @Test
  func rejectsSymlinkAncestorAndFixtureDirectory() throws {
    let fixture = try makeFixture(shape: .branchOnly, id: "loader-symlink-root")
    defer { fixture.remove() }
    let rootLink = fixture.rootURL.deletingLastPathComponent()
      .appendingPathComponent("root-link-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: rootLink) }
    guard symlink(fixture.rootURL.path, rootLink.path) == 0 else { throw POSIXError(.EIO) }
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidRoot) {
      try ManifestReplayFixtureFileLoader(rootURL: rootLink).load(
        id: fixture.id,
        expectedDescriptorSHA256: fixture.descriptorSHA256
      )
    }

    let fixtureLink = try makeFixture(shape: .branchOnly, id: "loader-symlink-dir")
    defer { fixtureLink.remove() }
    let moved = fixtureLink.rootURL.appendingPathComponent("real-fixture")
    try FileManager.default.moveItem(at: fixtureLink.fixtureURL, to: moved)
    guard symlink(moved.path, fixtureLink.fixtureURL.path) == 0 else { throw POSIXError(.EIO) }
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try loader(fixtureLink).load(
        id: fixtureLink.id,
        expectedDescriptorSHA256: fixtureLink.descriptorSHA256
      )
    }
  }

  @Test
  func detectsPreflightPathReplacementReadMutationAndFinalInventoryChange() throws {
    let replacement = try makeFixture(shape: .full, id: "loader-replace")
    defer { replacement.remove() }
    let branchURL = replacement.fileURLs[.branchResponse]!
    let replacementURL = replacement.rootURL.appendingPathComponent("replacement")
    try replacement.data[.branchResponse]!.write(to: replacementURL)
    try chmodChecked(replacementURL, 0o644)
    let replacementLoader = ManifestReplayFixtureFileLoader(
      rootURL: replacement.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(afterArtifactPreflight: {
        guard rename(replacementURL.path, branchURL.path) == 0 else { throw POSIXError(.EIO) }
      })
    )
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try replacementLoader.load(
        id: replacement.id,
        expectedDescriptorSHA256: replacement.descriptorSHA256
      )
    }

    let modeMutation = try makeFixture(shape: .full, id: "loader-post-mode")
    defer { modeMutation.remove() }
    let modeURL = modeMutation.fileURLs[.branchResponse]!
    let modeLoader = ManifestReplayFixtureFileLoader(
      rootURL: modeMutation.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(afterArtifactRead: { kind in
        if kind == .branchResponse, chmod(modeURL.path, 0o664) != 0 { throw POSIXError(.EIO) }
      })
    )
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try modeLoader.load(
        id: modeMutation.id,
        expectedDescriptorSHA256: modeMutation.descriptorSHA256
      )
    }

    let inventory = try makeFixture(shape: .full, id: "loader-final-inventory")
    defer { inventory.remove() }
    let extraURL = inventory.fixtureURL.appendingPathComponent("extra-final")
    let inventoryLoader = ManifestReplayFixtureFileLoader(
      rootURL: inventory.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(beforeFinalVerification: {
        try Data("extra".utf8).write(to: extraURL)
      })
    )
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidInventory) {
      try inventoryLoader.load(
        id: inventory.id,
        expectedDescriptorSHA256: inventory.descriptorSHA256
      )
    }
  }

  @Test
  func detectsSameInodeWriteAndFinalFixtureOrRootReplacement() throws {
    let sameInode = try makeFixture(shape: .full, id: "loader-same-inode")
    defer { sameInode.remove() }
    let branchURL = sameInode.fileURLs[.branchResponse]!
    let branchData = sameInode.data[.branchResponse]!
    let sameInodeLoader = ManifestReplayFixtureFileLoader(
      rootURL: sameInode.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(afterArtifactRead: { kind in
        guard kind == .branchResponse else { return }
        usleep(1_000)
        let descriptor = open(branchURL.path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { _ = close(descriptor) }
        let count = branchData.withUnsafeBytes { bytes in
          pwrite(descriptor, bytes.baseAddress, bytes.count, 0)
        }
        guard count == branchData.count else { throw POSIXError(.EIO) }
      })
    )
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try sameInodeLoader.load(
        id: sameInode.id,
        expectedDescriptorSHA256: sameInode.descriptorSHA256
      )
    }

    let fixtureSwap = try makeFixture(shape: .full, id: "loader-fixture-swap")
    defer { fixtureSwap.remove() }
    let movedFixture = fixtureSwap.rootURL.appendingPathComponent("moved-fixture")
    let fixtureSwapLoader = ManifestReplayFixtureFileLoader(
      rootURL: fixtureSwap.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(beforeFinalVerification: {
        guard rename(fixtureSwap.fixtureURL.path, movedFixture.path) == 0,
          mkdir(fixtureSwap.fixtureURL.path, 0o755) == 0
        else {
          throw POSIXError(.EIO)
        }
      })
    )
    #expect(throws: ManifestReplayFixtureFileLoadingError.unsafeEntry) {
      try fixtureSwapLoader.load(
        id: fixtureSwap.id,
        expectedDescriptorSHA256: fixtureSwap.descriptorSHA256
      )
    }

    let rootSwap = try makeFixture(shape: .full, id: "loader-root-swap")
    defer { rootSwap.remove() }
    let movedRoot = rootSwap.rootURL.deletingLastPathComponent()
      .appendingPathComponent("moved-root-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: movedRoot) }
    let rootSwapLoader = ManifestReplayFixtureFileLoader(
      rootURL: rootSwap.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(beforeFinalVerification: {
        guard rename(rootSwap.rootURL.path, movedRoot.path) == 0,
          mkdir(rootSwap.rootURL.path, 0o755) == 0
        else {
          throw POSIXError(.EIO)
        }
      })
    )
    #expect(throws: ManifestReplayFixtureFileLoadingError.invalidRoot) {
      try rootSwapLoader.load(
        id: rootSwap.id,
        expectedDescriptorSHA256: rootSwap.descriptorSHA256
      )
    }
  }

  @Test
  func midCancellationClosesPreflightAndActiveFileDescriptors() throws {
    let fixture = try makeFixture(shape: .update, id: "loader-mid-cancel")
    let before = openFileDescriptorCount(under: fixture.rootURL)
    let preflightCancellation = ManifestReplayFixtureFileLoader(
      rootURL: fixture.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(afterArtifactPreflight: {
        throw CancellationError()
      })
    )
    for _ in 0..<16 {
      #expect(throws: CancellationError.self) {
        try preflightCancellation.load(
          id: fixture.id,
          expectedDescriptorSHA256: fixture.descriptorSHA256
        )
      }
    }

    let readCancellation = ManifestReplayFixtureFileLoader(
      rootURL: fixture.rootURL,
      hooks: ManifestReplayFixtureFileLoaderHooks(afterArtifactRead: { kind in
        if kind == .branchResponse { throw CancellationError() }
      })
    )
    #expect(throws: CancellationError.self) {
      try readCancellation.load(
        id: fixture.id,
        expectedDescriptorSHA256: fixture.descriptorSHA256
      )
    }
    let after = openFileDescriptorCount(under: fixture.rootURL)
    #expect(after == before)
    try FileManager.default.removeItem(at: fixture.rootURL)
    #expect(!FileManager.default.fileExists(atPath: fixture.rootURL.path))
  }

  @Test
  func cancellationConcurrencySnapshotAndRedaction() async throws {
    let fixture = try makeFixture(shape: .update, id: "loader-concurrent")
    defer { fixture.remove() }
    let valueLoader = loader(fixture)
    let cancelled = Task { () throws -> ValidatedReplayArtifactBundle in
      withUnsafeCurrentTask { $0?.cancel() }
      return try valueLoader.load(
        id: fixture.id,
        expectedDescriptorSHA256: fixture.descriptorSHA256
      )
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }

    let expected = try valueLoader.load(
      id: fixture.id,
      expectedDescriptorSHA256: fixture.descriptorSHA256
    )
    let values = try await withThrowingTaskGroup(
      of: ValidatedReplayArtifactBundle.self,
      returning: [ValidatedReplayArtifactBundle].self
    ) { group in
      for _ in 0..<8 {
        group.addTask {
          try valueLoader.load(
            id: fixture.id,
            expectedDescriptorSHA256: fixture.descriptorSHA256
          )
        }
      }
      var result: [ValidatedReplayArtifactBundle] = []
      for try await value in group { result.append(value) }
      return result
    }
    #expect(values.count == 8)
    #expect(values.allSatisfy { $0 == expected })

    try Data("mutated".utf8).write(to: fixture.fileURLs[.branchResponse]!)
    #expect(expected.externalArtifacts.first?.data == fixture.data[.branchResponse])

    var dumpedLoader = ""
    dump(valueLoader, to: &dumpedLoader)
    #expect(!dumpedLoader.contains(fixture.rootURL.path))
    var dumpedError = ""
    dump(ManifestReplayFixtureFileLoadingError.invalidRoot, to: &dumpedError)
    #expect(dumpedError.contains("redacted"))
  }

  private func loader(_ fixture: LoaderFixture) -> ManifestReplayFixtureFileLoader {
    ManifestReplayFixtureFileLoader(rootURL: fixture.rootURL)
  }

  private func makeFixture(
    shape: LoaderFixtureShape,
    id: String,
    descriptorID: String? = nil
  ) throws -> LoaderFixture {
    let root = try canonicalTemporaryDirectory()
      .appendingPathComponent("mgb-loader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    try chmodChecked(root, 0o755)
    let fixtureID = try ManifestFixtureID(id)
    let fixture = root.appendingPathComponent(fixtureID.value, isDirectory: true)
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
    try chmodChecked(fixture, 0o755)

    let data = Dictionary(
      uniqueKeysWithValues: shape.kinds.map { kind in
        (kind, Data("\(id)-\(kind.rawValue)".utf8))
      })
    let bindings = shape.kinds.map { kind in
      LoaderBindingDTO(
        kind: kind.rawValue,
        sha256: sha256(data[kind]!),
        byteSize: UInt64(data[kind]!.count),
        manifestReferenceSHA256: kind == .chunkManifest
          ? String(repeating: "a", count: 64)
          : kind == .diffManifest ? String(repeating: "b", count: 64) : nil
      )
    }
    let dto = LoaderDescriptorDTO(
      schemaVersion: 3,
      scope: LoaderScopeDTO(
        fixtureID: descriptorID ?? id,
        release: "genshinOfficialCN",
        intent: LoaderIntentDTO(kind: shape.intentKind, sourceVersion: shape.sourceVersion),
        categories: ["game"]
      ),
      availability: shape.availability,
      branches: LoaderBranchesDTO(officialVersion: "2.0.0", preDownloadVersion: nil),
      target: shape.hasTarget ? LoaderTargetDTO(game: .chunk) : nil,
      selectedLdiff: shape.hasLdiff ? LoaderSelectedLdiffDTO(game: .selected) : nil,
      externalArtifactBindings: bindings,
      evidenceMetadata: LoaderEvidenceDTO(
        profileRevision: 1,
        observedAtUnixSeconds: 1,
        expiresAtUnixSeconds: 2,
        schemaBaseline: ManifestProtobufStructuralMapper.requiredSchemaBaseline
      ),
      observations: []
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let descriptor = try encoder.encode(dto)
    let descriptorURL = fixture.appendingPathComponent("fixture.json")
    try descriptor.write(to: descriptorURL)
    try chmodChecked(descriptorURL, 0o644)

    var fileURLs: [ManifestEvidenceArtifactKind: URL] = [:]
    for kind in shape.kinds {
      let url = fixture.appendingPathComponent(filename(kind))
      try data[kind]!.write(to: url)
      try chmodChecked(url, 0o644)
      fileURLs[kind] = url
    }
    return try LoaderFixture(
      rootURL: root,
      fixtureURL: fixture,
      id: fixtureID,
      descriptorURL: descriptorURL,
      descriptorData: descriptor,
      descriptorSHA256: ManifestSHA256(sha256(descriptor)),
      data: data,
      fileURLs: fileURLs
    )
  }

  private func filename(_ kind: ManifestEvidenceArtifactKind) -> String {
    switch kind {
    case .branchResponse: "branch-response.redacted.json"
    case .buildResponse: "build-response.redacted.json"
    case .patchResponse: "patch-response.redacted.json"
    case .chunkManifest: "chunk-manifest.pb.zst"
    case .diffManifest: "ldiff-manifest.pb.zst"
    case .fixtureDescriptor: "fixture.json"
    }
  }

  private func canonicalTemporaryDirectory() throws -> URL {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(FileManager.default.temporaryDirectory.path, &buffer) != nil else {
      throw POSIXError(.EIO)
    }
    guard
      let path = buffer.withUnsafeBufferPointer({ pointer in
        pointer.baseAddress.flatMap(String.init(validatingCString:))
      })
    else {
      throw POSIXError(.EIO)
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private func chmodChecked(_ url: URL, _ mode: mode_t) throws {
    guard chmod(url.path, mode) == 0 else { throw POSIXError(.EIO) }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func openFileDescriptorCount(under root: URL) -> Int {
    var count = 0
    let prefix = root.resolvingSymlinksInPath().path
    for descriptor in 0..<getdtablesize() {
      var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
      guard fcntl(descriptor, F_GETPATH, &path) == 0 else { continue }
      let value = String(cString: path)
      if value == prefix || value.hasPrefix(prefix + "/") { count += 1 }
    }
    return count
  }
}

private enum LoaderFixtureShape: String, CaseIterable {
  case branchOnly
  case full
  case update

  var kinds: [ManifestEvidenceArtifactKind] {
    switch self {
    case .branchOnly: [.branchResponse]
    case .full: [.branchResponse, .buildResponse, .chunkManifest]
    case .update:
      [.branchResponse, .buildResponse, .patchResponse, .chunkManifest, .diffManifest]
    }
  }

  var intentKind: String {
    switch self {
    case .branchOnly: "preDownload"
    case .full: "full"
    case .update: "update"
    }
  }

  var sourceVersion: String? { self == .update ? "1.0.0" : nil }
  var availability: String { self == .branchOnly ? "preDownloadNotPublished" : "available" }
  var hasTarget: Bool { self != .branchOnly }
  var hasLdiff: Bool { self == .update }
}

private struct LoaderFixture {
  let rootURL: URL
  let fixtureURL: URL
  let id: ManifestFixtureID
  let descriptorURL: URL
  let descriptorData: Data
  let descriptorSHA256: ManifestSHA256
  let data: [ManifestEvidenceArtifactKind: Data]
  let fileURLs: [ManifestEvidenceArtifactKind: URL]

  var dataSize: Int { data.values.reduce(0) { $0 + $1.count } }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

private struct LoaderDescriptorDTO: Encodable {
  let schemaVersion: UInt8
  let scope: LoaderScopeDTO
  let availability: String
  let branches: LoaderBranchesDTO
  let target: LoaderTargetDTO?
  let selectedLdiff: LoaderSelectedLdiffDTO?
  let externalArtifactBindings: [LoaderBindingDTO]
  let evidenceMetadata: LoaderEvidenceDTO
  let observations: [LoaderObservationDTO]
}

private struct LoaderScopeDTO: Encodable {
  let fixtureID: String
  let release: String
  let intent: LoaderIntentDTO
  let categories: [String]
}

private struct LoaderIntentDTO: Encodable {
  let kind: String
  let sourceVersion: String?
}

private struct LoaderBranchesDTO: Encodable {
  let officialVersion: String
  let preDownloadVersion: String?
}

private struct LoaderTargetDTO: Encodable {
  let game: LoaderChunkSummaryDTO
}

private struct LoaderChunkSummaryDTO: Encodable {
  let fileCount: UInt64
  let directoryCount: UInt64
  let chunkReferenceCount: UInt64
  let uniqueChunkObjectCount: UInt64
  let targetInstalledBytes: UInt64
  let referencedChunkCompressedBytes: UInt64
  let uniqueChunkObjectBytes: UInt64

  static let chunk = LoaderChunkSummaryDTO(
    fileCount: 1,
    directoryCount: 0,
    chunkReferenceCount: 1,
    uniqueChunkObjectCount: 1,
    targetInstalledBytes: 4,
    referencedChunkCompressedBytes: 3,
    uniqueChunkObjectBytes: 3
  )
}

private struct LoaderSelectedLdiffDTO: Encodable {
  let game: LoaderLdiffSummaryDTO
}

private struct LoaderLdiffSummaryDTO: Encodable {
  let manifestFileRecordCount: UInt64
  let selectedPatchFileCount: UInt64
  let fileRecordsWithoutSelectedPatchCount: UInt64
  let selectedDeletionCount: UInt64
  let uniquePatchObjectCount: UInt64
  let selectedPatchObjectBytes: UInt64

  static let selected = LoaderLdiffSummaryDTO(
    manifestFileRecordCount: 1,
    selectedPatchFileCount: 1,
    fileRecordsWithoutSelectedPatchCount: 0,
    selectedDeletionCount: 0,
    uniquePatchObjectCount: 1,
    selectedPatchObjectBytes: 5
  )
}

private struct LoaderBindingDTO: Encodable {
  let kind: String
  let sha256: String
  let byteSize: UInt64
  let manifestReferenceSHA256: String?
}

private struct LoaderEvidenceDTO: Encodable {
  let profileRevision: UInt64
  let observedAtUnixSeconds: Int64
  let expiresAtUnixSeconds: Int64?
  let schemaBaseline: String
}

private struct LoaderObservationDTO: Encodable {
  let code: String
  let severity: String
}
