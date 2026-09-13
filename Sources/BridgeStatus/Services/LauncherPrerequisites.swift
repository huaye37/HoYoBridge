import Foundation

enum LauncherPrerequisites {
  static func issue() -> String? {
    #if !arch(arm64)
    return "此版本面向 Apple Silicon Mac，请使用受支持的设备。"
    #else
    guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
      return "需要 macOS 26 或更新系统，请先升级 macOS。"
    }
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
    probe.arguments = ["-x86_64", "/usr/bin/true"]
    probe.standardOutput = FileHandle.nullDevice
    probe.standardError = FileHandle.nullDevice
    do {
      try probe.run()
      probe.waitUntilExit()
      guard probe.terminationStatus == 0 else {
        return "尚未安装 Rosetta，游戏运行环境无法启动。请按 Apple 指引安装 Rosetta 后重新打开应用。"
      }
    } catch {
      return "无法检测 Rosetta，请按 Apple 指引检查安装后重试。"
    }
    return nil
    #endif
  }
}
