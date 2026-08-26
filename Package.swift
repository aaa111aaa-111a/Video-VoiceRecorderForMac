// swift-tools-version: 5.9
// Aizuchi - meeting recorder for Apple Silicon Macs.
import PackageDescription

let package = Package(
    name: "Aizuchi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Aizuchi", targets: ["AizuchiApp"]),
        .library(name: "AizuchiKit", targets: ["AizuchiCore", "AizuchiAudio", "AizuchiCapture", "AizuchiRecording", "AizuchiUI"])
    ],
    targets: [
        // Domain models, protocol contracts, settings, pure helpers.
        // Every other module codes against this one.
        .target(name: "AizuchiCore"),

        // Format conversion, timeline-aligned mixing, level metering.
        .target(name: "AizuchiAudio", dependencies: ["AizuchiCore"]),

        // ScreenCaptureKit / AVFoundation capture + TCC permissions.
        .target(name: "AizuchiCapture", dependencies: ["AizuchiCore", "AizuchiAudio"]),

        // AVAssetWriter pipeline and the coordinator that wires everything together.
        .target(name: "AizuchiRecording", dependencies: ["AizuchiCore", "AizuchiAudio", "AizuchiCapture"]),

        // SwiftUI views, view models, menu bar UI.
        .target(name: "AizuchiUI", dependencies: ["AizuchiCore", "AizuchiRecording"]),

        // Executable entry point. Bundled into Aizuchi.app by Scripts/build-app.sh.
        .executableTarget(name: "AizuchiApp", dependencies: ["AizuchiUI", "AizuchiRecording", "AizuchiCapture"]),

        .testTarget(name: "AizuchiCoreTests", dependencies: ["AizuchiCore"]),
        .testTarget(name: "AizuchiAudioTests", dependencies: ["AizuchiAudio", "AizuchiCore"]),
        .testTarget(name: "AizuchiCaptureTests", dependencies: ["AizuchiCapture", "AizuchiCore"]),
        .testTarget(name: "AizuchiRecordingTests", dependencies: ["AizuchiRecording", "AizuchiCore"]),
        .testTarget(name: "AizuchiUITests", dependencies: ["AizuchiUI", "AizuchiCore"])
    ]
)
