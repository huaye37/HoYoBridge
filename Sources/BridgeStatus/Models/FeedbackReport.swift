import Foundation
import CryptoKit

enum FeedbackCategory: String, CaseIterable, Identifiable {
  case installation = "安装与下载"
  case update = "更新与修复"
  case launch = "无法启动或崩溃"
  case display = "画面与窗口"
  case performance = "性能与手柄"
  case suggestion = "建议与其他"
  var id: String { rawValue }
}

struct FeedbackReport {
  let id: UUID
  let game: String
  let category: String
  let title: String
  let detail: String
  let diagnostics: String
  let fingerprint: String

  static func redact(_ text: String) -> String {
    var value = text
    let patterns = [
      #"(?i)(?:authorization\s*:\s*bearer\s+|bearer\s+)[^\s,;]+"#,
      #"(?i)(?:token|password|passwd|cookie|secret|api[_-]?key|uid|account)[\"']?\s*[:=]\s*[\"']?[^\s\"',;]+"#,
      #"(?i)https?://[^\s<>]+"#,
      #"(?i)(?:[A-Z]:\\|/Users/|/Volumes/)[^\r\n]+"#,
      #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
      #"(?<!\d)1[3-9]\d{9}(?!\d)"#,
      #"\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+)\b"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
      value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "[已隐藏]")
    }
    return value
  }

  static let allowedEvents: Set<String> = ["engine_reconnected", "debug_port_conflict", "engine_prepare_failed",
    "engine_started", "engine_exited", "engine_connected", "engine_connect_timeout", "engine_stop_result", "task_stop_failed"]

  static func safeEvents(_ raw: String) -> [String] {
    raw.split(separator: "\n").suffix(30).compactMap { line in
      let fields = line.split(separator: " ")
      guard fields.count == 3, allowedEvents.contains(String(fields[1])) else { return nil }
      let event = String(fields[1])
      guard let code = Int32(fields[2].replacingOccurrences(of: "code=", with: "")) else { return nil }
      return event == "engine_started" ? event : "\(event) code=\(code)"
    }
  }

  static func make(game: MiHoYoGame, category: FeedbackCategory, title: String, detail: String,
    includeDiagnostics: Bool, version: String, system: String, memoryGB: UInt64, engineLog: String) -> Self {
    let events = safeEvents(engineLog)
    let signature = [game.rawValue, category.id, version, system, events.last ?? "none"].joined(separator: "|")
    let fingerprint = SHA256.hash(data: Data(signature.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    let diagnostics = includeDiagnostics ? """
    应用：\(version)
    macOS：\(system)
    架构：Apple Silicon
    内存：\(memoryGB) GB
    运行环境：CrossOver 11 / DXMT 0.80
    后台事件（不含路径、进程号和账号日志）：
    \(events.isEmpty ? "无可用事件" : events.joined(separator: "\n"))
    """ : "用户未附带诊断信息"
    return Self(id: UUID(), game: game.title, category: category.id,
      title: String(redact(title).prefix(120)), detail: String(redact(detail).prefix(6000)),
      diagnostics: diagnostics, fingerprint: includeDiagnostics ? fingerprint : "not-provided")
  }

  var markdown: String {
    """
    ## 问题
    \(title)

    游戏：\(game)
    分类：\(category)
    报告编号：\(id.uuidString)
    问题特征：`\(fingerprint)`

    ## 现象与复现步骤
    \(detail)

    ## 诊断摘要
    ```text
    \(diagnostics)
    ```
    """
  }

  func issueURL(repository: String) -> URL? {
    guard repository.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return nil }
    var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
    components.queryItems = [URLQueryItem(name: "title", value: "[\(game)] \(title)"), URLQueryItem(name: "body", value: markdown)]
    if let url = components.url, url.absoluteString.utf8.count <= 7500 { return url }
    components.queryItems = [URLQueryItem(name: "title", value: "[\(game)] \(title)"),
      URLQueryItem(name: "body", value: "请在此粘贴启动器已复制的报告。报告编号：\(id.uuidString)")]
    return components.url
  }
}
