import SwiftUI
import AizuchiCore

/// The most important view in the app: two meters (system audio, microphone)
/// that tell the user, at a glance, whether the meeting's audio is actually
/// being captured. "I recorded the call and there was no sound" is the failure
/// this exists to prevent — so it also surfaces clipping and a silence warning
/// with concrete next steps, not just bars.
public struct LevelMeterView: View {
    @ObservedObject var viewModel: RecorderViewModel

    @State private var peakHoldValues: [AudioSource: Float] = [:]
    @State private var peakHoldSamples: [AudioSource: [(Date, Float)]] = [:]
    @State private var gains: [AudioSource: Float] = [.system: 1.0, .microphone: 1.0]
    @State private var muted: [AudioSource: Bool] = [:]

    public init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AudioSource.allCases) { source in
                sourceRow(source)
            }
        }
        .onChange(of: viewModel.levels) { _, newLevels in
            updatePeakHold(newLevels)
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: AudioSource) -> some View {
        let level = viewModel.levels[source] ?? .silence
        let isMuted = muted[source] ?? false

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    let newValue = !isMuted
                    muted[source] = newValue
                    viewModel.setEnabled(!newValue, for: source)
                } label: {
                    Image(systemName: isMuted ? mutedSymbol(source) : source.symbolName)
                        .foregroundStyle(isMuted ? .secondary : .primary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(isMuted ? "ミュート解除" : "ミュート")

                Text(source.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if level.isClipping {
                    Label("クリップ", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .help("音が割れています。ゲインを下げてください。")
                }
            }

            LevelBar(
                rms: level.normalizedRMS,
                peakHold: peakHoldValues[source] ?? 0,
                isClipping: level.isClipping
            )
            .opacity(isMuted ? 0.35 : 1.0)

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Slider(value: gainBinding(source), in: 0...2)
                Text(String(format: "%.1f×", gains[source] ?? 1.0))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            .disabled(isMuted)

            if viewModel.silentSources.contains(source) {
                SilenceWarningView(source: source, viewModel: viewModel)
            }
        }
    }

    private func gainBinding(_ source: AudioSource) -> Binding<Float> {
        Binding(
            get: { gains[source] ?? 1.0 },
            set: { newValue in
                gains[source] = newValue
                viewModel.setGain(newValue, for: source)
            }
        )
    }

    private func mutedSymbol(_ source: AudioSource) -> String {
        switch source {
        case .system: return "speaker.slash.fill"
        case .microphone: return "mic.slash.fill"
        }
    }

    /// Tracks the loudest peak seen in roughly the last second, per source, so
    /// `LevelBar` can draw a peak-hold tick the way a hardware meter would.
    private func updatePeakHold(_ levels: [AudioSource: AudioLevel]) {
        let now = Date()
        for source in AudioSource.allCases {
            let value = levels[source]?.normalizedPeak ?? 0
            var samples = peakHoldSamples[source] ?? []
            samples.append((now, value))
            samples.removeAll { now.timeIntervalSince($0.0) > 1.0 }
            peakHoldSamples[source] = samples
            peakHoldValues[source] = samples.map(\.1).max() ?? value
        }
    }
}

/// A single horizontal level bar: RMS fill, colored by loudness, plus a thin
/// peak-hold tick.
private struct LevelBar: View {
    var rms: Float
    var peakHold: Float
    var isClipping: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 3)
                    .fill(fillStyle)
                    .frame(width: geometry.size.width * CGFloat(max(0, min(1, rms))))
                Rectangle()
                    .fill(isClipping ? Color.red : Color.primary.opacity(0.55))
                    .frame(width: 2)
                    .offset(x: max(0, geometry.size.width * CGFloat(max(0, min(1, peakHold))) - 1))
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .animation(.easeOut(duration: 0.08), value: rms)
    }

    private var fillStyle: LinearGradient {
        if isClipping {
            return LinearGradient(colors: [.red], startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing)
    }
}

/// "録画したのに音が入っていなかった" is the failure this view exists to catch
/// before it happens: a source that has been silent for the configured threshold
/// (5s by default, see `RecorderViewModel`) while enabled gets a visible warning
/// with the likely causes and a direct path to fix them.
private struct SilenceWarningView: View {
    let source: AudioSource
    @ObservedObject var viewModel: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("音声が検出されていません", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text(causesText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle) {
                viewModel.openSystemSettings(for: source == .system ? .screenRecording : .microphone)
            }
            .font(.caption)
            .buttonStyle(.link)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var causesText: String {
        switch source {
        case .system:
            return "考えられる原因: 画面収録の権限が許可されていない・出力先の音声デバイスが違う・会議アプリ側がミュートになっている"
        case .microphone:
            return "考えられる原因: マイクの権限が許可されていない・別の入力デバイスが選ばれている・マイクがミュートになっている"
        }
    }

    private var actionTitle: String {
        source == .system ? "画面収録の権限を確認…" : "マイクの権限を確認…"
    }
}

#Preview("録画中") {
    LevelMeterView(viewModel: RecorderViewModel(controller: PreviewRecordingController.recording))
        .padding()
        .frame(width: 300)
}

#Preview("マイクが無音") {
    LevelMeterView(viewModel: RecorderViewModel(controller: PreviewRecordingController.silentMicrophone, silenceThreshold: 0))
        .padding()
        .frame(width: 300)
}
