// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "StubRecorder",
	platforms: [
		.macOS(.v12),
		.iOS(.v14)
	],
    products: [
        .library(
            name: "StubRecorder",
            targets: ["StubRecorder"]
        ),
    ],
    dependencies: [
		.package(url: "git@github.com:engenious-inc/swift-proxy.git", .upToNextMajor(from: "1.0.0")),
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "StubRecorder",
            dependencies: [
				.product(name: "SwiftProxy", package: "swift-proxy"),
			]
        ),
        .testTarget(
            name: "StubRecorderTest",
            dependencies: ["StubRecorder"]
        ),
    ]
)
