import Foundation

enum GameSetupStepState: Equatable, Sendable {
  case pending
  case active
  case complete
  case attention
}

enum GameSetupStage: Equatable, Sendable {
  case checking
  case storageInsufficient(missingBytes: UInt64)
  case readyToInstall
  case installingGame
  case installingGameAndRuntime
  case preparingRuntime
  case needsAttention
  case ready
}

struct GameSetupProgress: Equatable, Sendable {
  let stage: GameSetupStage
  let storage: GameSetupStepState
  let game: GameSetupStepState
  let runtime: GameSetupStepState
  let launch: GameSetupStepState
  let fraction: Double
}

enum GameSetupProgressResolver {
  static func resolve(
    installation: GameInstallationState,
    runtime: RuntimePreparationState,
    launcher: GameLaunchState,
    storage: DownloadSpaceReadiness
  ) -> GameSetupProgress {
    let installationExists: Bool
    let storageAlreadyAuthorized: Bool
    let gameStep: GameSetupStepState
    let gameProgress: Double
    switch installation {
    case .installed:
      installationExists = true
      storageAlreadyAuthorized = true
      gameStep = .complete
      gameProgress = 1
    case .installing(let progress):
      installationExists = false
      storageAlreadyAuthorized = true
      gameStep = .active
      gameProgress = progress.fraction
    case .cancelling:
      installationExists = false
      storageAlreadyAuthorized = true
      gameStep = .active
      gameProgress = 0
    case .failed, .unavailable:
      installationExists = false
      storageAlreadyAuthorized = false
      gameStep = .attention
      gameProgress = 0
    case .checking:
      installationExists = false
      storageAlreadyAuthorized = false
      gameStep = .active
      gameProgress = 0
    case .notInstalled:
      installationExists = false
      storageAlreadyAuthorized = false
      gameStep = .pending
      gameProgress = 0
    case .resumable:
      installationExists = false
      storageAlreadyAuthorized = true
      gameStep = .pending
      gameProgress = 0
    case .recoveryRequired:
      installationExists = false
      storageAlreadyAuthorized = true
      gameStep = .attention
      gameProgress = 0
    }

    let storageStep: GameSetupStepState
    if storageAlreadyAuthorized {
      storageStep = .complete
    } else {
      switch storage {
      case .ready: storageStep = .complete
      case .insufficient: storageStep = .attention
      case .unknown: storageStep = .active
      }
    }

    let runtimeStep: GameSetupStepState
    switch runtime {
    case .ready: runtimeStep = .complete
    case .preparing, .checking: runtimeStep = .active
    case .available: runtimeStep = .pending
    case .failed, .unavailable: runtimeStep = .attention
    }

    let launchStep: GameSetupStepState
    switch launcher {
    case .ready: launchStep = installationExists ? .complete : .pending
    case .running: launchStep = .complete
    case .preparing, .stopping: launchStep = .active
    case .checking: launchStep = installationExists && runtimeStep == .complete ? .active : .pending
    case .failed, .unavailable:
      launchStep = installationExists && runtimeStep == .complete ? .attention : .pending
    }

    let stage: GameSetupStage
    if !storageAlreadyAuthorized, case .insufficient(let missingBytes) = storage {
      stage = .storageInsufficient(missingBytes: missingBytes)
    } else if !storageAlreadyAuthorized, storageStep == .active {
      stage = .checking
    } else if gameStep == .attention || runtimeStep == .attention || launchStep == .attention {
      stage = .needsAttention
    } else if installationExists, runtimeStep == .complete, launchStep == .complete {
      stage = .ready
    } else if gameStep == .active, runtimeStep == .active {
      stage = .installingGameAndRuntime
    } else if gameStep == .active {
      stage = .installingGame
    } else if runtimeStep == .active || (installationExists && runtimeStep == .pending) {
      stage = .preparingRuntime
    } else if !installationExists, storageStep == .complete {
      stage = .readyToInstall
    } else {
      stage = .checking
    }

    let fraction =
      score(storageStep) * 0.15
      + gameScore(step: gameStep, progress: gameProgress) * 0.55
      + score(runtimeStep) * 0.20
      + score(launchStep) * 0.10

    return GameSetupProgress(
      stage: stage,
      storage: storageStep,
      game: gameStep,
      runtime: runtimeStep,
      launch: launchStep,
      fraction: min(max(fraction, 0), 1)
    )
  }

  private static func score(_ state: GameSetupStepState) -> Double {
    state == .complete ? 1 : 0
  }

  private static func gameScore(step: GameSetupStepState, progress: Double) -> Double {
    switch step {
    case .complete: 1
    case .active: min(max(progress, 0), 1)
    case .pending, .attention: 0
    }
  }
}
