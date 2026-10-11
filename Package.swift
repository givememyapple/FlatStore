// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FlatStore",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .executable(name: "FlatStore", targets: ["FlatStore"])
    ],
    dependencies: [
        .package(url: "https://github.com/rhx/gir2swift.git", branch: "main"),
        .package(url: "https://github.com/rhx/SwiftGtk.git", branch: "gtk3"),
        .package(url: "https://github.com/rhx/SwiftGdkPixbuf.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "FlatStore",
            dependencies: [
                .product(name: "Gtk", package: "SwiftGtk"),
                .product(name: "GdkPixBuf", package: "SwiftGdkPixbuf"),
            ]
        )
    ]
)
