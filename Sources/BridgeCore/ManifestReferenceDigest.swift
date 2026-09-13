import Foundation

struct ManifestReferenceID: Equatable, Hashable, Sendable {
  fileprivate let rawValue: String

  init(_ value: String) throws {
    guard value != ".", value != "..", !value.isEmpty, value.utf8.count <= 256,
      value.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 46 || $0 == 95
      })
    else {
      throw ManifestAdapterError.invalidManifest
    }
    rawValue = value
  }
}

extension ManifestReferenceID: CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  var description: String { "<redacted>" }
  var debugDescription: String { "<redacted>" }
  var customMirror: Mirror {
    Mirror(self, children: ["redacted": true], displayStyle: .struct)
  }
}

enum ManifestReferenceKind: UInt8, Equatable, Sendable {
  case chunk = 1
  case ldiff = 2
}

enum ManifestReferenceCompression: UInt8, Equatable, Sendable {
  case zstdProtobuf = 1
}

struct ManifestReferenceDigest: Equatable, Hashable, Sendable {
  static let currentVersion: UInt8 = 1

  private static let domain = Array("MGBMANIFESTREF\0".utf8)

  let lowercaseHex: String

  static func parseLowercaseHex(_ value: String) throws -> Self {
    guard value.utf8.count == 64,
      value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else {
      throw ManifestAdapterError.invalidManifest
    }
    return Self(lowercaseHex: value)
  }

  static func make(
    release: GameRelease,
    category: ResourceCategory,
    manifestID: ManifestReferenceID,
    profileRevision: UInt64,
    kind: ManifestReferenceKind,
    compression: ManifestReferenceCompression = .zstdProtobuf
  ) throws -> Self {
    guard profileRevision > 0 else {
      throw ManifestAdapterError.invalidManifest
    }
    var digest = CanonicalSHA256Builder(domain: domain)
    digest.append(currentVersion)
    digest.appendFramed(release.rawValue)
    digest.appendFramed(category.rawValue)
    digest.appendFramed(manifestID.rawValue)
    digest.append(profileRevision)
    digest.append(kind.rawValue)
    digest.append(compression.rawValue)
    return try parseLowercaseHex(digest.finalize())
  }

  private init(lowercaseHex: String) {
    self.lowercaseHex = lowercaseHex
  }
}
