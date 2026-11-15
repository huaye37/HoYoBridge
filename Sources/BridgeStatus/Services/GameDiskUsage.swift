import Foundation

struct GameDiskUsage: Equatable, Sendable {
  let bytes: UInt64
  let approximate: Bool

  static func measure(_ directory: URL) throws -> Self? {
    try Task.checkCancellation()
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
    let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey,
      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
    var incomplete = false
    guard let entries = manager.enumerator(at: directory, includingPropertiesForKeys: keys,
      options: [], errorHandler: { _, _ in incomplete = true; return true }) else { return nil }
    var total: UInt64 = 0
    for case let file as URL in entries {
      try Task.checkCancellation()
      do {
        let values = try file.resourceValues(forKeys: Set(keys))
        // Never follow links into another client or volume.
        if values.isSymbolicLink == true { entries.skipDescendants(); continue }
        guard values.isRegularFile == true else { continue }
        let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        if values.totalFileAllocatedSize == nil && values.fileAllocatedSize == nil { incomplete = true }
        let (sum, overflow) = total.addingReportingOverflow(UInt64(max(0, size)))
        guard !overflow else { return Self(bytes: total, approximate: true) }
        total = sum
      } catch { incomplete = true }
    }
    return Self(bytes: total, approximate: incomplete)
  }
}
