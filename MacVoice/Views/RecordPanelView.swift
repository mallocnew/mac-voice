import AppKit
import SwiftUI

struct RecordPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        RecordPanelContent(
            appState: appState,
            recorder: appState.recorder,
            allSceneRecorder: appState.allSceneRecorder
        )
    }
}

private struct RecordPanelContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var allSceneRecorder: AllSceneRecorder

    private var isAllScene: Bool { appState.recordingMode == .allScene }
    private var activeIsRecording: Bool {
        isAllScene ? allSceneRecorder.isRecording : recorder.isRecording
    }
    private var activeElapsed: String {
        isAllScene ? allSceneRecorder.elapsedLabel : recorder.elapsedLabel
    }

    var body: some View {
        VStack(spacing: 18) {
            modePicker

            ZStack {
                Circle()
                    .fill(activeIsRecording
                          ? Color.red.opacity(0.12)
                          : Color.primary.opacity(0.04))
                    .frame(width: 120, height: 120)

                Image(systemName: "mic.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(activeIsRecording ? Color.red : Color.accentColor)
            }

            Text(activeIsRecording ? activeElapsed : recordIdleTitle)
                .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(activeIsRecording
                 ? "停止后可转写或导出录音文件"
                 : "录音保存为 m4a（16kHz 单声道），并记入当前会话")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if activeIsRecording {
                    Button {
                        appState.stopRecording(transcribeAfter: false)
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        appState.stopRecording(transcribeAfter: true)
                    } label: {
                        Label("停止并转写", systemImage: "text.bubble")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!appState.hasSavedKey)

                    Button("取消") {
                        appState.cancelRecording()
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        appState.startRecording()
                    } label: {
                        Label(
                            appState.canExportAudio ? "重新录音" : "开始录音",
                            systemImage: "record.circle"
                        )
                        .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    .disabled(appState.isTranscribing)
                    .disabled(isAllScene && allSceneRecorder.systemEnabled
                              && !allSceneRecorder.screenPermissionGranted)

                    if appState.canExportAudio {
                        Button {
                            appState.exportAudio()
                        } label: {
                            Label("导出录音…", systemImage: "square.and.arrow.up")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(appState.isBusy)
                    }
                }
            }

            if !activeIsRecording, let name = appState.selectedFileName.nilIfEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text(name)
                        .lineLimit(1)
                    if !appState.fileSizeLabel.isEmpty {
                        Text("· \(appState.fileSizeLabel)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: Capsule())
            }

            if appState.showsPlaybackBar {
                AudioPlayerBar()
            }

            if isAllScene {
                screenSourceToggles
            }

            if appState.micPermissionDenied {
                micPermissionBanner
            }

            if isAllScene, !allSceneRecorder.screenPermissionGranted {
                screenPermissionBanner
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
    }

    // MARK: - 子视图

    private var modePicker: some View {
        VStack(spacing: 6) {
            Picker("录音模式", selection: $appState.recordingMode) {
                ForEach(RecordingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .disabled(appState.isBusy)

            Text(appState.recordingMode.help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var screenSourceToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("麦克风", isOn: $allSceneRecorder.micEnabled)
            Toggle("系统声音（扬声器输出）", isOn: systemSourceBinding)
            Text("开关实时生效，可在录制过程中切换，无需重新开始。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var systemSourceBinding: Binding<Bool> {
        Binding(
            get: { allSceneRecorder.systemEnabled },
            set: { appState.setAllSceneSystemEnabled($0) }
        )
    }

    private var micPermissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mic.slash.fill")
            VStack(alignment: .leading, spacing: 6) {
                Text("麦克风权限未开启")
                    .fontWeight(.semibold)
                Text("请到「系统设置 → 隐私与安全性 → 麦克风」允许本应用，然后回来重试。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var screenPermissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "speaker.slash.fill")
            VStack(alignment: .leading, spacing: 6) {
                Text("需要「屏幕与系统录音」权限")
                    .fontWeight(.semibold)
                Text("开启后才能录制系统声音。请到「系统设置 → 隐私与安全性 → 屏幕与系统录音」允许本应用，然后重启本应用生效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var recordIdleTitle: String {
        if appState.canExportAudio {
            return "当前会话已有录音"
        }
        return "点击开始录音"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}