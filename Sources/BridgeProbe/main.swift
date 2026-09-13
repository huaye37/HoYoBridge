import BridgeCore
import Foundation

let report = SystemProbe().capture()

if CommandLine.arguments.contains("--json") {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  let data = try encoder.encode(report)
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
} else {
  let gigabyte = 1_000_000_000.0
  let memory = String(format: "%.1f GB", Double(report.physicalMemoryBytes) / gigabyte)
  let disk =
    report.freeDiskBytes.map { String(format: "%.1f GB", Double($0) / gigabyte) } ?? "unknown"

  print("MacGameBridge capability probe")
  print("macOS:       \(report.macOSVersion)")
  print("Architecture:\(report.architecture)")
  print("Model:       \(report.hardwareModel ?? "unknown")")
  print("Memory:      \(memory)")
  print("Free disk:   \(disk)")
  print(
    "Metal:       \(report.metal.deviceName ?? "unavailable") [\(report.metal.supportedFamilies.joined(separator: ", "))]"
  )
  print("Rosetta:     \(report.rosetta.availability.rawValue) \(report.rosetta.version ?? "")")
  print("Xcode:       \(report.xcode.version ?? report.xcode.availability.rawValue)")
  print("GPTK:        \(report.gptk.availability.rawValue) \(report.gptk.path ?? "")")
  print("Gatekeeper:  \(report.gatekeeper.detail ?? "unknown")")

  if !report.findings.isEmpty {
    print("Findings:")
    for finding in report.findings {
      print("- [\(finding.severity.rawValue)] \(finding.code): \(finding.message)")
    }
  }
}
