// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Folium",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Folium", targets: ["Folium"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm")
    ],
    targets: [
        .executableTarget(
            name: "Folium",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark")
            ],
            resources: [
                // Vendored by scripts/vendor-highlightjs.sh (`make vendor`),
                // gitignored — see that script and vendor/package.json.
                .copy("Vendor/HighlightJS"),
                // First-party CSS/JS, committed directly.
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "FoliumTests",
            dependencies: ["Folium"]
        ),
        .testTarget(
            name: "FoliumIntegrationTests",
            dependencies: ["Folium"],
            resources: [.copy("Fixtures")]
        )
    ]
)
