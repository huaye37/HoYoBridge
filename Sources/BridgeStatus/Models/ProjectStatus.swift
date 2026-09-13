import Foundation

enum StatusSection: String, CaseIterable, Identifiable {
  case overview
  case downloadPlan
  case environment
  case roadmap

  var id: Self { self }

  var title: String {
    switch self {
    case .overview: "项目概览"
    case .downloadPlan: "安装与更新"
    case .environment: "本机环境"
    case .roadmap: "路线图"
    }
  }

  var subtitle: String {
    switch self {
    case .overview: "已有成果与边界"
    case .downloadPlan: "下载、续传与空间预检"
    case .environment: "只读兼容性检测"
    case .roadmap: "距离能玩还有多远"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "rectangle.grid.2x2"
    case .downloadPlan: "arrow.down.circle"
    case .environment: "macbook.and.iphone"
    case .roadmap: "point.topleft.down.to.point.bottomright.curvepath"
    }
  }
}

struct ObservedManifestSnapshot: Equatable, Sendable {
  let observedAt: Date
  let fileCount: UInt64
  let chunkReferenceCount: UInt64
  let uniqueChunkObjectCount: UInt64
  let uniqueChunkObjectBytes: UInt64
  let targetInstalledBytes: UInt64
  let compressedManifestBytes: UInt64
  let decompressedManifestBytes: UInt64

  static let genshinOfficialCN = Self(
    observedAt: Date(timeIntervalSince1970: 1_787_137_904),
    fileCount: 2_673,
    chunkReferenceCount: 107_480,
    uniqueChunkObjectCount: 107_325,
    uniqueChunkObjectBytes: 121_185_381_917,
    targetInstalledBytes: 124_827_264_431,
    compressedManifestBytes: 8_521_303,
    decompressedManifestBytes: 15_913_977
  )
}

struct VerifiedChunkProbeSnapshot: Equatable, Sendable {
  let observedAt: Date
  let compressedBytes: UInt64
  let sha256: String
  let cacheRelativePath: String
  let requestCount: UInt8
  let compressedMD5Verified: Bool
  let uncompressedMD5Verified: Bool

  static let genshinOfficialCN = Self(
    observedAt: Date(timeIntervalSince1970: 1_787_217_671),
    compressedBytes: 21,
    sha256: "8a1c5ac944823490b4879b551f5862fe3718e96738f7f4e29490c280391b5391",
    cacheRelativePath:
      "objects/sha256/8a/8a1c5ac944823490b4879b551f5862fe3718e96738f7f4e29490c280391b5391",
    requestCount: 4,
    compressedMD5Verified: true,
    uncompressedMD5Verified: true
  )
}

struct DownloadedGameSnapshot: Equatable, Sendable {
  let completedAt: Date
  let version: String
  let manifestFileCount: UInt64
  let installedBytes: UInt64
  let executableVerified: Bool
  let dataDirectoryVerified: Bool

  static let genshinOfficialCN = Self(
    completedAt: Date(timeIntervalSince1970: 1_787_234_479),
    version: "7.0.0",
    manifestFileCount: 2_673,
    installedBytes: 124_827_264_431,
    executableVerified: true,
    dataDirectoryVerified: true
  )
}

struct RuntimeExperimentSnapshot: Equatable, Sendable {
  let wineVersion: String
  let dxmtVersion: String
  let windowsVersion: String
  let launchAttemptCount: UInt8
  let blockerCode: String
  let gameFilesModified: Bool
  let systemSettingsModified: Bool

  static let genshinOfficialCN = Self(
    wineVersion: "11.0-1 CrossOver",
    dxmtVersion: "0.80",
    windowsVersion: "10.0.19045",
    launchAttemptCount: 1,
    blockerCode: "游戏窗口已成功打开",
    gameFilesModified: false,
    systemSettingsModified: false
  )
}

enum DeliveryState: String, Equatable, Sendable {
  case verified
  case foundation
  case blocked
  case notStarted

  var title: String {
    switch self {
    case .verified: "已验证"
    case .foundation: "已有基础"
    case .blocked: "已定位阻塞"
    case .notStarted: "未完成"
    }
  }

  var systemImage: String {
    switch self {
    case .verified: "checkmark.circle.fill"
    case .foundation: "hammer.circle.fill"
    case .blocked: "exclamationmark.triangle.fill"
    case .notStarted: "circle.dashed"
    }
  }
}

struct DeliveryMilestone: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let detail: String
  let state: DeliveryState
}

enum StatusDemoData {
  static let milestones = [
    DeliveryMilestone(
      id: "manifest",
      title: "国服资源清单",
      detail: "已完整解压、解析并校验一份受控观测快照。",
      state: .verified
    ),
    DeliveryMilestone(
      id: "runtime",
      title: "CrossOver 兼容运行时",
      detail: "Wine 11.0-1 CrossOver + DXMT 0.80 + Steam 兼容入口已经形成可重复启动链。",
      state: .verified
    ),
    DeliveryMilestone(
      id: "download",
      title: "国服 7.0.0 完整客户端",
      detail: "2,673 个清单文件已下载并逐文件校验，关键入口与数据目录已复核。",
      state: .verified
    ),
    DeliveryMilestone(
      id: "launch",
      title: "真实游戏启动",
      detail: "原版国服客户端已经通过 CrossOver + Steam 兼容入口成功打开游戏窗口。",
      state: .verified
    ),
    DeliveryMilestone(
      id: "acceptance",
      title: "登录、持续运行与性能验收",
      detail: "等待完成登录、长时间运行、画面正确性、帧率和 1% Low 验收。",
      state: .notStarted
    ),
  ]
}
