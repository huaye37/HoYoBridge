import CryptoKit
import Foundation

public struct SignedCatalogEnvelope: Codable, Equatable, Sendable {
  public let formatVersion: Int
  public let keyID: String
  public let payload: String
  public let signature: String

  public init(formatVersion: Int = 1, keyID: String, payload: String, signature: String) {
    self.formatVersion = formatVersion
    self.keyID = keyID
    self.payload = payload
    self.signature = signature
  }
}

public enum CatalogRevisionPolicy: Equatable, Sendable {
  /// Accepts only a remote revision newer than the durably persisted last accepted revision.
  case newerThan(UInt64)

  /// Replays only the exact payload identity that was durably persisted after verification.
  case cached(revision: UInt64, payloadSHA256: String)
}

public struct CatalogTrustedKey: Equatable, Sendable {
  public let publicKey: Data
  public let allowedChannels: Set<CatalogChannel>

  public init(publicKey: Data, allowedChannels: Set<CatalogChannel>) {
    self.publicKey = publicKey
    self.allowedChannels = allowedChannels
  }
}

public enum CatalogLoadError: Error, Equatable, Sendable {
  case malformedCatalog
  case malformedEnvelope
  case unsupportedEnvelopeFormat(Int)
  case unknownSigningKey(String)
  case invalidBase64
  case invalidPublicKey
  case invalidSignature
  case invalidCatalog([CatalogIssue])
  case revisionRejected(received: UInt64, policy: CatalogRevisionPolicy)
  case clientTooOld(required: String, current: String)
  case invalidClientVersion(String)
  case unexpectedChannel(CatalogChannel)
  case signingKeyNotAuthorized(keyID: String, channel: CatalogChannel)
  case catalogTooLarge
  case unsignedCatalogRequiresDevelopmentChannel
}

public enum SignedCatalogLoader {
  private static let maximumEnvelopeBytes = 4 * 1_024 * 1_024
  private static let maximumPayloadBytes = 3 * 1_024 * 1_024

  public static func load(
    envelopeData: Data,
    trustedKeys: [String: CatalogTrustedKey],
    currentClientVersion: String,
    acceptedChannels: Set<CatalogChannel> = [.stable],
    revisionPolicy: CatalogRevisionPolicy,
    now: Date = Date()
  ) throws -> VerifiedCatalog {
    guard envelopeData.count <= maximumEnvelopeBytes else {
      throw CatalogLoadError.catalogTooLarge
    }
    let envelope: SignedCatalogEnvelope
    do {
      envelope = try decoder().decode(SignedCatalogEnvelope.self, from: envelopeData)
    } catch {
      throw CatalogLoadError.malformedEnvelope
    }

    guard envelope.formatVersion == 1 else {
      throw CatalogLoadError.unsupportedEnvelopeFormat(envelope.formatVersion)
    }
    guard let trustedKey = trustedKeys[envelope.keyID] else {
      throw CatalogLoadError.unknownSigningKey(envelope.keyID)
    }
    guard let payloadData = Data(base64Encoded: envelope.payload),
      let signatureData = Data(base64Encoded: envelope.signature)
    else {
      throw CatalogLoadError.invalidBase64
    }
    guard payloadData.count <= maximumPayloadBytes else {
      throw CatalogLoadError.catalogTooLarge
    }

    let publicKey: Curve25519.Signing.PublicKey
    do {
      publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: trustedKey.publicKey)
    } catch {
      throw CatalogLoadError.invalidPublicKey
    }
    guard publicKey.isValidSignature(signatureData, for: payloadData) else {
      throw CatalogLoadError.invalidSignature
    }

    let catalog = try decodeAndValidate(payloadData, at: now)
    guard acceptedChannels.contains(catalog.channel) else {
      throw CatalogLoadError.unexpectedChannel(catalog.channel)
    }
    guard trustedKey.allowedChannels.contains(catalog.channel) else {
      throw CatalogLoadError.signingKeyNotAuthorized(
        keyID: envelope.keyID, channel: catalog.channel)
    }
    let payloadSHA256 = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
    guard accepts(catalog.revision, payloadSHA256: payloadSHA256, policy: revisionPolicy) else {
      throw CatalogLoadError.revisionRejected(received: catalog.revision, policy: revisionPolicy)
    }
    guard let currentVersion = parseVersion(currentClientVersion) else {
      throw CatalogLoadError.invalidClientVersion(currentClientVersion)
    }
    guard let requiredVersion = parseVersion(catalog.minimumClientVersion) else {
      throw CatalogLoadError.invalidCatalog([
        .init(
          code: "invalid-client-version", path: "minimumClientVersion",
          message: "Minimum client version must use canonical ASCII numeric components.")
      ])
    }
    guard compareVersions(currentVersion, requiredVersion) != .orderedAscending else {
      throw CatalogLoadError.clientTooOld(
        required: catalog.minimumClientVersion, current: currentClientVersion)
    }
    return VerifiedCatalog(catalog: catalog, payloadSHA256: payloadSHA256)
  }

  public static func loadUnsignedDevelopmentCatalog(
    _ data: Data,
    now: Date = Date()
  ) throws -> CompatibilityCatalog {
    guard data.count <= maximumPayloadBytes else {
      throw CatalogLoadError.catalogTooLarge
    }
    let catalog = try decodeAndValidate(data, at: now)
    guard catalog.channel == .development else {
      throw CatalogLoadError.unsignedCatalogRequiresDevelopmentChannel
    }
    return catalog
  }

  private static func decodeAndValidate(_ data: Data, at date: Date) throws -> CompatibilityCatalog
  {
    let catalog: CompatibilityCatalog
    do {
      catalog = try decoder().decode(CompatibilityCatalog.self, from: data)
    } catch {
      throw CatalogLoadError.malformedCatalog
    }

    let issues = CatalogValidator.issues(in: catalog, at: date)
    guard issues.isEmpty else {
      throw CatalogLoadError.invalidCatalog(issues)
    }
    return catalog
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private static func accepts(
    _ revision: UInt64,
    payloadSHA256: String,
    policy: CatalogRevisionPolicy
  ) -> Bool {
    switch policy {
    case .newerThan(let previous): revision > previous
    case .cached(let expectedRevision, let expectedDigest):
      revision == expectedRevision && payloadSHA256 == expectedDigest.lowercased()
    }
  }

  private static func parseVersion(_ value: String) -> [Int]? {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard (2...4).contains(components.count) else { return nil }
    var parsed: [Int] = []
    for component in components {
      guard !component.isEmpty,
        component.utf8.allSatisfy({ (48...57).contains($0) }),
        component.count == 1 || component.utf8.first != 48,
        let number = Int(component)
      else {
        return nil
      }
      parsed.append(number)
    }
    return parsed
  }

  private static func compareVersions(_ left: [Int], _ right: [Int]) -> ComparisonResult {
    for index in 0..<max(left.count, right.count) {
      let leftValue = index < left.count ? left[index] : 0
      let rightValue = index < right.count ? right[index] : 0
      if leftValue < rightValue { return .orderedAscending }
      if leftValue > rightValue { return .orderedDescending }
    }
    return .orderedSame
  }
}
