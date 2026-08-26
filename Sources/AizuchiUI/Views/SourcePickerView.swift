import SwiftUI
import AizuchiCore

/// Lets the user choose what to record: a running meeting app, a whole display,
/// or a single window. "会議アプリ" is the default tab because it is almost
/// always the right answer and needs zero disambiguation from the user.
public struct SourcePickerView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var tab: Tab = .meetingApps

    public init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("録画対象の種類", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            content
                .frame(minHeight: 140, maxHeight: 240)

            if let selected = viewModel.selectedTarget, isBrowserTarget(selected) {
                browserNotice
            }

            HStack {
                Spacer()
                Button {
                    Task { await viewModel.refreshAvailableContent() }
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await viewModel.refreshAvailableContent() }
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case meetingApps, displays, windows
        var id: String { rawValue }
        var title: String {
            switch self {
            case .meetingApps: return "会議アプリ"
            case .displays: return "画面"
            case .windows: return "ウインドウ"
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .meetingApps: meetingAppsList
        case .displays: displaysList
        case .windows: windowsList
        }
    }

    private var meetingAppsList: some View {
        let apps = viewModel.availableContent.meetingApplications
        return Group {
            if apps.isEmpty {
                emptyState(text: "起動中の会議アプリが見つかりません。Zoom や Teams を起動するか、ブラウザで会議を開いてください。")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(apps) { app in
                            let isBrowser = MeetingAppCatalog.match(bundleIdentifier: app.id)?.isBrowser ?? false
                            selectableRow(
                                title: app.name,
                                subtitle: "\(app.windowCount) ウインドウ",
                                systemImage: isBrowser ? "globe" : "app.badge.checkmark",
                                isSelected: isSelected(applicationTarget(for: app.id))
                            ) {
                                viewModel.selectedTarget = applicationTarget(for: app.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var displaysList: some View {
        let displays = viewModel.availableContent.displays
        return Group {
            if displays.isEmpty {
                emptyState(text: "画面情報を取得できません。画面収録の権限を確認してください。")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(displays) { display in
                            selectableRow(
                                title: display.name,
                                subtitle: "\(display.width)×\(display.height)" + (display.isMain ? "・メイン" : ""),
                                systemImage: "display",
                                isSelected: isSelected(.display(id: display.id))
                            ) {
                                viewModel.selectedTarget = .display(id: display.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var windowsList: some View {
        let windows = viewModel.availableContent.windows.filter { $0.isOnScreen }
        return Group {
            if windows.isEmpty {
                emptyState(text: "録画できるウインドウが見つかりません。")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(windows) { window in
                            selectableRow(
                                title: window.title.isEmpty ? window.applicationName : window.title,
                                subtitle: window.applicationName,
                                systemImage: "macwindow",
                                isSelected: isSelected(.window(id: window.id))
                            ) {
                                viewModel.selectedTarget = .window(id: window.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func selectableRow(title: String, subtitle: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applicationTarget(for bundleIdentifier: String) -> CaptureTarget {
        .application(bundleIdentifier: bundleIdentifier, displayID: viewModel.availableContent.mainDisplay?.id ?? 0)
    }

    private func isSelected(_ target: CaptureTarget) -> Bool {
        viewModel.selectedTarget == target
    }

    private func isBrowserTarget(_ target: CaptureTarget) -> Bool {
        if case .application(let bundleIdentifier, _) = target {
            return MeetingAppCatalog.match(bundleIdentifier: bundleIdentifier)?.isBrowser ?? false
        }
        return false
    }

    private var browserNotice: some View {
        Label("Google Meet はブラウザのタブなので、ブラウザ全体の音が入ります。", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    SourcePickerView(viewModel: RecorderViewModel(controller: PreviewRecordingController.idle))
        .padding()
        .frame(width: 340)
}
