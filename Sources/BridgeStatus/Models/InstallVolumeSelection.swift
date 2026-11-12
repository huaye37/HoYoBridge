import Darwin
import Foundation

enum InstallVolumeProbeError: Error, Equatable, Sendable {
  case invalidLocation
  case unavailable
  case arithmeticOverflow
}

struct InstallVolumeSelection: Equatable, Sendable {
  let url: URL
  let volumeName: String
  let freeDiskBytes: UInt64
  let isDefaultPreview: Bool
  var fileSystemName: String = "未知"
  var isNetwork: Bool = false
  var isWritable: Bool = true
  var supportsCloning: Bool = false

  var storageAdvice: String {
    if !isWritable { return "此位置不可写，请检查磁盘权限或连接。" }
    if isNetwork {
      return "网络磁盘的加载速度取决于网络和存储性能，连接波动可能导致加载变慢或卡顿；断连会中断游戏。此旧迁移和更新流程的更新前 APFS 克隆备份不支持网络盘。"
    }
    if !supportsCloning {
      return "此卷不支持 APFS 克隆备份；可以存放游戏，更新和回滚前需要迁到可写的 APFS 磁盘。"
    }
    return "支持安装、迁移和 APFS 更新备份。外置硬盘在运行和更新期间需要保持连接。"
  }

  var directoryName: String {
    let name = url.lastPathComponent
    return name.isEmpty ? volumeName : name
  }
}

enum InstallVolumeProbe {
  static func inspect(_ url: URL, isDefaultPreview: Bool) throws -> InstallVolumeSelection {
    guard url.isFileURL, url.path.hasPrefix("/") else {
      throw InstallVolumeProbeError.invalidLocation
    }

    let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      throw InstallVolumeProbeError.unavailable
    }
    defer { _ = close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else {
      throw InstallVolumeProbeError.invalidLocation
    }

    var fileSystem = statfs()
    guard fstatfs(descriptor, &fileSystem) == 0 else {
      throw InstallVolumeProbeError.unavailable
    }

    let (freeDiskBytes, overflow) = UInt64(fileSystem.f_bavail)
      .multipliedReportingOverflow(by: UInt64(fileSystem.f_bsize))
    guard !overflow else {
      throw InstallVolumeProbeError.arithmeticOverflow
    }

    let values = try? url.resourceValues(forKeys: [
      .volumeNameKey, .volumeSupportsFileCloningKey, .volumeURLKey,
    ])
    if url.standardizedFileURL.path.hasPrefix("/Volumes/") {
      let components = url.standardizedFileURL.pathComponents
      guard components.count >= 3,
        values?.volume?.standardizedFileURL.path == "/Volumes/" + components[2]
      else { throw InstallVolumeProbeError.unavailable }
    }
    let volumeName = values?.volumeName ?? "存储卷"
    let fileSystemName = withUnsafeBytes(of: fileSystem.f_fstypename) { bytes in
      String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    return InstallVolumeSelection(
      url: url,
      volumeName: volumeName,
      freeDiskBytes: freeDiskBytes,
      isDefaultPreview: isDefaultPreview,
      fileSystemName: fileSystemName,
      isNetwork: fileSystem.f_flags & UInt32(MNT_LOCAL) == 0,
      isWritable: fileSystem.f_flags & UInt32(MNT_RDONLY) == 0
        && FileManager.default.isWritableFile(atPath: url.path),
      supportsCloning: values?.volumeSupportsFileCloning == true
    )
  }
}
