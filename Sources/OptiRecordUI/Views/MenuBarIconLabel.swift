import SwiftUI
import OptiRecordCore

/// The menu bar item's icon. The one thing this app must never hide: whether it
/// is recording right now. Idle is an outline `record.circle`; recording is a
/// solid red `record.circle.fill`, matched by macOS's own convention for "this is
/// live" (Voice Memos, screen recording, etc).
public struct MenuBarIconLabel: View {
    public let state: RecordingState

    public init(state: RecordingState) {
        self.state = state
    }

    public var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }

    private var symbolName: String {
        switch state {
        case .idle, .preparing: return "record.circle"
        case .recording: return "record.circle.fill"
        case .paused: return "pause.circle.fill"
        case .finishing: return "square.and.arrow.up.circle"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .recording: return .red
        case .paused: return .orange
        case .failed: return .red
        case .idle, .preparing, .finishing: return .primary
        }
    }
}

#Preview("待機中") {
    MenuBarIconLabel(state: .idle)
        .font(.system(size: 22))
        .padding()
}

#Preview("録画中") {
    MenuBarIconLabel(state: .recording)
        .font(.system(size: 22))
        .padding()
}
