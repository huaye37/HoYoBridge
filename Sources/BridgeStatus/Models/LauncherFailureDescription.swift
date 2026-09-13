import Foundation

enum LauncherFailureDescription {
  static func describe(_ error: Error) -> String {
    if let runtime = error as? RuntimeAssetInstallerError {
      return runtime.errorDescription ?? "运行环境准备失败。"
    }
    if let importError = error as? GPTKPackageImportError {
      return switch importError {
      case .invalidPackage, .nestedImageMissing:
        "所选 DMG 不包含预期的 GPTK 组件，请选择 Apple 官方安装包。"
      case .mountFailed: "无法挂载 GPTK 安装包，请重新下载后重试。"
      case .unsupportedVersion: "此 GPTK 版本尚不受当前启动器支持，未切换运行环境。"
      case .signatureRejected: "GPTK 的 Apple 签名校验未通过，未启用此组件。"
      case .unsafeDestination: "GPTK 目标目录不符合安全条件，未覆盖原文件。"
      case .commandFailed: "GPTK 导入步骤执行失败，请检查安装包和可用空间。"
      }
    }
    if let preparation = error as? GPTKRuntimePreparationError {
      return switch preparation {
      case .invalidBaseRuntime: "基础 Wine 运行环境不完整，请重新准备默认组合。"
      case .invalidGPTKRuntime: "GPTK 组件不完整，请重新导入，或改用默认 DXMT 组合。"
      case .compatibilityShimMissing, .compatibilityShimInvalid:
        "启动兼容组件缺失或校验失败，请重新下载完整启动器。"
      case .unsupportedVersionModule: "游戏的 version.dll 与当前兼容配置不匹配，未覆盖原文件。"
      case .copyFailed: "创建独立 GPTK 环境失败，请检查磁盘空间和目录权限。"
      case .unsafeDestination: "GPTK 环境目录不符合安全条件，未覆盖原文件。"
      }
    }
    if let configuration = error as? GenshinPrefixConfigurationError {
      return switch configuration {
      case .invalidRegistry: "游戏配置格式异常，无法应用启动设置，请检查游戏文件。"
      case .commandFailed: "Wine 启动配置写入失败，请检查独立运行目录的权限和启动日志。"
      }
    }
    let systemError = error as NSError
    if systemError.domain == NSCocoaErrorDomain {
      switch systemError.code {
      case NSFileWriteOutOfSpaceError: return "磁盘空间不足，请释放空间或更换安装位置后重试。"
      case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
        return "无法访问所需文件，请检查安装目录权限。"
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
        return "缺少所需文件，请检查游戏文件或重新下载完整启动器。"
      default: break
      }
    }
    // Only expose domain/code, never arbitrary paths, command arguments, or credentials.
    return "操作未完成（\(systemError.domain) / \(systemError.code)），请检查磁盘空间、组件完整性和诊断日志。"
  }
}
