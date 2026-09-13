import Darwin
import Foundation

enum GameDownloadLockError: LocalizedError {
  case busy
  case unavailable

  var errorDescription: String? {
    switch self {
    case .busy: "后台下载尚未结束，暂不能启动、更新或回滚。请稍后重新检查；不要移动正在写入的目录。"
    case .unavailable: "无法锁定安装目录，请检查磁盘连接和写入权限。"
    }
  }
}

/// Shares the downloader's flock. Passing this handle as stdin keeps the same lock
/// alive in the child even if the launcher exits; it is not a stale PID file.
final class GameDownloadLock: Sendable {
  let handle: FileHandle

  init(game: URL) throws {
    let url = Self.url(for: game)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw GameDownloadLockError.unavailable }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let busy = errno == EWOULDBLOCK
      close(descriptor)
      throw busy ? GameDownloadLockError.busy : .unavailable
    }
    handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }

  static func isBusy(game: URL) -> Bool {
    let descriptor = open(url(for: game).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { return errno != ENOENT }
    defer { close(descriptor) }
    return flock(descriptor, LOCK_EX | LOCK_NB) != 0
  }

  private static func url(for game: URL) -> URL {
    game.deletingLastPathComponent()
      .appending(path: ".MacGameBridge-Genshin-CN-download-cache/.download.lock")
  }
}
