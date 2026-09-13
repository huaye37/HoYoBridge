import CoreGraphics
import Foundation

enum LauncherPreferenceKeys {
  static let windowMode = "launcher.windowMode"
  static let resolution = "launcher.resolution"
  static let graphicsProfile = "launcher.graphicsProfile"
  static let textLanguage = "launcher.textLanguage"
  static let voiceLanguage = "launcher.voiceLanguage"
  static let hideAfterLaunch = "launcher.hideAfterLaunch"
  static let graphicsBackend = "launcher.graphicsBackend"
  static let fpsUnlockMode = "launcher.experimental.fpsUnlockMode"
  static let detailedWineLoggingEnabled = "launcher.experimental.detailedWineLoggingEnabled"
  static let metalHUDEnabled = "launcher.experimental.metalHUDEnabled"
  static let automaticDXMTFallbackEnabled = "launcher.experimental.automaticDXMTFallbackEnabled"
}

enum GameGraphicsBackend: String, CaseIterable, Identifiable, Sendable {
  case dxmt
  case gptk4

  var id: Self { self }

  var title: String {
    switch self {
    case .dxmt: "DXMT 0.80（已验证）"
    case .gptk4: "GPTK 4 / D3DMetal（实验）"
    }
  }
}

enum GameFPSUnlockMode: String, CaseIterable, Identifiable, Sendable {
  case disabled
  case fps120

  var id: Self { self }

  var title: String {
    switch self {
    case .disabled: "关闭（60 FPS）"
    case .fps120: "120 FPS（实验）"
    }
  }

  var targetFPS: Int? {
    switch self {
    case .disabled: nil
    case .fps120: 120
    }
  }
}

enum GameGraphicsProfile: String, CaseIterable, Identifiable, Sendable {
  case balanced
  case preserve

  var id: Self { self }

  var title: String {
    switch self {
    case .balanced: "平衡性能（推荐）"
    case .preserve: "保留游戏设置"
    }
  }
}

enum GameWindowMode: String, CaseIterable, Identifiable, Sendable {
  case windowed
  case fullScreen

  var id: Self { self }

  var title: String {
    switch self {
    case .windowed: "窗口模式"
    case .fullScreen: "全屏模式"
    }
  }
}

struct GameResolution: RawRepresentable, Hashable, Identifiable, Sendable {
  let rawValue: String
  let width: Int
  let height: Int

  var id: String { rawValue }
  var title: String { "\(width) × \(height)" }

  init?(rawValue: String) {
    let parts = rawValue.lowercased().split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2,
      let width = Int(parts[0]),
      let height = Int(parts[1]),
      (320...16_384).contains(width),
      (200...16_384).contains(height)
    else { return nil }
    self.rawValue = "\(width)x\(height)"
    self.width = width
    self.height = height
  }

  init(width: Int, height: Int) {
    self.rawValue = "\(width)x\(height)"
    self.width = width
    self.height = height
  }

  static let compact = Self(width: 1280, height: 720)
  static let balanced = Self(width: 1600, height: 900)
  static let large = Self(width: 1920, height: 1080)
  static let native = Self(width: 2560, height: 1440)
}

struct GameResolutionOption: Identifiable, Sendable {
  let resolution: GameResolution
  let isCurrentDesktop: Bool
  let isNativePixels: Bool
  let isCommon: Bool

  var id: String { resolution.id }

  var title: String {
    var details = [aspectRatio]
    if isCommon { details.insert("常用", at: 0) }
    if isCurrentDesktop { details.insert("当前桌面", at: 0) }
    if isNativePixels { details.insert("原生像素", at: 0) }
    return "\(resolution.title)  ·  \(details.joined(separator: " · "))"
  }

  private var aspectRatio: String {
    let divisor = greatestCommonDivisor(resolution.width, resolution.height)
    return "\(resolution.width / divisor):\(resolution.height / divisor)"
  }

  private func greatestCommonDivisor(_ left: Int, _ right: Int) -> Int {
    var a = left
    var b = right
    while b != 0 {
      (a, b) = (b, a % b)
    }
    return max(a, 1)
  }
}

enum GameResolutionCatalog {
  static var available: [GameResolutionOption] {
    var resolutions = Set(commonResolutions)
    var currentDesktop = Set<GameResolution>()
    var nativePixels = Set<GameResolution>()
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
      return options(
        resolutions: resolutions,
        currentDesktop: currentDesktop,
        nativePixels: nativePixels
      )
    }

    var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    guard
      CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success
    else {
      return options(
        resolutions: resolutions,
        currentDesktop: currentDesktop,
        nativePixels: nativePixels
      )
    }

    let modeOptions = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    for display in displays.prefix(Int(displayCount)) {
      if let mode = CGDisplayCopyDisplayMode(display) {
        let logical = GameResolution(width: mode.width, height: mode.height)
        let pixels = GameResolution(width: mode.pixelWidth, height: mode.pixelHeight)
        resolutions.formUnion([logical, pixels])
        currentDesktop.insert(logical)
        nativePixels.insert(pixels)
      }
      for mode in CGDisplayCopyAllDisplayModes(display, modeOptions) as? [CGDisplayMode] ?? [] {
        insertUsable(mode.width, mode.height, into: &resolutions)
        insertUsable(mode.pixelWidth, mode.pixelHeight, into: &resolutions)
      }
    }
    return options(
      resolutions: resolutions,
      currentDesktop: currentDesktop,
      nativePixels: nativePixels
    )
  }

  static func options(
    resolutions: Set<GameResolution>,
    currentDesktop: Set<GameResolution>,
    nativePixels: Set<GameResolution>
  ) -> [GameResolutionOption] {
    resolutions.map {
      GameResolutionOption(
        resolution: $0,
        isCurrentDesktop: currentDesktop.contains($0),
        isNativePixels: nativePixels.contains($0),
        isCommon: commonResolutionSet.contains($0)
      )
    }.sorted { left, right in
      if left.isCurrentDesktop != right.isCurrentDesktop { return left.isCurrentDesktop }
      if left.isNativePixels != right.isNativePixels { return left.isNativePixels }
      if left.isCommon != right.isCommon { return left.isCommon }
      let leftArea = left.resolution.width * left.resolution.height
      let rightArea = right.resolution.width * right.resolution.height
      if leftArea != rightArea { return leftArea < rightArea }
      return left.resolution.width < right.resolution.width
    }
  }

  private static func insertUsable(
    _ width: Int,
    _ height: Int,
    into resolutions: inout Set<GameResolution>
  ) {
    guard min(width, height) >= 600, max(width, height) <= 7680 else { return }
    resolutions.insert(GameResolution(width: width, height: height))
  }

  private static let commonResolutions: [GameResolution] = [
    GameResolution(width: 1024, height: 576),
    GameResolution(width: 1152, height: 648),
    .compact,
    GameResolution(width: 1366, height: 768),
    GameResolution(width: 1440, height: 810),
    .balanced,
    GameResolution(width: 1680, height: 945),
    .large,
    GameResolution(width: 2048, height: 1152),
    .native,
    GameResolution(width: 2880, height: 1620),
    GameResolution(width: 3200, height: 1800),
    GameResolution(width: 3840, height: 2160),
    GameResolution(width: 5120, height: 2880),
  ]

  private static let commonResolutionSet = Set(commonResolutions)
}

enum GameTextLanguage: String, CaseIterable, Identifiable, Sendable {
  case simplifiedChinese = "zh-CN"
  case english = "en-US"

  var id: Self { self }

  var title: String {
    switch self {
    case .simplifiedChinese: "简体中文"
    case .english: "English"
    }
  }

  var gameValue: Int {
    switch self {
    case .simplifiedChinese: 2
    case .english: 1
    }
  }
}

enum GameVoiceLanguage: String, CaseIterable, Identifiable, Sendable {
  case simplifiedChinese = "zh-CN"
  case english = "en-US"
  case japanese = "ja-JP"
  case korean = "ko-KR"

  var id: Self { self }

  var title: String {
    switch self {
    case .simplifiedChinese: "汉语"
    case .english: "英语"
    case .japanese: "日语"
    case .korean: "韩语"
    }
  }

  var gameValue: Int {
    switch self {
    case .simplifiedChinese: 0
    case .english: 1
    case .japanese: 2
    case .korean: 3
    }
  }
}

struct GameLaunchPreferences: Equatable, Sendable {
  let graphicsBackend: GameGraphicsBackend
  let windowMode: GameWindowMode
  let resolution: GameResolution
  let graphicsProfile: GameGraphicsProfile
  let textLanguage: GameTextLanguage
  let voiceLanguage: GameVoiceLanguage
  let hideAfterLaunch: Bool
  let fpsUnlockMode: GameFPSUnlockMode
  let detailedWineLoggingEnabled: Bool
  let metalHUDEnabled: Bool
  let automaticDXMTFallbackEnabled: Bool

  static func load(defaults: UserDefaults = .standard) -> Self {
    Self(
      graphicsBackend: .dxmt,
      windowMode: GameWindowMode(
        rawValue: defaults.string(forKey: LauncherPreferenceKeys.windowMode) ?? "") ?? .windowed,
      resolution: GameResolution(
        rawValue: defaults.string(forKey: LauncherPreferenceKeys.resolution) ?? "") ?? .balanced,
      graphicsProfile: GameGraphicsProfile(
        rawValue: defaults.string(forKey: LauncherPreferenceKeys.graphicsProfile) ?? "")
        ?? .balanced,
      textLanguage: GameTextLanguage(
        rawValue: defaults.string(forKey: LauncherPreferenceKeys.textLanguage) ?? "")
        ?? .simplifiedChinese,
      voiceLanguage: GameVoiceLanguage(
        rawValue: defaults.string(forKey: LauncherPreferenceKeys.voiceLanguage) ?? "")
        ?? .simplifiedChinese,
      hideAfterLaunch: defaults.object(forKey: LauncherPreferenceKeys.hideAfterLaunch) as? Bool
        ?? true,
      fpsUnlockMode: GameFPSUnlockMode(
        rawValue: defaults.string(forKey: LauncherPreferenceKeys.fpsUnlockMode) ?? "") ?? .disabled,
      detailedWineLoggingEnabled: false,
      metalHUDEnabled: defaults.bool(forKey: LauncherPreferenceKeys.metalHUDEnabled),
      automaticDXMTFallbackEnabled: true
    )
  }

  static let recommended = Self(
    graphicsBackend: .dxmt,
    windowMode: .windowed,
    resolution: .balanced,
    graphicsProfile: .balanced,
    textLanguage: .simplifiedChinese,
    voiceLanguage: .simplifiedChinese,
    hideAfterLaunch: true,
    fpsUnlockMode: .disabled,
    detailedWineLoggingEnabled: false,
    metalHUDEnabled: false,
    automaticDXMTFallbackEnabled: true
  )

  func usingGraphicsBackend(_ backend: GameGraphicsBackend) -> Self {
    Self(
      graphicsBackend: backend,
      windowMode: windowMode,
      resolution: resolution,
      graphicsProfile: graphicsProfile,
      textLanguage: textLanguage,
      voiceLanguage: voiceLanguage,
      hideAfterLaunch: hideAfterLaunch,
      fpsUnlockMode: fpsUnlockMode,
      detailedWineLoggingEnabled: detailedWineLoggingEnabled,
      metalHUDEnabled: metalHUDEnabled,
      automaticDXMTFallbackEnabled: automaticDXMTFallbackEnabled
    )
  }
}
