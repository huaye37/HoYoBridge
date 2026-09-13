import Foundation
import Testing

@testable import BridgeCore

struct CapabilityAnalyzerTests {
  @Test
  func macOS27WithoutGPTKReportsFallbackAndDiskWarning() {
    let report = CapabilityReport(
      macOSVersion: "27.0.0",
      architecture: "arm64",
      physicalMemoryBytes: 48_000_000_000,
      freeDiskBytes: 86_000_000_000,
      metal: .init(available: true, supportedFamilies: ["apple10"]),
      rosetta: .init(availability: .installed),
      xcode: .init(availability: .installed, version: "Xcode 26.6"),
      gptk: .init(availability: .missing),
      gatekeeper: .init(availability: .installed, detail: "assessments disabled")
    )

    let codes = Set(CapabilityAnalyzer.findings(for: report).map(\.code))
    #expect(codes.contains("gptk-not-installed"))
    #expect(codes.contains("initial-install-disk-low"))
    #expect(codes.contains("gatekeeper-disabled"))
    #expect(!codes.contains("unsupported-architecture"))
  }

  @Test
  func nonAppleSiliconIsBlocked() {
    let report = CapabilityReport(
      macOSVersion: "26.0.0",
      architecture: "x86_64",
      physicalMemoryBytes: 16_000_000_000,
      metal: .init(available: true),
      rosetta: .init(availability: .missing),
      xcode: .init(availability: .missing),
      gptk: .init(availability: .missing),
      gatekeeper: .init(availability: .installed, detail: "assessments enabled")
    )

    let findings = CapabilityAnalyzer.findings(for: report)
    #expect(findings.contains { $0.code == "unsupported-architecture" && $0.severity == .blocker })
  }

  @Test(arguments: ["25.6.0", "28.0.0", "unknown"])
  func macOSOutsideFirstReleaseRangeIsBlocked(version: String) {
    let report = CapabilityReport(
      macOSVersion: version,
      architecture: "arm64",
      physicalMemoryBytes: 16_000_000_000,
      metal: .init(available: true),
      rosetta: .init(availability: .installed),
      xcode: .init(availability: .installed),
      gptk: .init(availability: .missing),
      gatekeeper: .init(availability: .installed, detail: "assessments enabled")
    )

    let findings = CapabilityAnalyzer.findings(for: report)
    #expect(
      findings.contains {
        $0.code == "unsupported-macos-version" && $0.severity == .blocker
      }
    )
  }
}
