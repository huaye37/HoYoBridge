import Foundation

struct ManifestProtobufWireBudgetLimits: Equatable, Sendable {
  static let `default` = ManifestProtobufWireBudgetLimits(
    uncheckedMaximumFileCount: 100_000,
    maximumTotalChunkCount: 1_000_000,
    maximumChunksPerFile: 100_000,
    maximumTotalPatchCount: 500_000,
    maximumPatchesPerFile: 256,
    maximumDeleteGroupCount: 256,
    maximumDeleteEntryCount: 100_000,
    maximumDepth: 3,
    maximumNodeCount: 1_250_000,
    maximumStringFieldBytes: 1_024,
    maximumTotalStringBytes: 128 * 1_024 * 1_024
  )

  let maximumFileCount: UInt64
  let maximumTotalChunkCount: UInt64
  let maximumChunksPerFile: UInt64
  let maximumTotalPatchCount: UInt64
  let maximumPatchesPerFile: UInt64
  let maximumDeleteGroupCount: UInt64
  let maximumDeleteEntryCount: UInt64
  let maximumDepth: UInt8
  let maximumNodeCount: UInt64
  let maximumStringFieldBytes: UInt64
  let maximumTotalStringBytes: UInt64

  init(
    maximumFileCount: UInt64 = Self.default.maximumFileCount,
    maximumTotalChunkCount: UInt64 = Self.default.maximumTotalChunkCount,
    maximumChunksPerFile: UInt64 = Self.default.maximumChunksPerFile,
    maximumTotalPatchCount: UInt64 = Self.default.maximumTotalPatchCount,
    maximumPatchesPerFile: UInt64 = Self.default.maximumPatchesPerFile,
    maximumDeleteGroupCount: UInt64 = Self.default.maximumDeleteGroupCount,
    maximumDeleteEntryCount: UInt64 = Self.default.maximumDeleteEntryCount,
    maximumDepth: UInt8 = Self.default.maximumDepth,
    maximumNodeCount: UInt64 = Self.default.maximumNodeCount,
    maximumStringFieldBytes: UInt64 = Self.default.maximumStringFieldBytes,
    maximumTotalStringBytes: UInt64 = Self.default.maximumTotalStringBytes
  ) throws {
    let defaults = Self.default
    guard maximumFileCount <= defaults.maximumFileCount,
      maximumTotalChunkCount <= defaults.maximumTotalChunkCount,
      maximumChunksPerFile <= defaults.maximumChunksPerFile,
      maximumTotalPatchCount <= defaults.maximumTotalPatchCount,
      maximumPatchesPerFile <= defaults.maximumPatchesPerFile,
      maximumDeleteGroupCount <= defaults.maximumDeleteGroupCount,
      maximumDeleteEntryCount <= defaults.maximumDeleteEntryCount,
      maximumDepth <= defaults.maximumDepth,
      maximumNodeCount <= defaults.maximumNodeCount,
      maximumStringFieldBytes <= defaults.maximumStringFieldBytes,
      maximumTotalStringBytes <= defaults.maximumTotalStringBytes
    else {
      throw ManifestProtobufWireScanningError.resourceLimit
    }
    self.maximumFileCount = maximumFileCount
    self.maximumTotalChunkCount = maximumTotalChunkCount
    self.maximumChunksPerFile = maximumChunksPerFile
    self.maximumTotalPatchCount = maximumTotalPatchCount
    self.maximumPatchesPerFile = maximumPatchesPerFile
    self.maximumDeleteGroupCount = maximumDeleteGroupCount
    self.maximumDeleteEntryCount = maximumDeleteEntryCount
    self.maximumDepth = maximumDepth
    self.maximumNodeCount = maximumNodeCount
    self.maximumStringFieldBytes = maximumStringFieldBytes
    self.maximumTotalStringBytes = maximumTotalStringBytes
  }

  private init(
    uncheckedMaximumFileCount: UInt64,
    maximumTotalChunkCount: UInt64,
    maximumChunksPerFile: UInt64,
    maximumTotalPatchCount: UInt64,
    maximumPatchesPerFile: UInt64,
    maximumDeleteGroupCount: UInt64,
    maximumDeleteEntryCount: UInt64,
    maximumDepth: UInt8,
    maximumNodeCount: UInt64,
    maximumStringFieldBytes: UInt64,
    maximumTotalStringBytes: UInt64
  ) {
    maximumFileCount = uncheckedMaximumFileCount
    self.maximumTotalChunkCount = maximumTotalChunkCount
    self.maximumChunksPerFile = maximumChunksPerFile
    self.maximumTotalPatchCount = maximumTotalPatchCount
    self.maximumPatchesPerFile = maximumPatchesPerFile
    self.maximumDeleteGroupCount = maximumDeleteGroupCount
    self.maximumDeleteEntryCount = maximumDeleteEntryCount
    self.maximumDepth = maximumDepth
    self.maximumNodeCount = maximumNodeCount
    self.maximumStringFieldBytes = maximumStringFieldBytes
    self.maximumTotalStringBytes = maximumTotalStringBytes
  }
}

enum ManifestProtobufWireScanningError: Error, Equatable, Sendable {
  case schemaDrift
  case invalidWire
  case resourceLimit
}

struct ManifestProtobufWireSchemaDriftObservation: Equatable, Sendable {
  let messageKind: String
  let fieldNumber: UInt64
  let wireType: UInt8
}

private struct ManifestProtobufDetailedSchemaDrift: Error {
  let observation: ManifestProtobufWireSchemaDriftObservation
}

struct ManifestProtobufWireBudgetSummary: Equatable, Sendable {
  static let currentPolicyVersion: UInt8 = 1

  let policyVersion: UInt8
  let compressedArtifactIdentity: ManifestReplayArtifactIdentity
  let decompressedSHA256: ManifestSHA256
  let decompressedByteSize: UInt64
  let fileCount: UInt64
  let chunkCount: UInt64
  let patchCount: UInt64
  let deleteGroupCount: UInt64
  let deleteEntryCount: UInt64
  let nodeCount: UInt64
  let totalStringBytes: UInt64

  fileprivate init(
    capability: ManifestZstdDecompressedCapability,
    counters: ManifestWireCounters
  ) {
    policyVersion = Self.currentPolicyVersion
    compressedArtifactIdentity = capability.compressedArtifactIdentity
    decompressedSHA256 = capability.sha256
    decompressedByteSize = capability.byteSize
    fileCount = counters.fileCount
    chunkCount = counters.chunkCount
    patchCount = counters.patchCount
    deleteGroupCount = counters.deleteGroupCount
    deleteEntryCount = counters.deleteEntryCount
    nodeCount = counters.nodeCount
    totalStringBytes = counters.totalStringBytes
  }
}

extension ManifestProtobufWireBudgetSummary: ManifestReplayRedactedValue {}

enum ManifestProtobufWireBudgetScanner {
  static func scan(
    _ capability: ManifestZstdDecompressedCapability,
    limits: ManifestProtobufWireBudgetLimits = .default
  ) throws -> ManifestProtobufWireBudgetSummary {
    try Task.checkCancellation()
    guard UInt64(capability.data.count) == capability.byteSize else {
      throw ManifestProtobufWireScanningError.invalidWire
    }
    let root: ManifestWireMessage
    switch capability.compressedArtifactIdentity.kind {
    case .chunkManifest: root = .chunkManifest
    case .diffManifest: root = .diffManifest
    default: throw ManifestProtobufWireScanningError.schemaDrift
    }
    let counters: ManifestWireCounters
    do {
      counters = try capability.data.withUnsafeBytes { bytes in
        var scanner = ManifestWireScanner(bytes: bytes, limits: limits)
        try scanner.scan(root: root)
        return scanner.counters
      }
    } catch is ManifestProtobufDetailedSchemaDrift {
      throw ManifestProtobufWireScanningError.schemaDrift
    }
    try Task.checkCancellation()
    return ManifestProtobufWireBudgetSummary(capability: capability, counters: counters)
  }

  static func diagnoseSchemaDrift(
    _ capability: ManifestZstdDecompressedCapability,
    limits: ManifestProtobufWireBudgetLimits = .default
  ) throws -> ManifestProtobufWireSchemaDriftObservation? {
    try Task.checkCancellation()
    guard UInt64(capability.data.count) == capability.byteSize else {
      throw ManifestProtobufWireScanningError.invalidWire
    }
    let root: ManifestWireMessage
    switch capability.compressedArtifactIdentity.kind {
    case .chunkManifest: root = .chunkManifest
    case .diffManifest: root = .diffManifest
    default: throw ManifestProtobufWireScanningError.schemaDrift
    }
    do {
      try capability.data.withUnsafeBytes { bytes in
        var scanner = ManifestWireScanner(bytes: bytes, limits: limits)
        try scanner.scan(root: root)
      }
      return nil
    } catch let error as ManifestProtobufDetailedSchemaDrift {
      return error.observation
    }
  }

}

private enum ManifestWireMessage {
  case chunkManifest
  case chunkFile
  case chunkInfo
  case diffManifest
  case diffFile
  case patch
  case patchInfo
  case deleteFile
  case deleteFiles
  case deleteFileInfo

  var safeName: String {
    switch self {
    case .chunkManifest: "chunkManifest"
    case .chunkFile: "chunkFile"
    case .chunkInfo: "chunkInfo"
    case .diffManifest: "diffManifest"
    case .diffFile: "diffFile"
    case .patch: "patch"
    case .patchInfo: "patchInfo"
    case .deleteFile: "deleteFile"
    case .deleteFiles: "deleteFiles"
    case .deleteFileInfo: "deleteFileInfo"
    }
  }
}

private enum ManifestWireCounter {
  case files
  case chunks
  case patches
  case deleteGroups
  case deleteEntries
}

private enum ManifestWireVarintKind {
  case int32
  case int64
  case uint32
  case uint64

  func accepts(_ value: UInt64) -> Bool {
    switch self {
    case .int32:
      value <= UInt64(Int32.max) || value >= 0xFFFF_FFFF_8000_0000
    case .uint32:
      value <= UInt64(UInt32.max)
    case .int64, .uint64:
      true
    }
  }
}

private struct ManifestWireCounters {
  var fileCount: UInt64 = 0
  var chunkCount: UInt64 = 0
  var patchCount: UInt64 = 0
  var deleteGroupCount: UInt64 = 0
  var deleteEntryCount: UInt64 = 0
  var nodeCount: UInt64 = 0
  var totalStringBytes: UInt64 = 0
}

private struct ManifestWireScanner {
  let bytes: UnsafeRawBufferPointer
  let limits: ManifestProtobufWireBudgetLimits
  var counters = ManifestWireCounters()
  private var scannedFieldCount: UInt64 = 0
  private var lastCancellationByte = 0
  private var currentMessage: ManifestWireMessage?
  private var currentFieldNumber: UInt64?
  private var currentWireType: UInt8?

  init(bytes: UnsafeRawBufferPointer, limits: ManifestProtobufWireBudgetLimits) {
    self.bytes = bytes
    self.limits = limits
  }

  mutating func scan(root: ManifestWireMessage) throws {
    do {
      try addNode()
      try scanMessage(root, start: 0, end: bytes.count, depth: 0)
    } catch ManifestProtobufWireScanningError.schemaDrift {
      guard let currentMessage, let currentFieldNumber, let currentWireType else {
        throw ManifestProtobufWireScanningError.schemaDrift
      }
      throw ManifestProtobufDetailedSchemaDrift(
        observation: ManifestProtobufWireSchemaDriftObservation(
          messageKind: currentMessage.safeName,
          fieldNumber: currentFieldNumber,
          wireType: currentWireType
        )
      )
    }
  }

  private mutating func scanMessage(
    _ message: ManifestWireMessage,
    start: Int,
    end: Int,
    depth: UInt8
  ) throws {
    guard depth <= limits.maximumDepth else {
      throw ManifestProtobufWireScanningError.resourceLimit
    }
    var index = start
    var singularMask: UInt16 = 0
    var localRepeatedCount: UInt64 = 0
    while index < end {
      try cancellationCheckpoint(at: index)
      let tag = try readMinimalVarint(index: &index, end: end)
      guard tag != 0 else { throw ManifestProtobufWireScanningError.invalidWire }
      let fieldNumber = tag >> 3
      let wireType = UInt8(tag & 7)
      guard fieldNumber > 0, fieldNumber <= 536_870_911 else {
        throw ManifestProtobufWireScanningError.invalidWire
      }
      currentMessage = message
      currentFieldNumber = fieldNumber
      currentWireType = wireType
      scannedFieldCount += 1
      try scanField(
        message: message,
        fieldNumber: fieldNumber,
        wireType: wireType,
        index: &index,
        end: end,
        depth: depth,
        singularMask: &singularMask,
        localRepeatedCount: &localRepeatedCount
      )
    }
    try cancellationCheckpoint(at: end)
    guard index == end else { throw ManifestProtobufWireScanningError.invalidWire }
  }

  private mutating func scanField(
    message: ManifestWireMessage,
    fieldNumber: UInt64,
    wireType: UInt8,
    index: inout Int,
    end: Int,
    depth: UInt8,
    singularMask: inout UInt16,
    localRepeatedCount: inout UInt64
  ) throws {
    switch message {
    case .chunkManifest:
      guard fieldNumber == 1 else { throw ManifestProtobufWireScanningError.schemaDrift }
      try repeatedMessage(
        .chunkFile, wireType, &index, end, depth,
        counter: .files, maximum: limits.maximumFileCount)
    case .chunkFile:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 1_024)
      case 2:
        let (next, overflow) = localRepeatedCount.addingReportingOverflow(1)
        guard !overflow, next <= limits.maximumChunksPerFile else {
          throw ManifestProtobufWireScanningError.resourceLimit
        }
        localRepeatedCount = next
        try repeatedMessage(
          .chunkInfo, wireType, &index, end, depth,
          counter: .chunks, maximum: limits.maximumTotalChunkCount)
      case 3, 4:
        try singularVarint(
          fieldNumber, wireType, &index, end, &singularMask, kind: .int32)
      case 5: try singularString(5, wireType, &index, end, &singularMask, maximum: 32)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .chunkInfo:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 256)
      case 2: try singularString(2, wireType, &index, end, &singularMask, maximum: 32)
      case 3, 6:
        try singularVarint(
          fieldNumber, wireType, &index, end, &singularMask, kind: .uint64)
      case 4, 5:
        try singularVarint(
          fieldNumber, wireType, &index, end, &singularMask, kind: .uint32)
      case 7:
        try singularString(7, wireType, &index, end, &singularMask, maximum: 32)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .diffManifest:
      switch fieldNumber {
      case 1:
        try repeatedMessage(
          .diffFile, wireType, &index, end, depth,
          counter: .files, maximum: limits.maximumFileCount)
      case 2:
        try repeatedMessage(
          .deleteFile, wireType, &index, end, depth,
          counter: .deleteGroups, maximum: limits.maximumDeleteGroupCount)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .diffFile:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 1_024)
      case 2: try singularVarint(2, wireType, &index, end, &singularMask, kind: .int32)
      case 3: try singularString(3, wireType, &index, end, &singularMask, maximum: 32)
      case 4:
        let (next, overflow) = localRepeatedCount.addingReportingOverflow(1)
        guard !overflow, next <= limits.maximumPatchesPerFile else {
          throw ManifestProtobufWireScanningError.resourceLimit
        }
        localRepeatedCount = next
        try repeatedMessage(
          .patch, wireType, &index, end, depth,
          counter: .patches, maximum: limits.maximumTotalPatchCount)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .patch:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 128)
      case 2: try singularMessage(.patchInfo, 2, wireType, &index, end, depth, &singularMask)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .patchInfo:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 256)
      case 2: try singularString(2, wireType, &index, end, &singularMask, maximum: 128)
      case 3: try singularString(3, wireType, &index, end, &singularMask, maximum: 256)
      case 4, 6, 7, 9:
        try singularVarint(
          fieldNumber, wireType, &index, end, &singularMask, kind: .int64)
      case 5: try singularString(5, wireType, &index, end, &singularMask, maximum: 256)
      case 8: try singularString(8, wireType, &index, end, &singularMask, maximum: 1_024)
      case 10: try singularString(10, wireType, &index, end, &singularMask, maximum: 32)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .deleteFile:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 128)
      case 2: try singularMessage(.deleteFiles, 2, wireType, &index, end, depth, &singularMask)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    case .deleteFiles:
      guard fieldNumber == 1 else { throw ManifestProtobufWireScanningError.schemaDrift }
      try repeatedMessage(
        .deleteFileInfo, wireType, &index, end, depth,
        counter: .deleteEntries, maximum: limits.maximumDeleteEntryCount)
    case .deleteFileInfo:
      switch fieldNumber {
      case 1: try singularString(1, wireType, &index, end, &singularMask, maximum: 1_024)
      case 2: try singularVarint(2, wireType, &index, end, &singularMask, kind: .int64)
      case 3: try singularString(3, wireType, &index, end, &singularMask, maximum: 32)
      default: throw ManifestProtobufWireScanningError.schemaDrift
      }
    }
  }

  private mutating func singularVarint(
    _ field: UInt64,
    _ wireType: UInt8,
    _ index: inout Int,
    _ end: Int,
    _ mask: inout UInt16,
    kind: ManifestWireVarintKind
  ) throws {
    guard wireType == 0 else { throw ManifestProtobufWireScanningError.schemaDrift }
    try markSingular(field, mask: &mask)
    let value = try readMinimalVarint(index: &index, end: end)
    guard kind.accepts(value) else {
      throw ManifestProtobufWireScanningError.invalidWire
    }
  }

  private mutating func singularString(
    _ field: UInt64,
    _ wireType: UInt8,
    _ index: inout Int,
    _ end: Int,
    _ mask: inout UInt16,
    maximum: UInt64
  ) throws {
    guard wireType == 2 else { throw ManifestProtobufWireScanningError.schemaDrift }
    try markSingular(field, mask: &mask)
    let range = try readLengthDelimited(index: &index, end: end)
    try cancellationCheckpoint(at: range.upperBound)
    let count = UInt64(range.count)
    guard count <= min(maximum, limits.maximumStringFieldBytes) else {
      throw ManifestProtobufWireScanningError.resourceLimit
    }
    let (total, overflow) = counters.totalStringBytes.addingReportingOverflow(count)
    guard !overflow, total <= limits.maximumTotalStringBytes else {
      throw ManifestProtobufWireScanningError.resourceLimit
    }
    counters.totalStringBytes = total
  }

  private mutating func singularMessage(
    _ child: ManifestWireMessage,
    _ field: UInt64,
    _ wireType: UInt8,
    _ index: inout Int,
    _ end: Int,
    _ depth: UInt8,
    _ mask: inout UInt16
  ) throws {
    guard wireType == 2 else { throw ManifestProtobufWireScanningError.schemaDrift }
    try markSingular(field, mask: &mask)
    let range = try readLengthDelimited(index: &index, end: end)
    try addNode()
    try scanMessage(child, start: range.lowerBound, end: range.upperBound, depth: depth + 1)
  }

  private mutating func repeatedMessage(
    _ child: ManifestWireMessage,
    _ wireType: UInt8,
    _ index: inout Int,
    _ end: Int,
    _ depth: UInt8,
    counter: ManifestWireCounter,
    maximum: UInt64
  ) throws {
    guard wireType == 2 else { throw ManifestProtobufWireScanningError.schemaDrift }
    try increment(counter, maximum: maximum)
    let range = try readLengthDelimited(index: &index, end: end)
    try addNode()
    try scanMessage(child, start: range.lowerBound, end: range.upperBound, depth: depth + 1)
  }

  private mutating func increment(
    _ counter: ManifestWireCounter,
    maximum: UInt64
  ) throws {
    let current: UInt64
    switch counter {
    case .files: current = counters.fileCount
    case .chunks: current = counters.chunkCount
    case .patches: current = counters.patchCount
    case .deleteGroups: current = counters.deleteGroupCount
    case .deleteEntries: current = counters.deleteEntryCount
    }
    let (next, overflow) = current.addingReportingOverflow(1)
    guard !overflow, next <= maximum else {
      throw ManifestProtobufWireScanningError.resourceLimit
    }
    switch counter {
    case .files: counters.fileCount = next
    case .chunks: counters.chunkCount = next
    case .patches: counters.patchCount = next
    case .deleteGroups: counters.deleteGroupCount = next
    case .deleteEntries: counters.deleteEntryCount = next
    }
  }

  private mutating func markSingular(
    _ field: UInt64,
    mask: inout UInt16
  ) throws {
    guard field < 16 else { throw ManifestProtobufWireScanningError.schemaDrift }
    let bit = UInt16(1) << UInt16(field)
    guard mask & bit == 0 else { throw ManifestProtobufWireScanningError.schemaDrift }
    mask |= bit
  }

  private mutating func addNode() throws {
    let (next, overflow) = counters.nodeCount.addingReportingOverflow(1)
    guard !overflow, next <= limits.maximumNodeCount else {
      throw ManifestProtobufWireScanningError.resourceLimit
    }
    counters.nodeCount = next
  }

  private mutating func readLengthDelimited(
    index: inout Int,
    end: Int
  ) throws -> Range<Int> {
    let rawLength = try readMinimalVarint(index: &index, end: end)
    guard let length = Int(exactly: rawLength) else {
      throw ManifestProtobufWireScanningError.invalidWire
    }
    let (upperBound, overflow) = index.addingReportingOverflow(length)
    guard !overflow, upperBound <= end else {
      throw ManifestProtobufWireScanningError.invalidWire
    }
    let range = index..<upperBound
    index = upperBound
    return range
  }

  private mutating func readMinimalVarint(
    index: inout Int,
    end: Int
  ) throws -> UInt64 {
    let start = index
    var result: UInt64 = 0
    var shift: UInt64 = 0
    for byteIndex in 0..<10 {
      guard index < end else { throw ManifestProtobufWireScanningError.invalidWire }
      let byte = bytes[index]
      index += 1
      let payload = UInt64(byte & 0x7F)
      if byteIndex == 9, payload > 1 {
        throw ManifestProtobufWireScanningError.invalidWire
      }
      result |= payload << shift
      if byte & 0x80 == 0 {
        let encodedLength = index - start
        let minimumLength = result == 0 ? 1 : (64 - result.leadingZeroBitCount + 6) / 7
        guard encodedLength == minimumLength else {
          throw ManifestProtobufWireScanningError.invalidWire
        }
        return result
      }
      shift += 7
    }
    throw ManifestProtobufWireScanningError.invalidWire
  }

  private mutating func cancellationCheckpoint(at index: Int) throws {
    if scannedFieldCount & 0x3FF == 0 || index - lastCancellationByte >= 64 * 1_024 {
      try Task.checkCancellation()
      lastCancellationByte = index
    }
  }
}
