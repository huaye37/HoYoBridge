import Foundation

@MainActor
enum StatusFormatting {
  static let byteCount: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB, .useTB]
    formatter.countStyle = .decimal
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
  }()

  static let observationDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
    return formatter
  }()

  static let integer: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  static func bytes(_ value: UInt64) -> String {
    byteCount.string(fromByteCount: Int64(clamping: value))
  }

  static func count(_ value: UInt64) -> String {
    integer.string(from: NSNumber(value: value)) ?? String(value)
  }
}
