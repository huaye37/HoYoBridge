import CryptoKit
import Foundation
import Testing

@testable import BridgeCore

struct SignedCatalogLoaderTests {
  @Test
  func acceptsValidSignatureAndRejectsTampering() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let catalog = CatalogTestFixtures.catalog(runtimes: [], profiles: [])
    let payload = try encode(catalog)
    let signature = try privateKey.signature(for: payload)
    let envelope = SignedCatalogEnvelope(
      keyID: "test-key",
      payload: payload.base64EncodedString(),
      signature: signature.base64EncodedString()
    )

    let verified = try SignedCatalogLoader.load(
      envelopeData: encodeEnvelope(envelope),
      trustedKeys: [
        "test-key": .init(
          publicKey: privateKey.publicKey.rawRepresentation, allowedChannels: [.testing])
      ],
      currentClientVersion: "0.1.0",
      acceptedChannels: [.testing],
      revisionPolicy: .newerThan(9),
      now: CatalogTestFixtures.now
    )
    #expect(verified.catalog.revision == catalog.revision)

    var tamperedPayload = payload
    tamperedPayload.append(0x20)
    let tampered = SignedCatalogEnvelope(
      keyID: envelope.keyID,
      payload: tamperedPayload.base64EncodedString(),
      signature: envelope.signature
    )
    #expect(throws: CatalogLoadError.invalidSignature) {
      try SignedCatalogLoader.load(
        envelopeData: encodeEnvelope(tampered),
        trustedKeys: [
          "test-key": .init(
            publicKey: privateKey.publicKey.rawRepresentation, allowedChannels: [.testing])
        ],
        currentClientVersion: "0.1.0",
        acceptedChannels: [.testing],
        revisionPolicy: .newerThan(9),
        now: CatalogTestFixtures.now
      )
    }
  }

  @Test
  func rejectsRollbackAndOldClient() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let catalog = CatalogTestFixtures.catalog(
      revision: 4,
      minimumClientVersion: "2.0.0",
      runtimes: [],
      profiles: []
    )
    let payload = try encode(catalog)
    let envelope = SignedCatalogEnvelope(
      keyID: "test-key",
      payload: payload.base64EncodedString(),
      signature: try privateKey.signature(for: payload).base64EncodedString()
    )
    let envelopeData = encodeEnvelope(envelope)
    let keys = [
      "test-key": CatalogTrustedKey(
        publicKey: privateKey.publicKey.rawRepresentation, allowedChannels: [.testing])
    ]

    #expect(throws: CatalogLoadError.revisionRejected(received: 4, policy: .newerThan(4))) {
      try SignedCatalogLoader.load(
        envelopeData: envelopeData,
        trustedKeys: keys,
        currentClientVersion: "2.0.0",
        acceptedChannels: [.testing],
        revisionPolicy: .newerThan(4),
        now: CatalogTestFixtures.now
      )
    }
    #expect(throws: CatalogLoadError.clientTooOld(required: "2.0.0", current: "1.9.9")) {
      try SignedCatalogLoader.load(
        envelopeData: envelopeData,
        trustedKeys: keys,
        currentClientVersion: "1.9.9",
        acceptedChannels: [.testing],
        revisionPolicy: .newerThan(3),
        now: CatalogTestFixtures.now
      )
    }
  }

  @Test
  func cachedPolicyRequiresExactRevisionAndPayloadDigest() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let catalog = CatalogTestFixtures.catalog(runtimes: [], profiles: [])
    let payload = try encode(catalog)
    let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    let envelope = SignedCatalogEnvelope(
      keyID: "test-key",
      payload: payload.base64EncodedString(),
      signature: try privateKey.signature(for: payload).base64EncodedString()
    )
    let keys = [
      "test-key": CatalogTrustedKey(
        publicKey: privateKey.publicKey.rawRepresentation,
        allowedChannels: [.testing]
      )
    ]

    let verified = try SignedCatalogLoader.load(
      envelopeData: encodeEnvelope(envelope),
      trustedKeys: keys,
      currentClientVersion: "0.1.0",
      acceptedChannels: [.testing],
      revisionPolicy: .cached(revision: catalog.revision, payloadSHA256: payloadDigest),
      now: CatalogTestFixtures.now
    )
    #expect(verified.catalog == catalog)
    #expect(verified.payloadSHA256 == payloadDigest)

    #expect(
      throws: CatalogLoadError.revisionRejected(
        received: catalog.revision,
        policy: .cached(
          revision: catalog.revision, payloadSHA256: String(repeating: "0", count: 64))
      )
    ) {
      try SignedCatalogLoader.load(
        envelopeData: encodeEnvelope(envelope),
        trustedKeys: keys,
        currentClientVersion: "0.1.0",
        acceptedChannels: [.testing],
        revisionPolicy: .cached(
          revision: catalog.revision, payloadSHA256: String(repeating: "0", count: 64)),
        now: CatalogTestFixtures.now
      )
    }
  }

  @Test
  func sameRevisionChangedPayloadCannotReplaceAcceptedCatalogOrCache() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let acceptedCatalog = CatalogTestFixtures.catalog(runtimes: [], profiles: [])
    let changedCatalog = CatalogTestFixtures.catalog(
      revision: acceptedCatalog.revision,
      minimumClientVersion: "0.2.0",
      runtimes: [],
      profiles: []
    )
    let acceptedPayload = try encode(acceptedCatalog)
    let changedPayload = try encode(changedCatalog)
    let acceptedDigest =
      SHA256.hash(data: acceptedPayload).map { String(format: "%02x", $0) }.joined()
    let changedDigest =
      SHA256.hash(data: changedPayload).map { String(format: "%02x", $0) }.joined()
    #expect(changedDigest != acceptedDigest)

    let changedEnvelope = SignedCatalogEnvelope(
      keyID: "test-key",
      payload: changedPayload.base64EncodedString(),
      signature: try privateKey.signature(for: changedPayload).base64EncodedString()
    )
    let keys = [
      "test-key": CatalogTrustedKey(
        publicKey: privateKey.publicKey.rawRepresentation,
        allowedChannels: [.testing]
      )
    ]

    #expect(
      throws: CatalogLoadError.revisionRejected(
        received: changedCatalog.revision,
        policy: .newerThan(acceptedCatalog.revision)
      )
    ) {
      try SignedCatalogLoader.load(
        envelopeData: encodeEnvelope(changedEnvelope),
        trustedKeys: keys,
        currentClientVersion: "0.2.0",
        acceptedChannels: [.testing],
        revisionPolicy: .newerThan(acceptedCatalog.revision),
        now: CatalogTestFixtures.now
      )
    }

    #expect(
      throws: CatalogLoadError.revisionRejected(
        received: changedCatalog.revision,
        policy: .cached(
          revision: acceptedCatalog.revision,
          payloadSHA256: acceptedDigest
        )
      )
    ) {
      try SignedCatalogLoader.load(
        envelopeData: encodeEnvelope(changedEnvelope),
        trustedKeys: keys,
        currentClientVersion: "0.2.0",
        acceptedChannels: [.testing],
        revisionPolicy: .cached(
          revision: acceptedCatalog.revision,
          payloadSHA256: acceptedDigest
        ),
        now: CatalogTestFixtures.now
      )
    }
  }

  @Test
  func testingKeyCannotSignStableCatalog() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let catalog = CatalogTestFixtures.catalog(channel: .stable, runtimes: [], profiles: [])
    let payload = try encode(catalog)
    let envelope = SignedCatalogEnvelope(
      keyID: "testing-only",
      payload: payload.base64EncodedString(),
      signature: try privateKey.signature(for: payload).base64EncodedString()
    )

    #expect(
      throws: CatalogLoadError.signingKeyNotAuthorized(keyID: "testing-only", channel: .stable)
    ) {
      try SignedCatalogLoader.load(
        envelopeData: encodeEnvelope(envelope),
        trustedKeys: [
          "testing-only": .init(
            publicKey: privateKey.publicKey.rawRepresentation,
            allowedChannels: [.testing]
          )
        ],
        currentClientVersion: "0.1.0",
        acceptedChannels: [.stable],
        revisionPolicy: .newerThan(9),
        now: CatalogTestFixtures.now
      )
    }
  }

  @Test
  func preservesValidityDiagnosticsAndRejectsNonCanonicalClientVersion() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let expiresAt = Date(timeIntervalSince1970: 1_750_000_000)
    let catalog = CatalogTestFixtures.catalog(
      expiresAt: expiresAt,
      runtimes: [],
      profiles: []
    )
    let payload = try encode(catalog)
    let envelope = SignedCatalogEnvelope(
      keyID: "test-key",
      payload: payload.base64EncodedString(),
      signature: try privateKey.signature(for: payload).base64EncodedString()
    )
    let envelopeData = encodeEnvelope(envelope)
    let keys = [
      "test-key": CatalogTrustedKey(
        publicKey: privateKey.publicKey.rawRepresentation,
        allowedChannels: [.testing]
      )
    ]

    #expect(
      throws: CatalogLoadError.invalidCatalog([
        .init(code: "expired-catalog", path: "expiresAt", message: "Catalog has expired.")
      ])
    ) {
      try SignedCatalogLoader.load(
        envelopeData: envelopeData,
        trustedKeys: keys,
        currentClientVersion: "0.1.0",
        acceptedChannels: [.testing],
        revisionPolicy: .newerThan(9),
        now: CatalogTestFixtures.now
      )
    }

    let validCatalog = CatalogTestFixtures.catalog(runtimes: [], profiles: [])
    let validPayload = try encode(validCatalog)
    let validEnvelope = SignedCatalogEnvelope(
      keyID: "test-key",
      payload: validPayload.base64EncodedString(),
      signature: try privateKey.signature(for: validPayload).base64EncodedString()
    )
    #expect(throws: CatalogLoadError.invalidClientVersion("00.1.0")) {
      try SignedCatalogLoader.load(
        envelopeData: encodeEnvelope(validEnvelope),
        trustedKeys: keys,
        currentClientVersion: "00.1.0",
        acceptedChannels: [.testing],
        revisionPolicy: .newerThan(9),
        now: CatalogTestFixtures.now
      )
    }
  }

  @Test
  func unsignedLoaderRequiresDevelopmentChannel() throws {
    let catalog = CatalogTestFixtures.catalog(channel: .stable, runtimes: [], profiles: [])

    #expect(throws: CatalogLoadError.unsignedCatalogRequiresDevelopmentChannel) {
      try SignedCatalogLoader.loadUnsignedDevelopmentCatalog(
        try encode(catalog),
        now: CatalogTestFixtures.now
      )
    }
  }

  private func encode(_ catalog: CompatibilityCatalog) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(catalog)
  }

  private func encodeEnvelope(_ envelope: SignedCatalogEnvelope) -> Data {
    try! JSONEncoder().encode(envelope)
  }
}
