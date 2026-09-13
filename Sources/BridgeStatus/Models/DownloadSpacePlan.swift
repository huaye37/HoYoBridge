import Foundation

enum DownloadSpaceReadiness: Equatable, Sendable {
  case ready(remainingBytes: UInt64)
  case insufficient(missingBytes: UInt64)
  case unknown
}

struct DownloadSpacePlan: Equatable, Sendable {
  let resourceCacheBytes: UInt64
  let installedGameBytes: UInt64
  let safetyReserveBytes: UInt64

  var requiredPeakBytes: UInt64? {
    let (payloadAndInstall, firstOverflow) = resourceCacheBytes.addingReportingOverflow(
      installedGameBytes)
    guard !firstOverflow else { return nil }

    let (total, secondOverflow) = payloadAndInstall.addingReportingOverflow(safetyReserveBytes)
    guard !secondOverflow else { return nil }
    return total
  }

  func readiness(freeDiskBytes: UInt64?) -> DownloadSpaceReadiness {
    guard let requiredPeakBytes, let freeDiskBytes else { return .unknown }
    if freeDiskBytes >= requiredPeakBytes {
      return .ready(remainingBytes: freeDiskBytes - requiredPeakBytes)
    }
    return .insufficient(missingBytes: requiredPeakBytes - freeDiskBytes)
  }

  static let genshinOfficialCNInitialInstall = Self(
    resourceCacheBytes: ObservedManifestSnapshot.genshinOfficialCN.uniqueChunkObjectBytes,
    installedGameBytes: ObservedManifestSnapshot.genshinOfficialCN.targetInstalledBytes,
    safetyReserveBytes: 20_000_000_000
  )
}
