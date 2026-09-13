import Foundation

enum ManifestSemanticPathKind: Sendable {
  case file
  case directory
}

enum ManifestSemanticValidation {
  static func normalizeArchivePath(
    _ raw: String,
    kind: ManifestSemanticPathKind
  ) throws -> String {
    guard !raw.isEmpty, raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.hasPrefix("/"), !raw.hasPrefix("~"), !raw.contains("\\"), !raw.contains(":"),
      !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      throw ManifestAdapterError.invalidManifest
    }
    var path = raw
    if path.hasSuffix("/") {
      guard kind == .directory else { throw ManifestAdapterError.invalidManifest }
      path.removeLast()
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.isEmpty, components.count <= 32 else {
      throw ManifestAdapterError.invalidManifest
    }
    var normalizedComponents: [String] = []
    normalizedComponents.reserveCapacity(components.count)
    for rawComponent in components {
      let component = String(rawComponent)
      let normalized = component.precomposedStringWithCanonicalMapping
      guard !component.isEmpty, component != ".", component != "..",
        component == component.trimmingCharacters(in: .whitespacesAndNewlines),
        !component.hasSuffix("."), normalized.utf8.count <= 255
      else {
        throw ManifestAdapterError.invalidManifest
      }
      normalizedComponents.append(normalized)
    }
    let normalizedPath = normalizedComponents.joined(separator: "/")
    guard normalizedPath.utf8.count <= 1_024 else {
      throw ManifestAdapterError.invalidManifest
    }
    return normalizedPath
  }

  static func canonicalPath(_ path: String) -> String {
    path.precomposedStringWithCanonicalMapping.folding(
      options: [.caseInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }

  static func isOpaque(_ value: String, maximumBytes: Int) -> Bool {
    !value.isEmpty && value.utf8.count <= maximumBytes
      && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.utf8.elementsEqual(value.precomposedStringWithCanonicalMapping.utf8)
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }

  static func normalizedMD5(_ value: String) -> String? {
    guard value.utf8.count == 32,
      value.utf8.allSatisfy({
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      })
    else { return nil }
    return value.lowercased()
  }

  static func checkedAdd(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
    let (result, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw ManifestAdapterError.invalidManifest }
    return result
  }

  static func utf8Less(_ left: String, _ right: String) -> Bool {
    left.utf8.lexicographicallyPrecedes(right.utf8)
  }
}
