import Foundation
import Testing

@testable import BridgeStatus

@Suite("GPTK early crash recovery")
struct GPTKEarlyCrashDetectorTests {
  @Test("recognizes the observed GPTK D3D11 startup crash")
  func recognizesObservedCrash() {
    #expect(
      GPTKEarlyCrashDetector.matches(
        outputLog: """
          GfxDevice: creating device client; threaded=1
          Direct3D:
              Version: Direct3D 11.0 [level 11.1]
              Renderer: AMD Compatibility Mode (ID=0x66af)
          **** Crash! ****
          """,
        runDuration: 8
      ))
  }

  @Test("does not treat normal startup or a late crash as the GPTK startup failure")
  func rejectsUnrelatedRuns() {
    let normalLog = """
      GfxDevice: creating device client; threaded=1
      Direct3D:
          Renderer: AMD Compatibility Mode (ID=0x66af)
      """
    #expect(!GPTKEarlyCrashDetector.matches(outputLog: normalLog, runDuration: 8))

    let crashLog = normalLog + "\n**** Crash! ****\n"
    #expect(
      !GPTKEarlyCrashDetector.matches(
        outputLog: crashLog,
        runDuration: GPTKEarlyCrashDetector.startupWindow + 1
      ))
  }

  @Test("fallback preferences preserve every user choice except the backend")
  func preservesPreferences() {
    let original = GameLaunchPreferences(
      graphicsBackend: .gptk4,
      windowMode: .fullScreen,
      resolution: .large,
      graphicsProfile: .preserve,
      textLanguage: .english,
      voiceLanguage: .japanese,
      hideAfterLaunch: false,
      fpsUnlockMode: .fps120,
      detailedWineLoggingEnabled: true,
      metalHUDEnabled: true,
      automaticDXMTFallbackEnabled: false
    )

    let fallback = original.usingGraphicsBackend(.dxmt)

    #expect(fallback.graphicsBackend == .dxmt)
    #expect(fallback.windowMode == original.windowMode)
    #expect(fallback.resolution == original.resolution)
    #expect(fallback.graphicsProfile == original.graphicsProfile)
    #expect(fallback.textLanguage == original.textLanguage)
    #expect(fallback.voiceLanguage == original.voiceLanguage)
    #expect(fallback.hideAfterLaunch == original.hideAfterLaunch)
    #expect(fallback.fpsUnlockMode == original.fpsUnlockMode)
    #expect(fallback.detailedWineLoggingEnabled == original.detailedWineLoggingEnabled)
    #expect(fallback.metalHUDEnabled == original.metalHUDEnabled)
    #expect(fallback.automaticDXMTFallbackEnabled == original.automaticDXMTFallbackEnabled)
  }
}
