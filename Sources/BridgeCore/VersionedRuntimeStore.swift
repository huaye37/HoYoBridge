import Darwin
import Foundation

public enum VersionedRuntimeStoreError: Error, Equatable, Sendable {
  case invalidRootURL
  case unsafeRuntimeRoot
  case publisherBusy
  case unsafeStoreEntry
  case stagingCrossVolume
  case versionAlreadyExists(String)
  case corruptExistingVersion(String)
  case currentAlreadyExists
  case invalidExpectedCurrent
  case currentChanged
  case currentSwapUnsupported(Int32)
  case invalidInstallID
  case untrustedRuntime(String)
  case currentMissing
  case currentInvalid
  case currentNotAuthorized
  case publishFailed(Int32)
  case cleanupFailed
}

public enum VersionedRuntimeCommitState: Equatable, Sendable {
  case versionVisible(installID: String, durabilityConfirmed: Bool)
  case currentVisible(activationID: String, durabilityConfirmed: Bool)
}

public struct VersionedRuntimeCommittedError: Error {
  public let state: VersionedRuntimeCommitState
  public let underlyingError: any Error
}

public struct VersionedRuntimeInstallAndCleanupError: Error {
  public let installError: any Error
  public let cleanupError: any Error
}

public enum InstalledRuntimeDisposition: String, Equatable, Sendable {
  case published
  case reusedExisting
  case reopenedExisting
}

public struct InstalledRuntimeVersion: Equatable, Sendable {
  public let versionURL: URL
  public let record: RuntimeInstallRecord
  public let disposition: InstalledRuntimeDisposition
}

/// A lock-scoped snapshot. Launch must reverify the selected runtime before use.
public struct ResolvedRuntimeCurrent: Equatable, Sendable {
  public let current: RuntimeActivationRecord
  public let installed: InstalledRuntimeVersion
  public let decision: CompatibilityDecision
}

public struct VersionedRuntimeStore {
  public let rootURL: URL
  let postRenameHook: (@Sendable () throws -> Void)?
  let preCurrentCommitHook: (@Sendable () throws -> Void)?

  public init(rootURL: URL) {
    self.rootURL = rootURL
    postRenameHook = nil
    preCurrentCommitHook = nil
  }

  init(rootURL: URL, postRenameHook: @escaping @Sendable () throws -> Void) {
    self.rootURL = rootURL
    self.postRenameHook = postRenameHook
    preCurrentCommitHook = nil
  }

  init(rootURL: URL, preCurrentCommitHook: @escaping @Sendable () throws -> Void) {
    self.rootURL = rootURL
    postRenameHook = nil
    self.preCurrentCommitHook = preCurrentCommitHook
  }

}
