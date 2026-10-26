// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaperTodo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PaperTodo", targets: ["PaperTodo"])],
    targets: [
        .executableTarget(name: "PaperTodo", resources: [.copy("Resources/printer-busyboy.png"), .copy("Resources/thermal-paper.png")])
    ],
    swiftLanguageModes: [.v5]
)
