import Foundation
import Testing

@testable import ManifestSamplingCore

struct StrictJSONSchemaScannerTests {
  @Test
  func matchesKnownFingerprintVectorAndRedactsReflection() throws {
    let canary = "sensitive-branch-canary"
    let input = Data(
      """
      {"retcode":0,"data":{"game_branches":[{"branch":"\(canary)","future":{"n":1}},{"branch":"other"}]}}
      """.utf8
    )

    let result = try StrictJSONSchemaScanner.scan(input)

    #expect(result.policyVersion == 1)
    #expect(result.sha256 == "adce2c614ac3a7ce46cf83c298e354608c34dc83ece04b86801107726fe2198a")
    #expect(result.gameBranchEntryCount == 2)
    #expect(!isDecodable(JSONValueFreeShape.self))
    var dumped = ""
    dump(result, to: &dumped)
    #expect(result.description == "<redacted>")
    #expect(result.debugDescription == "<redacted>")
    #expect(Mirror(reflecting: result).children.first?.label == "redacted")
    #expect(!dumped.contains(canary))
  }

  @Test
  func objectAndArrayPermutationsHaveStableFingerprint() throws {
    let first = data(
      """
      {"retcode":0,"message":"ok","data":{"game_branches":[{"branch":"a","tag":1},{"main":true}]}}
      """
    )
    let permuted = data(
      """
      {"data":{"game_branches":[{"main":false},{"tag":99,"branch":"b"}]},"message":"changed","retcode":0}
      """
    )

    #expect(
      try StrictJSONSchemaScanner.scan(first).sha256
        == StrictJSONSchemaScanner.scan(permuted).sha256
    )
  }

  @Test
  func preservesFieldCorrelationWithinArrayElementShapes() throws {
    let split = data(
      #"{"retcode":0,"data":{"game_branches":[{"main":{}},{"pre_download":{}}]}}"#
    )
    let merged = data(
      #"{"retcode":0,"data":{"game_branches":[{"main":{},"pre_download":{}},{}]}}"#
    )

    let splitShape = try StrictJSONSchemaScanner.scan(split)
    let mergedShape = try StrictJSONSchemaScanner.scan(merged)
    #expect(splitShape.gameBranchEntryCount == 2)
    #expect(mergedShape.gameBranchEntryCount == 2)
    #expect(splitShape.sha256 != mergedShape.sha256)
  }

  @Test
  func scalarValuesAndLengthsDoNotEnterFingerprint() throws {
    let first = data(
      """
      {"retcode":0,"data":{"game_branches":[]},"future":{"text":"a","number":1,"flag":true,"nothing":null}}
      """
    )
    let changed = data(
      """
      {"retcode":0,"data":{"game_branches":[]},"future":{"text":"a much longer secret","number":-12.50e+2,"flag":false,"nothing":null}}
      """
    )

    #expect(
      try StrictJSONSchemaScanner.scan(first).sha256
        == StrictJSONSchemaScanner.scan(changed).sha256
    )
  }

  @Test
  func arrayShapeIgnoresMultiplicityAndCountsRemainSeparate() throws {
    let empty = try StrictJSONSchemaScanner.scan(
      data(#"{"retcode":0,"data":{"game_branches":[]},"future_a":null}"#))
    let one = try StrictJSONSchemaScanner.scan(
      data(#"{"retcode":0,"data":{"game_branches":[null]},"future_a":null}"#))
    let two = try StrictJSONSchemaScanner.scan(
      data(#"{"retcode":0,"data":{"game_branches":[null,null]},"future_a":null}"#))
    let renamed = try StrictJSONSchemaScanner.scan(
      data(#"{"retcode":0,"data":{"game_branches":[]},"future_b":null}"#))

    #expect(empty.sha256 != one.sha256)
    #expect(one.sha256 == two.sha256)
    #expect(empty.sha256 != renamed.sha256)
    #expect(empty.gameBranchEntryCount == 0)
    #expect(one.gameBranchEntryCount == 1)
    #expect(two.gameBranchEntryCount == 2)
  }

  @Test
  func rejectsDecodedDuplicateKeysAtEveryObjectDepth() {
    let candidates = [
      #"{"retcode":0,"retcode":0,"data":{"game_branches":[]}}"#,
      #"{"retcode":0,"data":{"game_branches":[],"game\u005fbranches":[]}}"#,
      #"{"retcode":0,"data":{"game_branches":[]},"future":{"a":1,"\u0061":2}}"#,
      #"{"retcode":0,"data":{"game_branches":[]},"future":{"\uD83D\uDE00":1,"😀":2}}"#,
    ]

    for candidate in candidates {
      #expect(throws: ManifestSamplingError.duplicateJSONKey) {
        try StrictJSONSchemaScanner.scan(data(candidate))
      }
    }
  }

  @Test
  func rejectsMalformedRFC8259AndInvalidRequiredAnchors() {
    var invalidUTF8 = Data(#"{"retcode":0,"data":{"game_branches":[]},"x":""#.utf8)
    invalidUTF8.append(0xFF)
    invalidUTF8.append(contentsOf: Data(#""}"#.utf8))

    let candidates: [Data] = [
      Data(),
      data("[]"),
      data(#"{"data":{"game_branches":[]}}"#),
      data(#"{"retcode":0,"data":{}}"#),
      data(#"{"retcode":1,"data":{"game_branches":[]}}"#),
      data(#"{"retcode":-0,"data":{"game_branches":[]}}"#),
      data(#"{"retcode":0.0,"data":{"game_branches":[]}}"#),
      data(#"{"retcode":"0","data":{"game_branches":[]}}"#),
      data(#"{"retcode":0,"data":[]}"#),
      data(#"{"retcode":0,"data":{"game_branches":{}}}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":01}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":1.}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":1e}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":+1}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":"\x"}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":"\uDC00"}"#),
      data(#"{"retcode":0,"data":{"game_branches":[]},"x":"\uD800"}"#),
      data("{\"retcode\":0,\"data\":{\"game_branches\":[]},\"x\":\"\n\"}"),
      data(#"{"retcode":0,"data":{"game_branches":[]}} trailing"#),
      invalidUTF8,
    ]

    for candidate in candidates {
      #expect(throws: ManifestSamplingError.malformedJSON) {
        try StrictJSONSchemaScanner.scan(candidate)
      }
    }
  }

  @Test
  func acceptsRFC8259WhitespaceEscapesNumbersAndLiterals() throws {
    let input = data(
      #"""
        {
          "retcode" : 0,
          "data" : { "game_branches" : [] },
          "escaped" : "\"\\\/\b\f\n\r\t\u0061\uD83D\uDE00",
          "numbers" : [-1, 2.5, 6.02e23, 1E-2],
          "literals" : [true, false, null]
        }
      """#
    )

    #expect(try StrictJSONSchemaScanner.scan(input).sha256.count == 64)
  }

  @Test
  func enforcesDepthAndNodeLimitsAtExactBoundaries() throws {
    let exactDepth = requiredJSON(extraValue: nestedArrays(14))
    let excessiveDepth = requiredJSON(extraValue: nestedArrays(15))
    #expect(try StrictJSONSchemaScanner.scan(exactDepth).sha256.count == 64)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scan(excessiveDepth)
    }

    let exactNodes = requiredJSON(
      extraValue: "[" + Array(repeating: "null", count: 16_379).joined(separator: ",") + "]"
    )
    let excessiveNodes = requiredJSON(
      extraValue: "[" + Array(repeating: "null", count: 16_380).joined(separator: ",") + "]"
    )
    #expect(try StrictJSONSchemaScanner.scan(exactNodes).sha256.count == 64)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scan(excessiveNodes)
    }
  }

  @Test
  func enforcesNumberTokenLimitAtExactBoundary() throws {
    let exact = requiredJSON(extraValue: String(repeating: "1", count: 128))
    let excessive = requiredJSON(extraValue: String(repeating: "1", count: 129))

    #expect(try StrictJSONSchemaScanner.scan(exact).sha256.count == 64)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scan(excessive)
    }
  }

  @Test
  func invokesInjectedCancellationInsideLongStringsAndNumbers() {
    let stringProbe = CancellationProbe(cancelOnCall: 5)
    #expect(throws: CancellationError.self) {
      try StrictJSONSchemaScanner.scan(
        requiredJSON(extraValue: quotedString(byteCount: 65_536)),
        cancellationCheck: stringProbe.check
      )
    }

    let numberProbe = CancellationProbe(cancelOnCall: 3)
    #expect(throws: CancellationError.self) {
      try StrictJSONSchemaScanner.scan(
        requiredJSON(extraValue: String(repeating: "1", count: 128)),
        cancellationCheck: numberProbe.check
      )
    }
  }

  @Test
  func enforcesInputAndDecodedStringLimitsAtExactBoundaries() throws {
    let base = data(#"{"retcode":0,"data":{"game_branches":[]}}"#)
    var exactInput = base
    exactInput.append(Data(repeating: 0x20, count: 1_048_576 - exactInput.count))
    #expect(try StrictJSONSchemaScanner.scan(exactInput).sha256.count == 64)
    var excessiveInput = exactInput
    excessiveInput.append(0x20)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scan(excessiveInput)
    }

    let exactSingle = requiredJSON(extraValue: quotedString(byteCount: 65_536))
    let excessiveSingle = requiredJSON(extraValue: quotedString(byteCount: 65_537))
    #expect(try StrictJSONSchemaScanner.scan(exactSingle).sha256.count == 64)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scan(excessiveSingle)
    }

    let exactTotal = requiredJSON(
      extraValue: totalStringArray(finalStringByteCount: 65_511)
    )
    let excessiveTotal = requiredJSON(
      extraValue: totalStringArray(finalStringByteCount: 65_512)
    )
    #expect(try StrictJSONSchemaScanner.scan(exactTotal).sha256.count == 64)
    #expect(throws: ManifestSamplingError.resourceLimit) {
      try StrictJSONSchemaScanner.scan(excessiveTotal)
    }
  }
}

private func data(_ value: String) -> Data {
  Data(value.utf8)
}

private func requiredJSON(extraValue: String) -> Data {
  data(#"{"retcode":0,"data":{"game_branches":[]},"x":\#(extraValue)}"#)
}

private func nestedArrays(_ count: Int) -> String {
  String(repeating: "[", count: count) + "null" + String(repeating: "]", count: count)
}

private func quotedString(byteCount: Int) -> String {
  "\"" + String(repeating: "a", count: byteCount) + "\""
}

private func totalStringArray(finalStringByteCount: Int) -> String {
  let full = Array(repeating: quotedString(byteCount: 65_536), count: 7)
  return "[" + (full + [quotedString(byteCount: finalStringByteCount)]).joined(separator: ",") + "]"
}

private func isDecodable<T>(_ type: T.Type) -> Bool {
  type is any Decodable.Type
}

private final class CancellationProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let cancelOnCall: Int
  private var calls = 0

  init(cancelOnCall: Int) {
    self.cancelOnCall = cancelOnCall
  }

  func check() throws {
    lock.lock()
    defer { lock.unlock() }
    calls += 1
    if calls == cancelOnCall {
      throw CancellationError()
    }
  }
}
