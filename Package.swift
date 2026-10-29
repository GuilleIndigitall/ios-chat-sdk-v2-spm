// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IndigitallChatSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "IndigitallChatSDK", targets: ["IndigitallChatSDK"])
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.1.1"),

    ],
    targets: [
        .target(
            name: "ChatCore",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ]
        ),
        .target(
            name: "ChatUI",
            dependencies: [
                "ChatCore",
                "IndigitallFoundation",
                "IndigitallModels",
                "IndigitallDesign",
                "IndigitallMultimedia",
                "IndigitallUI"
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "IndigitallChatSDK", dependencies: ["ChatCore", "ChatUI"]),
        .testTarget(name: "ChatCoreTests", dependencies: ["ChatCore"]),
        .binaryTarget(
            name: "IndigitallFoundation",
            url: "https://storage.googleapis.com/indigitall-public-assets/sdk/ios/ios-chat-kit/0.1.4/SPM/IndigitallFoundation.xcframework.zip",
            checksum: "d9e19fa615b0b4ff1aa1989cb35e264991acd05aaed76cc8e9b24cea191f53d8"
        ),
        .binaryTarget(
            name: "IndigitallModels",
            url: "https://storage.googleapis.com/indigitall-public-assets/sdk/ios/ios-chat-kit/0.1.4/SPM/IndigitallModels.xcframework.zip",
            checksum: "ac842ccae838981254113afc4360ed4ad4d2061377534af1ad4ca5362a991398"
        ),
        .binaryTarget(
            name: "IndigitallDesign",
            url: "https://storage.googleapis.com/indigitall-public-assets/sdk/ios/ios-chat-kit/0.1.4/SPM/IndigitallDesign.xcframework.zip",
            checksum: "d386266d6ac5a8b346956758c901acd8f71315fb321a8e3496d0beea639f5328"
        ),
        .binaryTarget(
            name: "IndigitallMultimedia",
            url: "https://storage.googleapis.com/indigitall-public-assets/sdk/ios/ios-chat-kit/0.1.4/SPM/IndigitallMultimedia.xcframework.zip",
            checksum: "d3c6393b53da3ac2a95278d3f9e26e86a7caae053d6ea38f8dd4f8b6a26865f2"
        ),
        .binaryTarget(
            name: "IndigitallUI",
            url: "https://storage.googleapis.com/indigitall-public-assets/sdk/ios/ios-chat-kit/0.1.4/SPM/IndigitallUI.xcframework.zip",
            checksum: "55ff89c822052e8a22ca4fd977d066f5dee0bf94f9a4dd4219a7a4b7d06fe069"
        )
    ],
    swiftLanguageModes: [.v5]
)
