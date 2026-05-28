// swift-tools-version: 6.0

import PackageDescription

let arrowIncludePaths = [
    "-I/opt/homebrew/include",
    "-I/opt/homebrew/opt/apache-arrow/include",
    "-I/usr/local/include",
    "-I/usr/local/opt/apache-arrow/include"
]

let arrowLibraryPaths = [
    "-L/opt/homebrew/lib",
    "-L/opt/homebrew/opt/apache-arrow/lib",
    "-L/usr/local/lib",
    "-L/usr/local/opt/apache-arrow/lib"
]

let package = Package(
    name: "ParquetPeek",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ParquetPeek", targets: ["ParquetPeek"]),
        .executable(name: "ParquetPeekSelfTests", targets: ["ParquetPeekSelfTests"])
    ],
    targets: [
        .executableTarget(
            name: "ParquetPeek",
            dependencies: ["ParquetPeekCore", "CParquetBridge"]
        ),
        .target(
            name: "ParquetPeekCore"
        ),
        .target(
            name: "CParquetBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-std=c++20"] + arrowIncludePaths)
            ],
            linkerSettings: [
                .unsafeFlags(arrowLibraryPaths + ["-larrow", "-lparquet"])
            ]
        ),
        .executableTarget(
            name: "ParquetPeekSelfTests",
            dependencies: ["ParquetPeekCore"]
        )
    ],
    cxxLanguageStandard: .cxx20
)
