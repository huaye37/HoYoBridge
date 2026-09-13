import SwiftUI
import UniformTypeIdentifiers

struct FeedbackView: View {
  @State private var game: MiHoYoGame = .starRail
  @State private var category = FeedbackCategory.launch
  @State private var title = ""
  @State private var detail = ""
  @State private var includeDiagnostics = false
  @State private var report: FeedbackReport?
  @State private var notice = ""
  private let repository = "huaye37/HoYoBridge"

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("问题反馈").font(.title2.bold())
      Text("先描述问题，再预览报告。不会自动上传账号、游戏原始日志或截图。")
        .font(.callout).foregroundStyle(.secondary)
      HStack {
        Picker("游戏", selection: $game) { ForEach(MiHoYoGame.allCases) { Text($0.title).tag($0) } }
        Picker("分类", selection: $category) { ForEach(FeedbackCategory.allCases) { Text($0.rawValue).tag($0) } }
      }
      TextField("一句话描述问题", text: $title).textFieldStyle(.roundedBorder)
      Text("发生了什么？如何重现？预期应该怎样？").font(.caption).foregroundStyle(.secondary)
      TextEditor(text: $detail).frame(minHeight: 100, maxHeight: 150).border(.quaternary)
      Toggle("附带基础环境与脱敏后台事件", isOn: $includeDiagnostics)
      HStack {
        Button("生成并预览报告") { generate() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || detail.isEmpty)
        Spacer()
        if report != nil { Text("下方为本次提交的完整内容").font(.caption).foregroundStyle(.secondary) }
      }
      if let report {
        ScrollView { Text(verbatim: report.markdown).font(.system(.caption, design: .monospaced))
          .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
          .frame(minHeight: 130).padding(8).background(.quaternary.opacity(0.4))
        Text("提交前请确认没有个人信息。GitHub 反馈需要账号；若仓库未开放，可先保存报告发给维护者。")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button("保存报告…") { save(report) }
          Button("复制报告") { copy(report); notice = "已复制，尚未发送。" }
          Spacer()
          Button("前往 GitHub 确认提交") {
            copy(report)
            if let url = report.issueURL(repository: repository), NSWorkspace.shared.open(url) {
              notice = "已打开 GitHub 草稿，尚未提交；长报告请粘贴后提交。"
            } else { notice = "无法打开浏览器；报告已复制，可保存后发送。" }
          }.buttonStyle(.borderedProminent)
        }
      }
      if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.secondary) }
    }
    .padding(24).frame(minWidth: 650, minHeight: 560)
    .onChange(of: title) { report = nil }
    .onChange(of: detail) { report = nil }
    .onChange(of: game) { report = nil }
    .onChange(of: category) { report = nil }
    .onChange(of: includeDiagnostics) { report = nil }
  }

  private func generate() {
    let logURL = GameRuntimePaths.userStorageRoot.appending(path: "Diagnostics/official-engine.log")
    let log: String
    if includeDiagnostics, let handle = try? FileHandle(forReadingFrom: logURL) {
      defer { try? handle.close() }
      log = String(decoding: (try? handle.read(upToCount: 32_768)) ?? Data(), as: UTF8.self)
    } else { log = "" }
    let os = ProcessInfo.processInfo.operatingSystemVersion
    report = FeedbackReport.make(game: game, category: category, title: title, detail: detail,
      includeDiagnostics: includeDiagnostics, version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
      system: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      memoryGB: ProcessInfo.processInfo.physicalMemory / 1_073_741_824, engineLog: log)
    notice = "报告仅在本机生成，尚未发送。"
  }

  private func copy(_ report: FeedbackReport) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report.markdown, forType: .string)
  }

  private func save(_ report: FeedbackReport) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "HoYoBridge-feedback-\(report.id.uuidString.prefix(8)).txt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try report.markdown.write(to: url, atomically: true, encoding: .utf8); notice = "报告已保存，尚未发送。" }
    catch { notice = "保存失败，请选择可写目录。" }
  }
}
