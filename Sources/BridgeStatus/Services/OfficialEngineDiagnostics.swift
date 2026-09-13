import Foundation
import OSLog
import Darwin

@MainActor
final class OfficialEngineDiagnostics {
  private let logger = Logger(subsystem: "cn.yeutech.MacGameBridge", category: "OfficialEngine")
  let url = GameRuntimePaths.userStorageRoot.appending(path: "Diagnostics/official-engine.log")
  private var entries: [String] = []

  init() {
    if let saved = try? String(contentsOf: url, encoding: .utf8) {
      entries = Array(saved.split(separator: "\n").suffix(128).map(String.init))
    }
  }

  /// Callers supply fixed event identifiers and numeric results, never raw engine payloads.
  func record(_ event: String, code: Int32 = 0) {
    logger.notice("event=\(event, privacy: .public) code=\(code, privacy: .public)")
    entries.append("\(ISO8601DateFormatter().string(from: Date())) \(event) code=\(code)")
    if entries.count > 128 { entries.removeFirst(entries.count - 128) }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(entries.joined(separator: "\n").utf8).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch { logger.error("diagnostic_file_write_failed") }
  }

  static func portIsOccupied(_ port: UInt16) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return true }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    return withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
      }
    }
  }
}
