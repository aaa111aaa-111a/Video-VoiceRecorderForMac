// swift-tools-version: 5.9
// OptiRecord - meeting recorder for Apple Silicon Macs.
import PackageDescription

let package = Package(
    name: "OptiRecord",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OptiRecord", targets: ["OptiRecordApp"]),
        .library(name: "OptiRecordKit", targets: ["OptiRecordCore", "OptiRecordAudio", "OptiRecordCapture", "OptiRecordRecording", "OptiRecordUI"])
    ],
    targets: [
        // Domain models, protocol contracts, settings, pure helpers.
        // Every other module codes against this one.
        .target(name: "OptiRecordCore"),

        // Format conversion, timeline-aligned mixing, level metering.
        .target(name: "OptiRecordAudio", dependencies: ["OptiRecordCore"]),

        // ScreenCaptureKit / AVFoundation capture + TCC permissions.
        .target(name: "OptiRecordCapture", dependencies: ["OptiRecordCore", "OptiRecordAudio"]),

        // AVAssetWriter pipeline and the coordinator that wires everything together.
        .target(name: "OptiRecordRecording", dependencies: ["OptiRecordCore", "OptiRecordAudio", "OptiRecordCapture"]),

        // SwiftUI views, view models, menu bar UI.
        .target(name: "OptiRecordUI", dependencies: ["OptiRecordCore", "OptiRecordRecording"]),

        // Executable entry point. Bundled into OptiRecord.app by Scripts/build-app.sh.
        .executableTarget(name: "OptiRecordApp", dependencies: ["OptiRecordUI", "OptiRecordRecording", "OptiRecordCapture"]),

        .testTarget(name: "OptiRecordCoreTests", dependencies: ["OptiRecordCore"]),
        .testTarget(name: "OptiRecordAudioTests", dependencies: ["OptiRecordAudio", "OptiRecordCore"]),
        .testTarget(name: "OptiRecordCaptureTests", dependencies: ["OptiRecordCapture", "OptiRecordCore"]),
        .testTarget(name: "OptiRecordRecordingTests", dependencies: ["OptiRecordRecording", "OptiRecordCore"]),
        .testTarget(name: "OptiRecordUITests", dependencies: ["OptiRecordUI", "OptiRecordCore"])
    ]
)
