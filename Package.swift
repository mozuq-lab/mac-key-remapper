// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyRemapper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KeyRemapper", targets: ["KeyRemapper"]),
    ],
    targets: [
        // 設定ファイルの読み込みと、キーの置き換えの適用（IOKit）
        .target(name: "KeyRemapperCore"),
        // メニューバー常駐アプリ
        .executableTarget(name: "KeyRemapper", dependencies: ["KeyRemapperCore"]),
        .testTarget(name: "KeyRemapperCoreTests", dependencies: ["KeyRemapperCore"]),
    ]
)
