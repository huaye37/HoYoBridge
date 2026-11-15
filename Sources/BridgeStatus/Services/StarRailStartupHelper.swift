import AppKit
import CryptoKit
import Darwin
import Foundation

enum StarRailStartupHelper {
  private static let label = "cn.yeutech.HoYoBridge.StartupHelper"
  private static let installedPath = "/Library/PrivilegedHelperTools/" + label
  private static let plistPath = "/Library/LaunchDaemons/" + label + ".plist"
  private static let socketPath = "/var/run/" + label + ".sock"

  @MainActor
  static func activate() async throws {
    guard let source = Bundle.main.resourceURL?.appending(path: "RuntimeAssets/hoyobridge-startup-helper"),
      FileManager.default.isExecutableFile(atPath: source.path) else {
      throw issue("启动辅助程序缺失，请更新启动器后重试。")
    }
    if !installationMatches(source) { try await install(source) }
    try await Task.detached(priority: .userInitiated) { try requestActivation() }.value
  }

  private static func installationMatches(_ source: URL) -> Bool {
    let manager = FileManager.default
    guard let attributes = try? manager.attributesOfItem(atPath: installedPath),
      attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
      let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue, mode & 0o022 == 0,
      let plistAttributes = try? manager.attributesOfItem(atPath: plistPath),
      plistAttributes[.type] as? FileAttributeType == .typeRegular,
      (plistAttributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
      let plistMode = (plistAttributes[.posixPermissions] as? NSNumber)?.intValue, plistMode & 0o022 == 0,
      let bytes = try? Data(contentsOf: URL(fileURLWithPath: installedPath)),
      let expected = try? Data(contentsOf: source),
      SHA256.hash(data: bytes) == SHA256.hash(data: expected),
      let plistBytes = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
      let configuration = try? PropertyListSerialization.propertyList(from: plistBytes, format: nil) as? [String: Any],
      configuration["ProgramArguments"] as? [String] == [installedPath, String(getuid())] else { return false }
    return true
  }

  @MainActor
  private static func install(_ source: URL) async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: "hoyobridge-helper-\(UUID().uuidString).plist")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let config: [String: Any] = ["Label": label, "ProgramArguments": [installedPath, String(getuid())],
      "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "ThrottleInterval": 5,
      "Sockets": ["Requests": ["SockPathName": socketPath, "SockPathMode": 0o666, "SockType": "stream"]]]
    try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0).write(to: temporary, options: .atomic)
    let command = "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true; "
      + "/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools && "
      + "/usr/bin/install -o root -g wheel -m 755 \(quote(source.path)) \(quote(installedPath)) && "
      + "/usr/bin/install -o root -g wheel -m 644 \(quote(temporary.path)) \(quote(plistPath)) && "
      + "/bin/launchctl bootstrap system \(quote(plistPath))"
    let encoded = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let status = try await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", "do shell script \"\(encoded)\" with administrator privileges"]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    }.value
    guard status == 0, installationMatches(source) else {
      throw issue("首次启动需要安装专用辅助程序。请允许一次管理员授权后重试。")
    }
  }

  private static func requestActivation() throws {
    // launchd may return from bootstrap before its socket has appeared.
    for _ in 0..<30 {
      if FileManager.default.fileExists(atPath: socketPath) { break }
      Thread.sleep(forTimeInterval: 0.1)
    }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw issue("无法连接启动辅助程序。") }
    defer { close(descriptor) }
    var timeout = timeval(tv_sec: 8, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8) + [0]
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { throw issue("启动辅助程序未能连接，请重试；若持续出现，请重新安装辅助程序。") }
    var noSignal: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
    let sent = "START\n".withCString { Darwin.write(descriptor, $0, 6) }
    guard sent == 6 else { throw issue("启动辅助程序未响应。") }
    var reply = [UInt8](repeating: 0, count: 6)
    var count = 0
    while count < reply.count {
      let received = reply.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!.advanced(by: count), 6-count) }
      guard received > 0 else { throw issue("启动辅助程序未确认完成，请稍后重试。") }
      count += received
    }
    guard String(bytes: reply, encoding: .utf8) == "READY\n" else {
      throw issue("启动辅助程序未能建立兼容窗口，系统已有配置保持原样。")
    }
  }

  private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
  private static func issue(_ message: String) -> NSError {
    NSError(domain: "HoYoBridge.StartupHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
