import CryptoKit
import Darwin
import Foundation

struct GameMigrationProgress: Equatable, Sendable {
  let completedBytes: UInt64
  let totalBytes: UInt64
  let phase: String

  var fraction: Double { totalBytes == 0 ? 0 : Double(completedBytes) / Double(totalBytes) }
}

enum GameStorageError: LocalizedError {
  case invalidGame, destinationExists, nestedDestination, unsupportedFile, insufficientSpace
  case readOnly, changedDuringCopy, verificationFailed, publishFailed

  var errorDescription: String? {
    switch self {
    case .invalidGame: "请选择包含 YuanShen.exe 和 YuanShen_Data 的国服游戏目录。"
    case .destinationExists: "目标已有同名目录，未覆盖任何文件。请选择其他位置，或使用“定位已有游戏”。"
    case .nestedDestination: "目标不能是原游戏目录，也不能位于原游戏目录内部。"
    case .unsupportedFile: "目录包含符号链接或特殊文件，未迁移。请先检查游戏目录。"
    case .insufficientSpace: "目标磁盘空间不足，需要容纳一份完整游戏并预留 1 GiB。"
    case .readOnly: "目标目录不可写，请检查磁盘权限或网络盘连接。"
    case .changedDuringCopy: "复制期间原游戏文件发生变化，未切换位置。请关闭游戏和其他更新程序后重试。"
    case .verificationFailed: "新副本校验失败，未切换位置，原游戏保持不变。"
    case .publishFailed: "无法发布新目录，未切换位置。请检查目标磁盘是否仍连接。"
    }
  }
}

enum GameStorageManager {
  private struct Entry: Equatable {
    let path: String
    let directory: Bool
    let size: UInt64
    let modified: Date?
  }

  static func recognize(_ url: URL) throws -> URL {
    guard url.isFileURL else { throw GameStorageError.invalidGame }
    let root = url.standardizedFileURL
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw GameStorageError.invalidGame
    }
    let executable = try root.appending(path: "YuanShen.exe")
      .resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    let data = try root.appending(path: "YuanShen_Data")
      .resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard executable.isRegularFile == true, executable.isSymbolicLink != true,
      data.isDirectory == true, data.isSymbolicLink != true
    else { throw GameStorageError.invalidGame }
    return root.resolvingSymlinksInPath()
  }

  static func migrate(
    source: URL, to container: URL,
    progress: @Sendable (GameMigrationProgress) async -> Void = { _ in }
  ) async throws -> URL {
    try Task.checkCancellation()
    let source = try recognize(source)
    let volume = try InstallVolumeProbe.inspect(container, isDefaultPreview: false)
    guard volume.isWritable else { throw GameStorageError.readOnly }
    let container = container.resolvingSymlinksInPath().standardizedFileURL
    let destination = container.appending(
      path: source.lastPathComponent, directoryHint: .isDirectory)
    guard destination.path != source.path, !destination.path.hasPrefix(source.path + "/") else {
      throw GameStorageError.nestedDestination
    }
    guard !exists(destination) else { throw GameStorageError.destinationExists }
    await progress(.init(completedBytes: 0, totalBytes: 0, phase: "正在统计游戏文件"))
    let entries = try inventory(source)
    let total = try entries.reduce(UInt64(0)) { result, entry in
      let (sum, overflow) = result.addingReportingOverflow(entry.size)
      guard !overflow else { throw GameStorageError.insufficientSpace }
      return sum
    }
    guard volume.freeDiskBytes > total,
      volume.freeDiskBytes - total >= 1_073_741_824
    else { throw GameStorageError.insufficientSpace }

    let staging = container.appending(path: ".mgb-migration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    // Only this operation's private staging directory is ever removed; the source is untouched.
    defer { try? FileManager.default.removeItem(at: staging) }
    var copied: UInt64 = 0
    var lastReport = Date.distantPast
    for entry in entries {
      try Task.checkCancellation()
      let input = source.appending(path: entry.path)
      let output = staging.appending(path: entry.path)
      if entry.directory {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        continue
      }
      let descriptor = open(input.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor >= 0 else { throw GameStorageError.changedDuringCopy }
      let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
        try? reader.close()
        throw GameStorageError.readOnly
      }
      let writer = try FileHandle(forWritingTo: output)
      do {
        var digest = SHA256()
        var fileBytes: UInt64 = 0
        while let buffer = try reader.read(upToCount: 4 * 1024 * 1024), !buffer.isEmpty {
          try Task.checkCancellation()
          try writer.write(contentsOf: buffer)
          digest.update(data: buffer)
          fileBytes += UInt64(buffer.count)
          copied += UInt64(buffer.count)
          if Date().timeIntervalSince(lastReport) >= 0.25 {
            await progress(.init(completedBytes: copied, totalBytes: total, phase: "正在复制游戏"))
            lastReport = Date()
          }
        }
        try writer.synchronize()
        try writer.close()
        try reader.close()
        guard fileBytes == entry.size else { throw GameStorageError.changedDuringCopy }
        await progress(.init(completedBytes: copied, totalBytes: total, phase: "正在校验新副本"))
        guard try hash(output) == digest.finalize() else {
          throw GameStorageError.verificationFailed
        }
      } catch {
        try? reader.close()
        try? writer.close()
        throw error
      }
    }
    guard try inventory(source) == entries else { throw GameStorageError.changedDuringCopy }
    _ = try recognize(staging)
    try Task.checkCancellation()
    // Exclusive rename prevents a concurrently created destination from being overwritten.
    guard renamex_np(staging.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
      if exists(destination) { throw GameStorageError.destinationExists }
      throw GameStorageError.publishFailed
    }
    return destination
  }

  // Called only after a successful safety backup, when the user requests repair/update.
  static func prepareManagedMarker(at game: URL) throws {
    let marker = game.appending(path: ".mgb-managed-cn-download")
    if exists(marker) {
      let values = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw GameStorageError.unsupportedFile
      }
      return
    }
    _ = try recognize(game)
    try Data("schema=1\nstate=imported\n".utf8).write(to: marker, options: .withoutOverwriting)
  }

  private static func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }

  private static func inventory(_ root: URL) throws -> [Entry] {
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
      .contentModificationDateKey,
    ]
    var entries: [Entry] = []
    func visit(_ directory: URL, relative: String) throws {
      for url in try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: Array(keys)
      ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: keys)
        guard values.isSymbolicLink != true,
          values.isDirectory == true || values.isRegularFile == true
        else { throw GameStorageError.unsupportedFile }
        let path = relative + url.lastPathComponent
        let directory = values.isDirectory == true
        entries.append(
          Entry(
            path: path, directory: directory, size: directory ? 0 : UInt64(values.fileSize ?? 0),
            modified: values.contentModificationDate))
        if directory { try visit(url, relative: path + "/") }
      }
    }
    try visit(root, relative: "")
    return entries
  }

  private static func hash(_ url: URL) throws -> SHA256.Digest {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while let buffer = try handle.read(upToCount: 4 * 1024 * 1024), !buffer.isEmpty {
      try Task.checkCancellation()
      digest.update(data: buffer)
    }
    return digest.finalize()
  }
}
