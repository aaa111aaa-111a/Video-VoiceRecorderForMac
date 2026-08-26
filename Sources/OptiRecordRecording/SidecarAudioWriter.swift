import AVFoundation
import CoreMedia
import OptiRecordCore

/// One audio-only `.m4a` next to the video, holding a single source unmixed.
///
/// The point is transcription: Whisper and friends do far better on a clean microphone
/// track and a clean system track than on a mix where both speakers overlap. Optional,
/// off by default, because it costs a second AAC encode.
final class SidecarAudioWriter {
    let source: AudioSource
    let url: URL

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var sessionStarted = false
    private var lastPresentationTime: CMTime = .invalid
    private(set) var isFinished = false

    init(source: AudioSource, url: URL, audioSettings: [String: Any]) throws {
        self.source = source
        self.url = url
        try? FileManager.default.removeItem(at: url)
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        } catch {
            throw RecorderError.writerSetupFailed(error.localizedDescription)
        }
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecorderError.writerSetupFailed("\(source.localizedName)の音声トラックを追加できません")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecorderError.writerSetupFailed(writer.error?.localizedDescription ?? "書き出しを開始できません")
        }
    }

    /// Not thread-safe on its own; `AssetWriterMediaWriter` serializes access.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard !isFinished, writer.status == .writing else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return }

        if !sessionStarted {
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }
        // AVAssetWriterInput rejects the whole file if timestamps ever go backwards.
        if lastPresentationTime.isValid, presentationTime <= lastPresentationTime { return }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) {
            lastPresentationTime = presentationTime
        }
    }

    func finish() async {
        guard !isFinished else { return }
        isFinished = true
        guard sessionStarted, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }
}
