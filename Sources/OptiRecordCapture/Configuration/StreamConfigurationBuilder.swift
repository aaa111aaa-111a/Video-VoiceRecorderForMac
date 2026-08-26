import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import OptiRecordCore

/// Builds the `SCStreamConfiguration` ScreenCaptureKit needs from our own
/// `RecordingConfiguration`.
///
/// `SCStreamConfiguration` can be constructed and inspected without screen-recording
/// permission, so this is kept as a pure function and is fully unit tested directly
/// (`StreamConfigurationBuilderTests`) rather than only through a live stream.
enum StreamConfigurationBuilder {
    static func makeConfiguration(from configuration: RecordingConfiguration, microphoneDeviceID: String?) -> SCStreamConfiguration {
        let streamConfiguration = SCStreamConfiguration()

        // Core already clamps these to even numbers within the encoder's supported
        // range; this layer just carries them through unchanged.
        streamConfiguration.width = configuration.width
        streamConfiguration.height = configuration.height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        streamConfiguration.queueDepth = 6
        streamConfiguration.showsCursor = configuration.showsCursor

        // 32BGRA is the compatibility-first pixel format: every downstream consumer
        // (Core Image, AVFoundation, our own writer) understands it directly, no
        // bi-planar handling required. kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        // ("420v") is roughly half the memory bandwidth and maps onto the hardware
        // encoder's native input format, which would cut CPU/GPU copy cost — worth
        // revisiting if capture becomes a bottleneck on base M1 hardware.
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.colorSpaceName = CGColorSpace.sRGB

        streamConfiguration.capturesAudio = configuration.capturesSystemAudio
        streamConfiguration.excludesCurrentProcessAudio = configuration.excludesOwnAudio
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2

        // Never letterbox/crop to force-fit width x height; keep the source's aspect
        // ratio (Core already computed width/height to match it).
        streamConfiguration.scalesToFit = false

        if #available(macOS 15.0, *) {
            if configuration.capturesMicrophone {
                streamConfiguration.captureMicrophone = true
                if let microphoneDeviceID {
                    streamConfiguration.microphoneCaptureDeviceID = microphoneDeviceID
                }
                // A `nil` microphoneDeviceID leaves ScreenCaptureKit on the system
                // default input device, mirroring `MicrophoneCapturing.start(deviceUID:
                // nil)`'s "system default" convention.
            }
        }
        // On macOS 14, `configuration.capturesMicrophone` is honored instead by
        // `AVCaptureMicrophoneCapturer`, started alongside this stream by the
        // coordinator — `SCStream` never receives microphone audio pre-15.

        return streamConfiguration
    }
}
