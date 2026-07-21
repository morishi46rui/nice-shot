// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiceShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NiceShot",
            path: "Sources/NiceShot",
            swiftSettings: [
                // MVP 段階では厳格な並行性チェックを避けて Swift 5 モードでビルドする
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
