import CryptoKit
import Foundation

package struct SafeJSONShapeReportLimits: Equatable, Sendable {
  package static let standard = SafeJSONShapeReportLimits(
    maximumNodeCount: 4_096,
    maximumArrayElementShapes: 256,
    maximumUnknownKeyCount: 1_024,
    maximumCanonicalBytes: 256 * 1_024
  )

  package let maximumNodeCount: Int
  package let maximumArrayElementShapes: Int
  package let maximumUnknownKeyCount: Int
  package let maximumCanonicalBytes: Int

  package init(
    maximumNodeCount: Int,
    maximumArrayElementShapes: Int,
    maximumUnknownKeyCount: Int,
    maximumCanonicalBytes: Int
  ) {
    self.maximumNodeCount = maximumNodeCount
    self.maximumArrayElementShapes = maximumArrayElementShapes
    self.maximumUnknownKeyCount = maximumUnknownKeyCount
    self.maximumCanonicalBytes = maximumCanonicalBytes
  }

  fileprivate func isNoLooserThanStandard() -> Bool {
    maximumNodeCount >= 0
      && maximumNodeCount <= Self.standard.maximumNodeCount
      && maximumArrayElementShapes >= 0
      && maximumArrayElementShapes <= Self.standard.maximumArrayElementShapes
      && maximumUnknownKeyCount >= 0
      && maximumUnknownKeyCount <= Self.standard.maximumUnknownKeyCount
      && maximumCanonicalBytes >= 0
      && maximumCanonicalBytes <= Self.standard.maximumCanonicalBytes
  }
}

package enum SafeJSONShapeReportPolicyV1 {
  package static let policyVersion: UInt8 = 1
  package static let knownKeyNames = [
    "biz", "branch", "data", "game", "game_branches", "id", "main", "message",
    "package_id", "password", "pre_download", "retcode", "tag",
  ]
  package static let unknownKeyPolicy = "sha256DecodedUTF8Only"
  package static let scalarPolicy = "kindOnlyNoValueNoLength"
  package static let objectPolicy = "sortedKeyIdentityChildShape"
  package static let arrayPolicy = "sortedUniqueChildShapeNoCountOrderMultiplicity"

  static let knownKeyData = Set(knownKeyNames.map { Data($0.utf8) })
  private static let digestDomain = Data("MGBJSONSHAPEREPORT\0".utf8)

  static func make(
    root: SafeJSONShapeNode,
    limits: SafeJSONShapeReportLimits,
    cancellationCheck: @escaping @Sendable () throws -> Void
  ) throws -> SafeJSONShapeReport {
    try cancellationCheck()
    guard limits.isNoLooserThanStandard() else {
      throw ManifestSamplingError.shapeReportLimit
    }
    _ = try root.metrics(limits: limits, cancellationCheck: cancellationCheck)
    try cancellationCheck()
    let canonical = try ManifestSamplingCanonicalJSON.encode(root)
    guard canonical.count <= limits.maximumCanonicalBytes else {
      throw ManifestSamplingError.shapeReportLimit
    }
    var digestInput = digestDomain
    digestInput.append(policyVersion)
    digestInput.append(canonical)
    let sha256 = SHA256.hash(data: digestInput)
      .map { String(format: "%02x", $0) }
      .joined()
    try cancellationCheck()
    return SafeJSONShapeReport(
      policyVersion: policyVersion,
      sha256: sha256,
      canonicalByteSize: UInt64(canonical.count),
      root: root
    )
  }
}

package struct SafeJSONShapeReport: Equatable, Sendable {
  package let policyVersion: UInt8
  package let sha256: String
  package let canonicalByteSize: UInt64
  package let root: SafeJSONShapeNode

  fileprivate init(
    policyVersion: UInt8,
    sha256: String,
    canonicalByteSize: UInt64,
    root: SafeJSONShapeNode
  ) {
    self.policyVersion = policyVersion
    self.sha256 = sha256
    self.canonicalByteSize = canonicalByteSize
    self.root = root
  }
}

extension SafeJSONShapeReport: ManifestSamplingRedactedValue {}

package struct SafeJSONShapeNode: Encodable, Equatable, Sendable {
  indirect enum Storage: Equatable, Sendable {
    case object([SafeJSONShapeField])
    case array([SafeJSONShapeNode])
    case string
    case number
    case boolean
    case null
  }

  let storage: Storage

  package func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch storage {
    case .object(let fields):
      try container.encode("object", forKey: .kind)
      try container.encode(fields, forKey: .fields)
    case .array(let elementShapes):
      try container.encode("array", forKey: .kind)
      try container.encode(elementShapes, forKey: .elementShapes)
    case .string:
      try container.encode("string", forKey: .kind)
    case .number:
      try container.encode("number", forKey: .kind)
    case .boolean:
      try container.encode("boolean", forKey: .kind)
    case .null:
      try container.encode("null", forKey: .kind)
    }
  }

  fileprivate func metrics(
    limits: SafeJSONShapeReportLimits,
    cancellationCheck: @escaping @Sendable () throws -> Void
  ) throws -> SafeJSONShapeMetrics {
    try cancellationCheck()
    var metrics = SafeJSONShapeMetrics(nodeCount: 1, unknownKeyCount: 0)
    try metrics.validate(limits: limits)
    switch storage {
    case .object(let fields):
      for field in fields {
        let child = try field.value.metrics(
          limits: limits,
          cancellationCheck: cancellationCheck
        )
        metrics = try metrics.adding(child, limits: limits)
        if field.key.isUnknown {
          metrics.unknownKeyCount += 1
          try metrics.validate(limits: limits)
        }
      }
    case .array(let elementShapes):
      guard elementShapes.count <= limits.maximumArrayElementShapes else {
        throw ManifestSamplingError.shapeReportLimit
      }
      for elementShape in elementShapes {
        metrics = try metrics.adding(
          elementShape.metrics(
            limits: limits,
            cancellationCheck: cancellationCheck
          ),
          limits: limits
        )
      }
    case .string, .number, .boolean, .null:
      break
    }
    return metrics
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case fields
    case elementShapes
  }
}

extension SafeJSONShapeNode: ManifestSamplingRedactedValue {}

struct SafeJSONShapeField: Encodable, Equatable, Sendable {
  let key: SafeJSONShapeKey
  let value: SafeJSONShapeNode
}

enum SafeJSONShapeKey: Encodable, Equatable, Sendable {
  case known(String)
  case unknownSHA256(String)

  var isUnknown: Bool {
    if case .unknownSHA256 = self { return true }
    return false
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .known(let name):
      try container.encode("known", forKey: .kind)
      try container.encode(name, forKey: .name)
    case .unknownSHA256(let sha256):
      try container.encode("unknownSHA256", forKey: .kind)
      try container.encode(sha256, forKey: .sha256)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case name
    case sha256
  }
}

private struct SafeJSONShapeMetrics {
  var nodeCount: Int
  var unknownKeyCount: Int

  mutating func validate(limits: SafeJSONShapeReportLimits) throws {
    guard nodeCount <= limits.maximumNodeCount,
      unknownKeyCount <= limits.maximumUnknownKeyCount
    else {
      throw ManifestSamplingError.shapeReportLimit
    }
  }

  func adding(
    _ other: SafeJSONShapeMetrics,
    limits: SafeJSONShapeReportLimits
  ) throws -> SafeJSONShapeMetrics {
    let (nodes, nodeOverflow) = nodeCount.addingReportingOverflow(other.nodeCount)
    let (unknownKeys, keyOverflow) = unknownKeyCount.addingReportingOverflow(
      other.unknownKeyCount)
    guard !nodeOverflow, !keyOverflow else {
      throw ManifestSamplingError.shapeReportLimit
    }
    var combined = SafeJSONShapeMetrics(
      nodeCount: nodes,
      unknownKeyCount: unknownKeys
    )
    try combined.validate(limits: limits)
    return combined
  }
}
