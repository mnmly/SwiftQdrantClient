// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftQdrantClient",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "QdrantClient", targets: ["QdrantClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", exact: "1.27.5"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        // Generated SwiftProtobuf message types + gRPC service clients.
        // Code is pre-generated from `protos/*.proto` and committed under Generated/.
        .target(
            name: "QdrantProtos",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPC", package: "grpc-swift"),
            ],
            path: "Sources/QdrantProtos",
            exclude: ["protos"]
        ),
        // High-level Swift client: REST + gRPC transports, models, local mode.
        .target(
            name: "QdrantClient",
            dependencies: ["QdrantProtos"],
            path: "Sources/QdrantClient"
        ),
        .testTarget(
            name: "QdrantClientTests",
            dependencies: ["QdrantClient"],
            path: "Tests/QdrantClientTests"
        ),
    ]
)
