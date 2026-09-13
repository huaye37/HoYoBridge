import Foundation

public enum GPTKDetector {
  public static let defaultCandidates = [
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "MacGameBridge/Runtimes/GPTK/active/lib/external/D3DMetal.framework")
      .path,
    "/Library/Apple/usr/lib/external/D3DMetal.framework",
    "/usr/local/lib/external/D3DMetal.framework",
    "/opt/homebrew/lib/external/D3DMetal.framework",
    "/Applications/Game Porting Toolkit.app",
    "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework",
  ]

  public static func detect(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    candidates: [String] = defaultCandidates,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
    versionAtPath: (String) -> String? = detectedVersion
  ) -> ComponentStatus {
    var searchPaths: [String] = []
    if let explicitPath = environment["GPTK_HOME"], !explicitPath.isEmpty {
      searchPaths.append(explicitPath)
    }
    searchPaths.append(contentsOf: candidates)

    if let path = searchPaths.first(where: fileExists) {
      let version = versionAtPath(path)
      return ComponentStatus(
        availability: .installed,
        version: version,
        path: path,
        detail: version == nil
          ? "Detected GPTK/D3DMetal, but its version could not be verified."
          : "Detected a local GPTK/D3DMetal installation."
      )
    }

    return ComponentStatus(
      availability: .missing,
      detail: "No GPTK/D3DMetal installation was found in known locations."
    )
  }

  @usableFromInline
  static func detectedVersion(at path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    let bundleURL =
      path.hasSuffix(".app")
      ? url
      : (path.hasSuffix(".framework") ? url : nil)
    guard let bundleURL,
      let values = NSDictionary(contentsOf: bundleURL.appending(path: "Contents/Info.plist"))
        ?? NSDictionary(contentsOf: bundleURL.appending(path: "Resources/Info.plist"))
        ?? NSDictionary(
          contentsOf: bundleURL.appending(path: "Versions/Current/Resources/Info.plist")
        )
    else { return nil }
    return values["CFBundleShortVersionString"] as? String
      ?? values["CFBundleVersion"] as? String
  }
}
