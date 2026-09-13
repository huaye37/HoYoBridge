import Foundation

public enum CapabilityAnalyzer {
  private static let initialInstallRecommendedBytes: UInt64 = 200 * 1_000_000_000

  public static func findings(for report: CapabilityReport) -> [DiagnosticFinding] {
    var findings: [DiagnosticFinding] = []

    let macOSMajor = report.macOSVersion.split(separator: ".").first.flatMap { Int($0) }
    if macOSMajor.map({ $0 == 26 || $0 == 27 }) != true {
      findings.append(
        .init(
          severity: .blocker,
          code: "unsupported-macos-version",
          message: "The first release supports macOS 26 and macOS 27 only."
        ))
    }

    if report.architecture != "arm64" {
      findings.append(
        .init(
          severity: .blocker,
          code: "unsupported-architecture",
          message: "The first release targets Apple Silicon only."
        ))
    }

    if !report.metal.available {
      findings.append(
        .init(
          severity: .blocker,
          code: "metal-unavailable",
          message: "No Metal device is available."
        ))
    }

    if report.rosetta.availability != .installed {
      findings.append(
        .init(
          severity: .warning,
          code: "rosetta-missing",
          message: "Current Wine-based runtimes may require Rosetta 2."
        ))
    }

    if macOSMajor == 27,
      report.gptk.availability != .installed
    {
      findings.append(
        .init(
          severity: .info,
          code: "gptk-not-installed",
          message:
            "macOS 27 is available, but GPTK/D3DMetal was not detected; DXMT remains a possible backend."
        ))
    }

    if let freeDiskBytes = report.freeDiskBytes,
      freeDiskBytes < initialInstallRecommendedBytes
    {
      findings.append(
        .init(
          severity: .warning,
          code: "initial-install-disk-low",
          message:
            "Initial game installation should reserve about 200 GB; current free space is below that planning threshold."
        ))
    }

    if report.gatekeeper.detail?.localizedCaseInsensitiveContains("disabled") == true {
      findings.append(
        .init(
          severity: .info,
          code: "gatekeeper-disabled",
          message:
            "Gatekeeper assessments are disabled. This probe reports the state but does not change it."
        ))
    }

    return findings
  }
}
