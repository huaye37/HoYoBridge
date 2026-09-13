// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MacGameBridge",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "BridgeCore", targets: ["BridgeCore"]),
    .executable(name: "bridge-probe", targets: ["BridgeProbe"]),
    .executable(name: "bridge-catalog", targets: ["BridgeCatalog"]),
    .executable(name: "bridge-manifest-sample", targets: ["BridgeManifestSample"]),
    .executable(name: "MacGameBridge", targets: ["BridgeStatus"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    .package(
      url: "https://github.com/apple/swift-protobuf.git",
      exact: "1.38.1"
    ),
    .package(
      url: "https://github.com/facebook/zstd.git",
      exact: "1.5.7"
    ),
  ],
  targets: [
    .target(
      name: "CZstdBridge",
      dependencies: [.product(name: "libzstd", package: "zstd")],
      publicHeadersPath: "include"
    ),
    .target(
      name: "BridgeCore",
      dependencies: [
        "CZstdBridge",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ],
      plugins: [
        .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")
      ]
    ),
    .executableTarget(name: "BridgeProbe", dependencies: ["BridgeCore"]),
    .executableTarget(name: "BridgeCatalog", dependencies: ["BridgeCore"]),
    .target(name: "ManifestSamplingCore"),
    .executableTarget(
      name: "BridgeManifestSample",
      dependencies: ["ManifestSamplingCore", "BridgeCore"]
    ),
    .executableTarget(
      name: "BridgeStatus", dependencies: ["BridgeCore", .product(name: "Sparkle", package: "Sparkle")],
      resources: [.process("Resources")],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    .target(
      name: "CZstdTestSupport",
      dependencies: [.product(name: "libzstd", package: "zstd")],
      path: "Tests/CZstdTestSupport",
      publicHeadersPath: "include",
      cSettings: [.define("ZSTD_STATIC_LINKING_ONLY")]
    ),
    .testTarget(
      name: "BridgeCoreTests",
      dependencies: [
        "BridgeCore",
        "CZstdBridge",
        "CZstdTestSupport",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
      ]
    ),
    .testTarget(
      name: "ManifestSamplingCoreTests",
      dependencies: ["ManifestSamplingCore"]
    ),
    .testTarget(name: "BridgeStatusTests", dependencies: ["BridgeStatus"]),
  ]
)
