import Darwin
import Foundation

enum GenshinPrefixConfigurationError: Error, Equatable {
  case invalidRegistry
  case commandFailed(String)
}

enum GenshinGeneralDataEditor {
  static let valueName = "GENERAL_DATA_h2389025596"

  static func updatedBinaryHex(
    userRegistryText: String,
    textLanguage: GameTextLanguage,
    voiceLanguage: GameVoiceLanguage,
    graphicsProfile: GameGraphicsProfile
  ) throws -> String? {
    guard let marker = userRegistryText.range(of: "\"\(valueName)\"=hex:") else {
      return nil
    }

    let suffix = userRegistryText[marker.upperBound...]
    var payload = ""
    for (index, line) in suffix.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      if index > 0, !line.hasPrefix("  ") { break }
      payload.append(contentsOf: line)
    }

    let expression = try NSRegularExpression(pattern: "(?i)(?<![0-9a-f])[0-9a-f]{2}(?![0-9a-f])")
    let fullRange = NSRange(payload.startIndex..<payload.endIndex, in: payload)
    let bytes = expression.matches(in: payload, range: fullRange).compactMap { match -> UInt8? in
      guard let range = Range(match.range, in: payload) else { return nil }
      return UInt8(payload[range], radix: 16)
    }
    guard !bytes.isEmpty else { throw GenshinPrefixConfigurationError.invalidRegistry }

    var data = Data(bytes)
    if data.last == 0 { data.removeLast() }
    guard
      var object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw GenshinPrefixConfigurationError.invalidRegistry
    }
    object["deviceLanguageType"] = textLanguage.gameValue
    object["deviceVoiceLanguageType"] = voiceLanguage.gameValue
    if graphicsProfile == .balanced {
      try applyBalancedGraphics(to: &object)
    }

    var updated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    updated.append(0)
    return updated.map { String(format: "%02x", $0) }.joined()
  }

  private static func applyBalancedGraphics(to object: inout [String: Any]) throws {
    let settings = [
      1: 2,  // 60 FPS
      2: 3,  // 1.0 internal render scale
      3: 2,  // low shadows
      4: 3,  // medium visual effects
      5: 3,  // medium SFX
      6: 3,  // medium environment detail
      7: 1,  // game VSync off; DXMT owns frame pacing
      8: 3,  // antialiasing enabled
      9: 1,  // volumetric fog off
      10: 1,  // reflections off
      11: 1,  // motion blur off
      12: 2,  // bloom on
      13: 1,  // low crowd density
      15: 2,  // medium subsurface scattering
      16: 1,  // teammate effects reduced
      17: 3,  // 4x anisotropic filtering
    ]

    let existingGraphics = (object["graphicsData"] as? String)
      .flatMap { $0.data(using: .utf8) }
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let version = existingGraphics?["volatileVersion"] as? String ?? "CNRELWin7.0.0"
    let grades = settings.keys.sorted().map { key in
      ["key": key, "value": settings[key] ?? 1]
    }
    let graphics: [String: Any] = [
      "currentVolatielGrade": -1,
      "customVolatileGrades": grades,
      "volatileVersion": version,
    ]
    object["graphicsData"] = String(
      decoding: try JSONSerialization.data(withJSONObject: graphics, options: [.sortedKeys]),
      as: UTF8.self
    )

    let perfItems = settings.keys.sorted().map { key in
      [
        "entryType": key,
        "index": (settings[key] ?? 1) - 1,
        "itemVersion": version,
      ] as [String: Any]
    }
    let performance: [String: Any] = [
      "saveItems": perfItems,
      "truePortedFromGraphicData": true,
      "portedVersion": version,
      "volatileUpgradeVersion": 0,
      "portedFromGraphicData": false,
    ]
    object["globalPerfData"] = String(
      decoding: try JSONSerialization.data(withJSONObject: performance, options: [.sortedKeys]),
      as: UTF8.self
    )
    object["motionBlur"] = false
  }
}

enum WineUserRegistryEditor {
  static func updatedText(
    _ registryText: String,
    preferences: GameLaunchPreferences
  ) throws -> String {
    var lines = registryText.components(separatedBy: "\n")
    guard
      let internationalSection = lines.firstIndex(where: {
        $0.hasPrefix("[Control Panel") && $0.contains("International]")
      }),
      lines.contains(where: {
        $0.hasPrefix("\"\(GenshinGeneralDataEditor.valueName)\"=")
      })
    else {
      throw GenshinPrefixConfigurationError.invalidRegistry
    }
    setValue("LocaleName", encoded: "\"zh-CN\"", section: internationalSection, lines: &lines)
    setValue("Locale", encoded: "\"00000804\"", section: internationalSection, lines: &lines)
    setValue("sLanguage", encoded: "\"CHS\"", section: internationalSection, lines: &lines)
    setValue("sCountry", encoded: "\"China\"", section: internationalSection, lines: &lines)
    setValue("iCountry", encoded: "\"86\"", section: internationalSection, lines: &lines)

    guard
      let updatedGeneralDataLine = lines.firstIndex(where: {
        $0.hasPrefix("\"\(GenshinGeneralDataEditor.valueName)\"=")
      })
    else {
      throw GenshinPrefixConfigurationError.invalidRegistry
    }
    let gameSection = try sectionStart(containing: updatedGeneralDataLine, lines: lines)

    let fullScreen = preferences.windowMode == .fullScreen ? 1 : 0
    if preferences.graphicsProfile == .balanced {
      setValue(
        "UnityGraphicsQuality_h1669003810",
        encoded: dword(2),
        section: gameSection,
        lines: &lines
      )
    }
    setValue(
      "Screenmanager Is Fullscreen mode_h3981298716",
      encoded: dword(fullScreen),
      section: gameSection,
      lines: &lines
    )
    setValue(
      "Screenmanager Resolution Width_h182942802",
      encoded: dword(preferences.resolution.width),
      section: gameSection,
      lines: &lines
    )
    setValue(
      "Screenmanager Resolution Height_h2627697771",
      encoded: dword(preferences.resolution.height),
      section: gameSection,
      lines: &lines
    )
    setValue(
      "MIHOYOSDK_CURRENT_LANGUAGE_h2559149783",
      encoded: binary(Data("zh-cn\0".utf8).map { String(format: "%02x", $0) }.joined()),
      section: gameSection,
      lines: &lines
    )

    let currentText = lines.joined(separator: "\n")
    if let generalData = try GenshinGeneralDataEditor.updatedBinaryHex(
      userRegistryText: currentText,
      textLanguage: preferences.textLanguage,
      voiceLanguage: preferences.voiceLanguage,
      graphicsProfile: preferences.graphicsProfile
    ) {
      setValue(
        GenshinGeneralDataEditor.valueName,
        encoded: binary(generalData),
        section: gameSection,
        lines: &lines
      )
    }

    return lines.joined(separator: "\n")
  }

  private static func sectionStart(containing index: Int, lines: [String]) throws -> Int {
    for candidate in stride(from: index, through: 0, by: -1) where lines[candidate].hasPrefix("[") {
      return candidate
    }
    throw GenshinPrefixConfigurationError.invalidRegistry
  }

  private static func setValue(
    _ name: String,
    encoded: String,
    section: Int,
    lines: inout [String]
  ) {
    let sectionEnd =
      lines[(section + 1)...].firstIndex(where: { $0.hasPrefix("[") })
      ?? lines.endIndex
    let prefix = "\"\(name)\"="
    if let existing = lines[section..<sectionEnd].firstIndex(where: { $0.hasPrefix(prefix) }) {
      var valueEnd = existing + 1
      while valueEnd < lines.endIndex, lines[valueEnd].hasPrefix("  ") {
        valueEnd += 1
      }
      lines.replaceSubrange(existing..<valueEnd, with: [prefix + encoded])
    } else {
      lines.insert(prefix + encoded, at: sectionEnd)
    }
  }

  private static func dword(_ value: Int) -> String {
    String(format: "dword:%08x", value)
  }

  private static func binary(_ compactHex: String) -> String {
    let bytes = stride(from: 0, to: compactHex.count, by: 2).map { offset -> String in
      let start = compactHex.index(compactHex.startIndex, offsetBy: offset)
      let remaining = compactHex.distance(from: start, to: compactHex.endIndex)
      let end = compactHex.index(start, offsetBy: min(2, remaining))
      return String(compactHex[start..<end])
    }
    return "hex:"
      + stride(from: 0, to: bytes.count, by: 16).map { offset in
        bytes[offset..<min(offset + 16, bytes.count)].joined(separator: ",")
      }.joined(separator: ",\\\n  ")
  }
}

struct GenshinPrefixConfigurator: Sendable {
  func prepare(paths: GameRuntimePaths, preferences: GameLaunchPreferences) throws {
    try run(paths.wineserver, ["-k"], paths: paths, requireSuccess: false, timeout: 3)
    try run(paths.wineserver, ["-w"], paths: paths, requireSuccess: false, timeout: 3)
    let userRegistry = paths.prefix.appending(path: "user.reg")
    let text = try String(contentsOf: userRegistry, encoding: .utf8)
    let updated = try WineUserRegistryEditor.updatedText(text, preferences: preferences)
    try updated.write(to: userRegistry, atomically: true, encoding: .utf8)
  }

  func stop(paths: GameRuntimePaths) throws {
    try run(paths.wineserver, ["-k"], paths: paths, requireSuccess: false, timeout: 3)
    try run(paths.wineserver, ["-w"], paths: paths, requireSuccess: false, timeout: 3)
  }

  private func run(
    _ executable: URL,
    _ arguments: [String],
    paths: GameRuntimePaths,
    requireSuccess: Bool = true,
    timeout: TimeInterval = 20
  ) throws {
    var fileActions: posix_spawn_file_actions_t?
    guard posix_spawn_file_actions_init(&fileActions) == 0 else {
      throw GenshinPrefixConfigurationError.commandFailed("file-actions")
    }
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_addopen(
      &fileActions,
      STDIN_FILENO,
      "/dev/null",
      O_RDONLY,
      0
    )
    posix_spawn_file_actions_addopen(
      &fileActions,
      STDOUT_FILENO,
      "/dev/null",
      O_WRONLY,
      0
    )
    posix_spawn_file_actions_adddup2(&fileActions, STDOUT_FILENO, STDERR_FILENO)

    let argumentStrings = [executable.path] + arguments
    let environmentStrings = launchEnvironment(paths: paths).map { "\($0.key)=\($0.value)" }
    var processIdentifier: pid_t = 0
    let spawnResult = withCStringArray(argumentStrings) { argumentPointers in
      withCStringArray(environmentStrings) { environmentPointers in
        posix_spawn(
          &processIdentifier,
          executable.path,
          &fileActions,
          nil,
          argumentPointers,
          environmentPointers
        )
      }
    }
    guard spawnResult == 0 else {
      NSLog(
        "MacGameBridge command spawn failed: %@ (%d)",
        executable.lastPathComponent,
        spawnResult
      )
      throw GenshinPrefixConfigurationError.commandFailed(
        "spawn:\(executable.lastPathComponent):\(spawnResult)"
      )
    }

    let deadline = Date().addingTimeInterval(timeout)
    var status: Int32 = 0
    var exited = false
    while Date() < deadline {
      let result = waitpid(processIdentifier, &status, WNOHANG)
      if result == processIdentifier {
        exited = true
        break
      }
      if result == -1 {
        NSLog("MacGameBridge command wait failed: %@", executable.lastPathComponent)
        throw GenshinPrefixConfigurationError.commandFailed(
          "wait:\(executable.lastPathComponent)"
        )
      }
      usleep(50_000)
    }
    if !exited {
      Darwin.kill(processIdentifier, SIGKILL)
      _ = waitpid(processIdentifier, &status, 0)
    }
    let exitedNormally = status & 0x7f == 0
    let exitCode = (status >> 8) & 0xff
    if requireSuccess, !exited || !exitedNormally || exitCode != 0 {
      NSLog(
        "MacGameBridge command failed: %@ %@ timedOut=%d exit=%d",
        executable.lastPathComponent,
        arguments.first ?? "",
        exited ? 0 : 1,
        exitCode
      )
      throw GenshinPrefixConfigurationError.commandFailed(
        "exit:\(executable.lastPathComponent):\(arguments.first ?? "none"):\(exited ? exitCode : -1)"
      )
    }
  }

  private func withCStringArray<Result>(
    _ strings: [String],
    body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
  ) -> Result {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer {
      for pointer in pointers.dropLast() {
        free(pointer)
      }
    }
    return pointers.withUnsafeMutableBufferPointer { buffer in
      body(buffer.baseAddress!)
    }
  }

  private func launchEnvironment(paths: GameRuntimePaths) -> [String: String] {
    let inherited = ProcessInfo.processInfo.environment
    var environment: [String: String] = [:]
    for key in ["HOME", "LOGNAME", "PATH", "TMPDIR", "USER"] {
      environment[key] = inherited[key]
    }
    environment["WINEPREFIX"] = paths.prefix.path
    environment["LANG"] = "zh_CN.UTF-8"
    environment["LC_ALL"] = "zh_CN.UTF-8"
    return environment
  }
}
