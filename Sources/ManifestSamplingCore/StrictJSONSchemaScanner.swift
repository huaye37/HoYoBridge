import CryptoKit
import Foundation

package struct JSONValueFreeShape: Equatable, Sendable {
  package let policyVersion: UInt8
  package let sha256: String
  package let gameBranchEntryCount: UInt64
  package let safeReport: SafeJSONShapeReport?
}

extension JSONValueFreeShape: ManifestSamplingRedactedValue {}

package struct JSONRootDataValueFreeShape: Equatable, Sendable {
  package let policyVersion: UInt8
  package let sha256: String
  package let safeReport: SafeJSONShapeReport?
}

extension JSONRootDataValueFreeShape: ManifestSamplingRedactedValue {}

package enum StrictJSONSchemaScanner {
  package static let maximumRootDataInputBytes = 8 * 1_024 * 1_024

  package static func scan(
    _ data: Data,
    reportLimits: SafeJSONShapeReportLimits? = nil,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> JSONValueFreeShape {
    try cancellationCheck()
    guard data.count <= JSONSchemaParser.maximumInputBytes else {
      throw ManifestSamplingError.resourceLimit
    }

    var parser = JSONSchemaParser(
      bytes: Array(data),
      requiredAnchors: .branches,
      reportLimits: reportLimits,
      cancellationCheck: cancellationCheck
    )
    let parsed = try parser.scan()
    guard let gameBranchEntryCount = parsed.gameBranchEntryCount else {
      throw ManifestSamplingError.malformedJSON
    }
    return JSONValueFreeShape(
      policyVersion: parsed.policyVersion,
      sha256: parsed.sha256,
      gameBranchEntryCount: gameBranchEntryCount,
      safeReport: parsed.safeReport
    )
  }

  package static func scanRootData(
    _ data: Data,
    reportLimits: SafeJSONShapeReportLimits? = nil,
    cancellationCheck: @escaping @Sendable () throws -> Void = {
      try Task.checkCancellation()
    }
  ) throws -> JSONRootDataValueFreeShape {
    try cancellationCheck()
    guard data.count <= maximumRootDataInputBytes else {
      throw ManifestSamplingError.resourceLimit
    }
    var parser = JSONSchemaParser(
      bytes: Array(data),
      requiredAnchors: .rootData,
      reportLimits: reportLimits,
      cancellationCheck: cancellationCheck
    )
    let parsed = try parser.scan()
    return JSONRootDataValueFreeShape(
      policyVersion: parsed.policyVersion,
      sha256: parsed.sha256,
      safeReport: parsed.safeReport
    )
  }
}

private struct JSONSchemaParser {
  static let maximumInputBytes = 1_024 * 1_024

  private static let policyVersion: UInt8 = 1
  private static let maximumDepth = 16
  private static let maximumNodeCount = 16_384
  private static let maximumStringBytes = 64 * 1_024
  private static let maximumTotalStringBytes = 512 * 1_024
  private static let maximumNumberTokenBytes = 128
  private static let cancellationStride = 4 * 1_024
  private static let cancellationNodeStride = 256
  private static let cancellationNumberStride = 64
  private static let shapeNodeDomain = Data("MacGameBridge.JSONValueFreeShape.Node.v1".utf8)

  private static let retcodeKey = Data("retcode".utf8)
  private static let dataKey = Data("data".utf8)
  private static let gameBranchesKey = Data("game_branches".utf8)
  private static let knownSafeKeys: Set<Data> = [
    retcodeKey,
    dataKey,
    gameBranchesKey,
    Data("message".utf8),
    Data("game".utf8),
    Data("main".utf8),
    Data("pre_download".utf8),
    Data("tag".utf8),
    Data("branch".utf8),
    Data("package_id".utf8),
    Data("password".utf8),
  ]

  private let bytes: [UInt8]
  private let requiredAnchors: JSONRequiredAnchors
  private let reportLimits: SafeJSONShapeReportLimits?
  private let cancellationCheck: @Sendable () throws -> Void
  private var index = 0
  private var nodeCount = 0
  private var totalStringBytes = 0
  private var nextCancellationIndex = 0
  private var sawRetcode = false
  private var sawData = false
  private var sawGameBranches = false
  private var gameBranchEntryCount: UInt64?

  init(
    bytes: [UInt8],
    requiredAnchors: JSONRequiredAnchors,
    reportLimits: SafeJSONShapeReportLimits?,
    cancellationCheck: @escaping @Sendable () throws -> Void
  ) {
    self.bytes = bytes
    self.requiredAnchors = requiredAnchors
    self.reportLimits = reportLimits
    self.cancellationCheck = cancellationCheck
  }

  mutating func scan() throws -> JSONParsedValueFreeShape {
    try cancellationCheckpoint(force: true)
    try skipWhitespace()
    guard currentByte == JSONByte.leftBrace else {
      throw ManifestSamplingError.malformedJSON
    }

    let rootShape = try parseValue(path: [], depth: 1, requirement: .object)
    try skipWhitespace()
    guard index == bytes.count, sawRetcode, sawData else {
      throw ManifestSamplingError.malformedJSON
    }
    if requiredAnchors == .branches,
      !sawGameBranches || gameBranchEntryCount == nil
    {
      throw ManifestSamplingError.malformedJSON
    }

    try cancellationCheckpoint(force: true)
    let digest =
      rootShape.digest
      .map { String(format: "%02x", $0) }
      .joined()
    let safeReport: SafeJSONShapeReport?
    if let reportLimits, let root = rootShape.reportNode {
      safeReport = try SafeJSONShapeReportPolicyV1.make(
        root: root,
        limits: reportLimits,
        cancellationCheck: cancellationCheck
      )
    } else {
      safeReport = nil
    }
    return JSONParsedValueFreeShape(
      policyVersion: Self.policyVersion,
      sha256: digest,
      gameBranchEntryCount: gameBranchEntryCount,
      safeReport: safeReport
    )
  }

  private mutating func parseValue(
    path: [JSONSchemaPathComponent],
    depth: Int,
    requirement: JSONValueRequirement = .none
  ) throws -> JSONShapeBuild {
    try cancellationCheckpoint()
    guard depth <= Self.maximumDepth else {
      throw ManifestSamplingError.resourceLimit
    }
    guard nodeCount < Self.maximumNodeCount else {
      throw ManifestSamplingError.resourceLimit
    }
    nodeCount += 1
    if nodeCount.isMultiple(of: Self.cancellationNodeStride) {
      try cancellationCheck()
    }
    try skipWhitespace()

    guard let token = currentByte else {
      throw ManifestSamplingError.malformedJSON
    }
    let shape: JSONShapeBuild
    switch token {
    case JSONByte.leftBrace:
      guard requirement == .none || requirement == .object else {
        throw ManifestSamplingError.malformedJSON
      }
      shape = try parseObject(path: path, depth: depth)
    case JSONByte.leftBracket:
      guard requirement == .none || requirement == .array else {
        throw ManifestSamplingError.malformedJSON
      }
      shape = try parseArray(path: path, depth: depth)
    case JSONByte.quote:
      guard requirement == .none else {
        throw ManifestSamplingError.malformedJSON
      }
      _ = try parseString()
      shape = makeScalarShape(.string)
    case JSONByte.minus, JSONByte.zero...JSONByte.nine:
      guard requirement == .none || requirement == .numericZero else {
        throw ManifestSamplingError.malformedJSON
      }
      let range = try parseNumber()
      if requirement == .numericZero,
        range.count != 1 || bytes[range.lowerBound] != JSONByte.zero
      {
        throw ManifestSamplingError.malformedJSON
      }
      shape = makeScalarShape(.number)
    case JSONByte.lowercaseT:
      guard requirement == .none else {
        throw ManifestSamplingError.malformedJSON
      }
      try consumeLiteral([0x74, 0x72, 0x75, 0x65])
      shape = makeScalarShape(.boolean)
    case JSONByte.lowercaseF:
      guard requirement == .none else {
        throw ManifestSamplingError.malformedJSON
      }
      try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])
      shape = makeScalarShape(.boolean)
    case JSONByte.lowercaseN:
      guard requirement == .none else {
        throw ManifestSamplingError.malformedJSON
      }
      try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C])
      shape = makeScalarShape(.null)
    default:
      throw ManifestSamplingError.malformedJSON
    }

    return shape
  }

  private mutating func parseObject(
    path: [JSONSchemaPathComponent],
    depth: Int
  ) throws -> JSONShapeBuild {
    try consume(JSONByte.leftBrace)
    try skipWhitespace()
    if consumeIfPresent(JSONByte.rightBrace) {
      return try makeObjectShape([])
    }

    var keys: Set<Data> = []
    var entries: [(key: JSONShapeKeyMaterial, child: JSONShapeBuild)] = []
    while true {
      try skipWhitespace()
      guard currentByte == JSONByte.quote else {
        throw ManifestSamplingError.malformedJSON
      }
      let key = try parseString()
      guard keys.insert(key).inserted else {
        throw ManifestSamplingError.duplicateJSONKey
      }
      try skipWhitespace()
      try consume(JSONByte.colon)

      let childPath = path + [.key(key)]
      let requirement: JSONValueRequirement
      if path.isEmpty, key == Self.retcodeKey {
        requirement = .numericZero
      } else if path.isEmpty, key == Self.dataKey {
        requirement = .object
      } else if isDataObject(path), key == Self.gameBranchesKey {
        requirement = .array
      } else {
        requirement = .none
      }
      let child = try parseValue(
        path: childPath,
        depth: depth + 1,
        requirement: requirement
      )
      entries.append((keyMaterial(key), child))

      if path.isEmpty, key == Self.retcodeKey {
        sawRetcode = true
      } else if path.isEmpty, key == Self.dataKey {
        sawData = true
      } else if isDataObject(path), key == Self.gameBranchesKey {
        sawGameBranches = true
      }

      try skipWhitespace()
      if consumeIfPresent(JSONByte.rightBrace) {
        return try makeObjectShape(entries)
      }
      try consume(JSONByte.comma)
    }
  }

  private mutating func parseArray(
    path: [JSONSchemaPathComponent],
    depth: Int
  ) throws -> JSONShapeBuild {
    try consume(JSONByte.leftBracket)
    try skipWhitespace()
    var itemCount: UInt64 = 0
    var elementShapes: [Data: JSONShapeBuild] = [:]
    if !consumeIfPresent(JSONByte.rightBracket) {
      while true {
        guard itemCount < UInt64.max else {
          throw ManifestSamplingError.resourceLimit
        }
        itemCount += 1
        let element = try parseValue(path: path + [.arrayItem], depth: depth + 1)
        elementShapes[element.digest] = element
        try skipWhitespace()
        if consumeIfPresent(JSONByte.rightBracket) {
          break
        }
        try consume(JSONByte.comma)
      }
    }
    if isGameBranchesArray(path) {
      gameBranchEntryCount = itemCount
    }
    return try makeArrayShape(elementShapes)
  }

  private mutating func parseString() throws -> Data {
    try consume(JSONByte.quote)
    var decoded = Data()

    while index < bytes.count {
      try cancellationCheckpoint()
      let byte = bytes[index]
      if byte == JSONByte.quote {
        index += 1
        guard String(data: decoded, encoding: .utf8) != nil else {
          throw ManifestSamplingError.malformedJSON
        }
        guard totalStringBytes <= Self.maximumTotalStringBytes - decoded.count else {
          throw ManifestSamplingError.resourceLimit
        }
        totalStringBytes += decoded.count
        return decoded
      }
      if byte < 0x20 {
        throw ManifestSamplingError.malformedJSON
      }
      if byte != JSONByte.backslash {
        try appendDecodedByte(byte, to: &decoded)
        index += 1
        continue
      }

      index += 1
      guard let escape = currentByte else {
        throw ManifestSamplingError.malformedJSON
      }
      index += 1
      switch escape {
      case JSONByte.quote, JSONByte.backslash, JSONByte.slash:
        try appendDecodedByte(escape, to: &decoded)
      case 0x62:
        try appendDecodedByte(0x08, to: &decoded)
      case 0x66:
        try appendDecodedByte(0x0C, to: &decoded)
      case 0x6E:
        try appendDecodedByte(0x0A, to: &decoded)
      case 0x72:
        try appendDecodedByte(0x0D, to: &decoded)
      case 0x74:
        try appendDecodedByte(0x09, to: &decoded)
      case 0x75:
        let first = try parseHexQuad()
        let scalar: UInt32
        if (0xD800...0xDBFF).contains(first) {
          guard currentByte == JSONByte.backslash,
            index + 1 < bytes.count,
            bytes[index + 1] == 0x75
          else {
            throw ManifestSamplingError.malformedJSON
          }
          index += 2
          let second = try parseHexQuad()
          guard (0xDC00...0xDFFF).contains(second) else {
            throw ManifestSamplingError.malformedJSON
          }
          scalar = 0x1_0000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
        } else {
          guard !(0xDC00...0xDFFF).contains(first) else {
            throw ManifestSamplingError.malformedJSON
          }
          scalar = UInt32(first)
        }
        guard let unicodeScalar = UnicodeScalar(scalar) else {
          throw ManifestSamplingError.malformedJSON
        }
        for scalarByte in String(unicodeScalar).utf8 {
          try appendDecodedByte(scalarByte, to: &decoded)
        }
      default:
        throw ManifestSamplingError.malformedJSON
      }
    }
    throw ManifestSamplingError.malformedJSON
  }

  private mutating func appendDecodedByte(_ byte: UInt8, to decoded: inout Data) throws {
    guard decoded.count < Self.maximumStringBytes else {
      throw ManifestSamplingError.resourceLimit
    }
    decoded.append(byte)
  }

  private mutating func parseHexQuad() throws -> UInt16 {
    guard index <= bytes.count - 4 else {
      throw ManifestSamplingError.malformedJSON
    }
    var value: UInt16 = 0
    for _ in 0..<4 {
      let byte = bytes[index]
      index += 1
      let digit: UInt16
      switch byte {
      case 0x30...0x39: digit = UInt16(byte - 0x30)
      case 0x41...0x46: digit = UInt16(byte - 0x41 + 10)
      case 0x61...0x66: digit = UInt16(byte - 0x61 + 10)
      default: throw ManifestSamplingError.malformedJSON
      }
      value = value * 16 + digit
    }
    return value
  }

  private mutating func parseNumber() throws -> Range<Int> {
    let start = index
    if currentByte == JSONByte.minus {
      index += 1
      try validateNumberProgress(from: start)
    }
    guard let first = currentByte else {
      throw ManifestSamplingError.malformedJSON
    }
    if first == JSONByte.zero {
      index += 1
      try validateNumberProgress(from: start)
      if let next = currentByte, (JSONByte.zero...JSONByte.nine).contains(next) {
        throw ManifestSamplingError.malformedJSON
      }
    } else if (JSONByte.one...JSONByte.nine).contains(first) {
      index += 1
      try validateNumberProgress(from: start)
      while let next = currentByte, (JSONByte.zero...JSONByte.nine).contains(next) {
        index += 1
        try validateNumberProgress(from: start)
      }
    } else {
      throw ManifestSamplingError.malformedJSON
    }

    if consumeIfPresent(JSONByte.period) {
      try validateNumberProgress(from: start)
      guard let firstFraction = currentByte,
        (JSONByte.zero...JSONByte.nine).contains(firstFraction)
      else {
        throw ManifestSamplingError.malformedJSON
      }
      repeat {
        index += 1
        try validateNumberProgress(from: start)
      } while currentByte.map {
        (JSONByte.zero...JSONByte.nine).contains($0)
      } == true
    }

    if currentByte == JSONByte.lowercaseE || currentByte == JSONByte.uppercaseE {
      index += 1
      try validateNumberProgress(from: start)
      if currentByte == JSONByte.plus || currentByte == JSONByte.minus {
        index += 1
        try validateNumberProgress(from: start)
      }
      guard let firstExponent = currentByte,
        (JSONByte.zero...JSONByte.nine).contains(firstExponent)
      else {
        throw ManifestSamplingError.malformedJSON
      }
      repeat {
        index += 1
        try validateNumberProgress(from: start)
      } while currentByte.map {
        (JSONByte.zero...JSONByte.nine).contains($0)
      } == true
    }
    return start..<index
  }

  private mutating func validateNumberProgress(from start: Int) throws {
    guard index - start <= Self.maximumNumberTokenBytes else {
      throw ManifestSamplingError.resourceLimit
    }
    if (index - start).isMultiple(of: Self.cancellationNumberStride) {
      try cancellationCheck()
    }
    try cancellationCheckpoint()
  }

  private mutating func consumeLiteral(_ literal: [UInt8]) throws {
    guard index <= bytes.count - literal.count,
      bytes[index..<(index + literal.count)].elementsEqual(literal)
    else {
      throw ManifestSamplingError.malformedJSON
    }
    index += literal.count
  }

  private mutating func consume(_ expected: UInt8) throws {
    guard currentByte == expected else {
      throw ManifestSamplingError.malformedJSON
    }
    index += 1
  }

  private mutating func consumeIfPresent(_ byte: UInt8) -> Bool {
    guard currentByte == byte else { return false }
    index += 1
    return true
  }

  private mutating func skipWhitespace() throws {
    while let byte = currentByte,
      byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    {
      index += 1
      try cancellationCheckpoint()
    }
  }

  private mutating func cancellationCheckpoint(force: Bool = false) throws {
    guard force || index >= nextCancellationIndex else { return }
    try cancellationCheck()
    nextCancellationIndex = index + Self.cancellationStride
  }

  private var currentByte: UInt8? {
    index < bytes.count ? bytes[index] : nil
  }

  private func isDataObject(_ path: [JSONSchemaPathComponent]) -> Bool {
    guard path.count == 1, case .key(let key) = path[0] else { return false }
    return key == Self.dataKey
  }

  private func isGameBranchesArray(_ path: [JSONSchemaPathComponent]) -> Bool {
    guard path.count == 2,
      case .key(let dataKey) = path[0],
      case .key(let branchesKey) = path[1]
    else {
      return false
    }
    return dataKey == Self.dataKey && branchesKey == Self.gameBranchesKey
  }

  private mutating func makeObjectShape(
    _ entries: [(key: JSONShapeKeyMaterial, child: JSONShapeBuild)]
  ) throws -> JSONShapeBuild {
    let sortedEntries = entries.sorted {
      if $0.key.identity != $1.key.identity {
        return $0.key.identity.lexicographicallyPrecedes($1.key.identity)
      }
      return $0.child.digest.lexicographicallyPrecedes($1.child.digest)
    }
    var framed = Self.shapeNodeDomain
    framed.append(JSONNodeKind.object.rawValue)
    framed.appendUInt32(UInt32(sortedEntries.count))
    for (entryIndex, entry) in sortedEntries.enumerated() {
      if entryIndex.isMultiple(of: Self.cancellationNodeStride) {
        try cancellationCheck()
      }
      framed.appendUInt32(UInt32(entry.key.identity.count))
      framed.append(entry.key.identity)
      framed.appendUInt32(UInt32(entry.child.digest.count))
      framed.append(entry.child.digest)
    }
    let reportNode: SafeJSONShapeNode?
    if reportLimits != nil {
      let fields = try sortedEntries.map { entry in
        guard let childNode = entry.child.reportNode else {
          throw ManifestSamplingError.shapeReportLimit
        }
        return SafeJSONShapeField(key: entry.key.reportKey, value: childNode)
      }
      reportNode = SafeJSONShapeNode(storage: .object(fields))
    } else {
      reportNode = nil
    }
    return JSONShapeBuild(
      digest: Data(SHA256.hash(data: framed)),
      reportNode: reportNode
    )
  }

  private mutating func makeArrayShape(
    _ elementShapes: [Data: JSONShapeBuild]
  ) throws -> JSONShapeBuild {
    let sortedShapes = elementShapes.keys.sorted { $0.lexicographicallyPrecedes($1) }
    var framed = Self.shapeNodeDomain
    framed.append(JSONNodeKind.array.rawValue)
    framed.appendUInt32(UInt32(sortedShapes.count))
    for (shapeIndex, shape) in sortedShapes.enumerated() {
      if shapeIndex.isMultiple(of: Self.cancellationNodeStride) {
        try cancellationCheck()
      }
      framed.appendUInt32(UInt32(shape.count))
      framed.append(shape)
    }
    let reportNode: SafeJSONShapeNode?
    if reportLimits != nil {
      let nodes = try sortedShapes.map { shape -> SafeJSONShapeNode in
        guard let node = elementShapes[shape]?.reportNode else {
          throw ManifestSamplingError.shapeReportLimit
        }
        return node
      }
      reportNode = SafeJSONShapeNode(storage: .array(nodes))
    } else {
      reportNode = nil
    }
    return JSONShapeBuild(
      digest: Data(SHA256.hash(data: framed)),
      reportNode: reportNode
    )
  }

  private func makeScalarShape(_ kind: JSONNodeKind) -> JSONShapeBuild {
    var framed = Self.shapeNodeDomain
    framed.append(kind.rawValue)
    let storage: SafeJSONShapeNode.Storage
    switch kind {
    case .string: storage = .string
    case .number: storage = .number
    case .boolean: storage = .boolean
    case .null: storage = .null
    case .object, .array:
      preconditionFailure("Composite JSON shape must use its dedicated builder")
    }
    return JSONShapeBuild(
      digest: Data(SHA256.hash(data: framed)),
      reportNode: reportLimits == nil ? nil : SafeJSONShapeNode(storage: storage)
    )
  }

  private func keyMaterial(_ key: Data) -> JSONShapeKeyMaterial {
    let reportKey: SafeJSONShapeKey
    if SafeJSONShapeReportPolicyV1.knownKeyData.contains(key),
      let knownName = String(data: key, encoding: .utf8)
    {
      reportKey = .known(knownName)
    } else {
      let keyDigest = SHA256.hash(data: key)
        .map { String(format: "%02x", $0) }
        .joined()
      reportKey = .unknownSHA256(keyDigest)
    }
    if Self.knownSafeKeys.contains(key) {
      var identity = Data([0x01])
      identity.appendUInt32(UInt32(key.count))
      identity.append(key)
      return JSONShapeKeyMaterial(identity: identity, reportKey: reportKey)
    }
    let digest = Data(SHA256.hash(data: key))
    var identity = Data([0x02])
    identity.appendUInt32(UInt32(digest.count))
    identity.append(digest)
    return JSONShapeKeyMaterial(identity: identity, reportKey: reportKey)
  }
}

private struct JSONShapeBuild {
  let digest: Data
  let reportNode: SafeJSONShapeNode?
}

private struct JSONParsedValueFreeShape {
  let policyVersion: UInt8
  let sha256: String
  let gameBranchEntryCount: UInt64?
  let safeReport: SafeJSONShapeReport?
}

private enum JSONRequiredAnchors {
  case branches
  case rootData
}

private struct JSONShapeKeyMaterial {
  let identity: Data
  let reportKey: SafeJSONShapeKey
}

private enum JSONSchemaPathComponent {
  case key(Data)
  case arrayItem
}

private enum JSONNodeKind: UInt8 {
  case object = 1
  case array = 2
  case string = 3
  case number = 4
  case boolean = 5
  case null = 6
}

private enum JSONValueRequirement {
  case none
  case object
  case array
  case numericZero
}

private enum JSONByte {
  static let quote: UInt8 = 0x22
  static let plus: UInt8 = 0x2B
  static let comma: UInt8 = 0x2C
  static let minus: UInt8 = 0x2D
  static let period: UInt8 = 0x2E
  static let slash: UInt8 = 0x2F
  static let zero: UInt8 = 0x30
  static let one: UInt8 = 0x31
  static let nine: UInt8 = 0x39
  static let colon: UInt8 = 0x3A
  static let uppercaseE: UInt8 = 0x45
  static let leftBracket: UInt8 = 0x5B
  static let backslash: UInt8 = 0x5C
  static let rightBracket: UInt8 = 0x5D
  static let lowercaseE: UInt8 = 0x65
  static let lowercaseF: UInt8 = 0x66
  static let lowercaseN: UInt8 = 0x6E
  static let lowercaseT: UInt8 = 0x74
  static let leftBrace: UInt8 = 0x7B
  static let rightBrace: UInt8 = 0x7D
}

extension Data {
  fileprivate mutating func appendUInt32(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value >> 24))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }
}
