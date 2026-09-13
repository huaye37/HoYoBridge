import Darwin
import Foundation

struct GameFramePerformanceReport: Equatable, Sendable {
  let frameCount: Int
  let averageFPS: Double
  let onePercentLowFPS: Double
  let averageFrameTimeMilliseconds: Double
  let percentile95FrameTimeMilliseconds: Double
  let percentile99FrameTimeMilliseconds: Double
  let frameTimeStandardDeviationMilliseconds: Double
  let averageGPUTimeMilliseconds: Double
  let percentile95GPUTimeMilliseconds: Double
  let slowFrameCount: Int

  var slowFramePercent: Double {
    guard frameCount > 0 else { return 0 }
    return Double(slowFrameCount) / Double(frameCount) * 100
  }
}

struct GamePerformanceReport: Equatable, Sendable {
  let benchmarkKind: String
  let graphicsBackend: String
  let graphicsProfile: String
  let resolution: String
  let durationSeconds: Int
  let sampleCount: Int
  let peakMemoryBytes: UInt64
  let averageMemoryBytes: UInt64
  let averageCPUPercent: Double
  let maximumCPUPercent: Double
  let maximumProcessCount: Int
  let shaderLoadCount: Int
  let streamOutputWarningCount: Int
  let framePerformance: GameFramePerformanceReport?

  var durationText: String {
    let minutes = durationSeconds / 60
    let seconds = durationSeconds % 60
    return "\(minutes) 分 \(seconds) 秒"
  }

  var peakMemoryText: String { Self.bytes(peakMemoryBytes) }
  var averageMemoryText: String { Self.bytes(averageMemoryBytes) }

  var assessmentTitle: String {
    if let framePerformance, framePerformance.onePercentLowFPS < 50 {
      return "帧节奏需要优化"
    }
    if peakMemoryBytes >= 5 * 1_073_741_824 {
      return "内存仍然偏高"
    }
    if shaderLoadCount > 0 || streamOutputWarningCount > 0 {
      return "内存受控，掉帧仍需继续优化"
    }
    return "本轮运行负载稳定"
  }

  var assessmentDetail: String {
    var findings: [String] = []
    if peakMemoryBytes >= 5 * 1_073_741_824 {
      findings.append("兼容层峰值超过 5 GB")
    }
    if shaderLoadCount > 0 {
      findings.append("游戏仍提交了 \(shaderLoadCount) 次 shader load")
    }
    if streamOutputWarningCount > 0 {
      findings.append("DXMT 出现 \(streamOutputWarningCount) 次 stream-output 兼容警告")
    }
    if let framePerformance {
      findings.append(
        String(
          format: "平均 %.1f FPS，1%% Low %.1f FPS",
          framePerformance.averageFPS,
          framePerformance.onePercentLowFPS
        ))
    }
    return findings.isEmpty ? "未发现新的明显异常；尚未执行逐帧基准测试。" : findings.joined(separator: "；") + "。"
  }

  private static func bytes(_ value: UInt64) -> String {
    String(format: "%.1f GB", Double(value) / 1_073_741_824)
  }
}

enum GamePerformanceReportParser {
  static func parse(launcherLog: String, gameLog: String?) -> GamePerformanceReport? {
    var benchmarkKind = "none"
    var graphicsBackend = "unknown"
    var graphicsProfile = "unknown"
    var resolution = "unknown"
    var sampleCount = 0
    var elapsedSeconds = 0
    var peakMemoryBytes: UInt64 = 0
    var memorySum = 0.0
    var cpuSum = 0.0
    var maximumCPU = 0.0
    var maximumProcessCount = 0
    var streamOutputWarnings = 0
    var frameCaptureActive = false
    var frameIntervals: [Double] = []
    var gpuTimes: [Double] = []
    var captureSampleCount = 0
    var capturePeakMemoryBytes: UInt64 = 0
    var captureMemorySum = 0.0
    var captureCPUSum = 0.0
    var captureMaximumCPU = 0.0
    var captureMaximumProcessCount = 0

    for line in launcherLog.split(separator: "\n") {
      let text = String(line)
      if text.hasPrefix("MGB_CONFIG ") {
        let fields = keyValues(text)
        graphicsBackend = fields["backend"] ?? graphicsBackend
        graphicsProfile = fields["graphics"] ?? graphicsProfile
        resolution = fields["resolution"] ?? resolution
      } else if text.hasPrefix("MGB_BENCHMARK ") {
        benchmarkKind = keyValues(text)["kind"] ?? benchmarkKind
      } else if text == "MGB_FRAME_CAPTURE_START" {
        if benchmarkKind == "none" { benchmarkKind = "startup" }
        frameIntervals.removeAll(keepingCapacity: true)
        gpuTimes.removeAll(keepingCapacity: true)
        frameCaptureActive = true
      } else if text == "MGB_FRAME_CAPTURE_END" {
        frameCaptureActive = false
      } else if text.hasPrefix("MGB_PERF ") {
        let fields = keyValues(text)
        guard let memory = fields["rss_bytes"].flatMap(UInt64.init),
          let cpu = fields["cpu_percent"].flatMap(Double.init),
          let processes = fields["processes"].flatMap(Int.init)
        else { continue }
        sampleCount += 1
        peakMemoryBytes = max(peakMemoryBytes, memory)
        if let reportedPeak = fields["peak_rss_bytes"].flatMap(UInt64.init) {
          peakMemoryBytes = max(peakMemoryBytes, reportedPeak)
        }
        if let reportedElapsed = fields["elapsed_seconds"].flatMap(Int.init) {
          elapsedSeconds = max(elapsedSeconds, reportedElapsed)
        }
        memorySum += Double(memory)
        cpuSum += cpu
        maximumCPU = max(maximumCPU, cpu)
        maximumProcessCount = max(maximumProcessCount, processes)
        if frameCaptureActive {
          captureSampleCount += 1
          capturePeakMemoryBytes = max(capturePeakMemoryBytes, memory)
          captureMemorySum += Double(memory)
          captureCPUSum += cpu
          captureMaximumCPU = max(captureMaximumCPU, cpu)
          captureMaximumProcessCount = max(captureMaximumProcessCount, processes)
        }
      }
      if text.contains("Emulate stream output") {
        streamOutputWarnings += 1
      }
      if frameCaptureActive {
        appendMetalHUDFrames(text, intervals: &frameIntervals, gpuTimes: &gpuTimes)
      }
    }

    guard sampleCount > 0 else { return nil }
    let shaderLoadCount =
      gameLog?.split(separator: "\n")
      .count(where: { $0.hasPrefix("submit shader load ") }) ?? 0
    let frames = frameReport(intervals: frameIntervals, gpuTimes: gpuTimes)
    let usesCaptureWindow = frames != nil && captureSampleCount > 0
    let reportedSampleCount = usesCaptureWindow ? captureSampleCount : sampleCount
    let reportedDuration =
      frames.map {
        Int((Double($0.frameCount) * $0.averageFrameTimeMilliseconds / 1_000).rounded())
      } ?? max(elapsedSeconds, sampleCount * 2)
    return GamePerformanceReport(
      benchmarkKind: benchmarkKind,
      graphicsBackend: graphicsBackend,
      graphicsProfile: graphicsProfile,
      resolution: resolution,
      durationSeconds: reportedDuration,
      sampleCount: reportedSampleCount,
      peakMemoryBytes: usesCaptureWindow ? capturePeakMemoryBytes : peakMemoryBytes,
      averageMemoryBytes: UInt64(
        (usesCaptureWindow ? captureMemorySum : memorySum) / Double(reportedSampleCount)),
      averageCPUPercent: (usesCaptureWindow ? captureCPUSum : cpuSum)
        / Double(reportedSampleCount),
      maximumCPUPercent: usesCaptureWindow ? captureMaximumCPU : maximumCPU,
      maximumProcessCount: usesCaptureWindow
        ? captureMaximumProcessCount : maximumProcessCount,
      shaderLoadCount: shaderLoadCount,
      streamOutputWarningCount: streamOutputWarnings,
      framePerformance: frames
    )
  }

  private static func appendMetalHUDFrames(
    _ line: String,
    intervals: inout [Double],
    gpuTimes: inout [Double]
  ) {
    guard let marker = line.range(of: "metal-HUD:") else { return }
    let values = line[marker.upperBound...]
      .split(separator: ",")
      .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard values.count >= 5 else { return }
    var index = 3
    while index + 1 < values.count {
      let interval = values[index]
      let gpuTime = values[index + 1]
      if (1...2_000).contains(interval), gpuTime >= 0 {
        intervals.append(interval)
        gpuTimes.append(gpuTime)
      }
      index += 2
    }
  }

  private static func frameReport(
    intervals: [Double],
    gpuTimes: [Double]
  ) -> GameFramePerformanceReport? {
    guard intervals.count >= 60, intervals.count == gpuTimes.count else { return nil }
    let totalDuration = intervals.reduce(0, +)
    guard totalDuration > 0 else { return nil }
    let averageFrameTime = totalDuration / Double(intervals.count)
    let variance =
      intervals.reduce(0) { partial, value in
        let difference = value - averageFrameTime
        return partial + difference * difference
      } / Double(intervals.count)
    let p95 = percentile(intervals, fraction: 0.95)
    let p99 = percentile(intervals, fraction: 0.99)
    return GameFramePerformanceReport(
      frameCount: intervals.count,
      averageFPS: 1_000 * Double(intervals.count) / totalDuration,
      onePercentLowFPS: p99 > 0 ? 1_000 / p99 : 0,
      averageFrameTimeMilliseconds: averageFrameTime,
      percentile95FrameTimeMilliseconds: p95,
      percentile99FrameTimeMilliseconds: p99,
      frameTimeStandardDeviationMilliseconds: variance.squareRoot(),
      averageGPUTimeMilliseconds: gpuTimes.reduce(0, +) / Double(gpuTimes.count),
      percentile95GPUTimeMilliseconds: percentile(gpuTimes, fraction: 0.95),
      slowFrameCount: intervals.count(where: { $0 > 33.34 })
    )
  }

  private static func percentile(_ values: [Double], fraction: Double) -> Double {
    let sorted = values.sorted()
    let position = Double(sorted.count - 1) * fraction
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower != upper else { return sorted[lower] }
    let weight = position - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
  }

  private static func keyValues(_ line: String) -> [String: String] {
    var result: [String: String] = [:]
    for component in line.split(separator: " ").dropFirst() {
      guard let separator = component.firstIndex(of: "=") else { continue }
      let key = String(component[..<separator])
      let value = String(component[component.index(after: separator)...])
      guard !key.isEmpty, !value.isEmpty else { continue }
      result[key] = value
    }
    return result
  }
}

enum GamePerformanceReportLoader {
  static func latest(paths: GameRuntimePaths) -> GamePerformanceReport? {
    guard let logs = directoryEntries(at: paths.diagnosticsDirectory) else { return nil }
    let launcherLogURL =
      logs
      .filter { $0.lastPathComponent.hasPrefix("launcher-") && $0.pathExtension == "log" }
      .max { left, right in
        modificationDate(left) < modificationDate(right)
      }
    guard let launcherLogURL,
      let launcherLog = try? String(contentsOf: launcherLogURL, encoding: .utf8)
    else { return nil }
    return GamePerformanceReportParser.parse(launcherLog: launcherLog, gameLog: nil)
  }

  static func latestBenchmarks(paths: GameRuntimePaths) -> [GameGraphicsBackend:
    GamePerformanceReport]
  {
    let userDiagnostics = GameRuntimePaths.userStorageRoot.appending(
      path: "LocalRuntimes/Diagnostics",
      directoryHint: .isDirectory
    )
    let directories = Set([paths.diagnosticsDirectory, userDiagnostics])
    var selected: [GameGraphicsBackend: (date: Date, report: GamePerformanceReport)] = [:]
    for directory in directories {
      guard let logs = directoryEntries(at: directory) else { continue }
      for logURL in logs
      where logURL.lastPathComponent.hasPrefix("launcher-") && logURL.pathExtension == "log" {
        guard let log = try? String(contentsOf: logURL, encoding: .utf8),
          let report = GamePerformanceReportParser.parse(launcherLog: log, gameLog: nil),
          report.benchmarkKind == "gameplay",
          report.framePerformance != nil,
          let backend = GameGraphicsBackend(rawValue: report.graphicsBackend)
        else { continue }
        let date = modificationDate(logURL)
        if selected[backend]?.date ?? .distantPast < date {
          selected[backend] = (date, report)
        }
      }
    }
    return selected.mapValues(\.report)
  }

  private static func modificationDate(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? .distantPast
  }

  private static func directoryEntries(at directory: URL) -> [URL]? {
    guard let stream = opendir(directory.path) else { return nil }
    defer { closedir(stream) }
    var entries: [URL] = []
    while let entry = readdir(stream) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
          String(cString: $0)
        }
      }
      guard !name.hasPrefix(".") else { continue }
      entries.append(directory.appending(path: name))
    }
    return entries
  }
}
