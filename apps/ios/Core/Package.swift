// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Core",
  // `Synchronization.Atomic` (WarmthRenderCore's lock-free dial handoff) needs
  // macOS 15 / iOS 18. Without an explicit iOS floor SPM builds this at iOS 12
  // when the app links it, so the floor must be stated. The app itself deploys
  // iOS 26.5, comfortably above.
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "Core",
      targets: ["Core"]
    )
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "Core"
    ),
    .testTarget(
      name: "CoreTests",
      dependencies: ["Core"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
