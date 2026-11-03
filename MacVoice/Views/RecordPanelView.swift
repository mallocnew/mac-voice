import AppKit
import SwiftUI

struct RecordPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(appState.isRecording
                          ? Color.red.opacity(0.12)
                          : Color.primary.opacity(0.04))
                    .frame(width: 120, height: 120)
                    .scaleEffect(appState.isRecording ? 1 + CGFloat(appState.meterLevel) * 0.18 : 1)
                    .animation(.easeOut(duration: 0.1), value: appState.meterLevel)

                Image(systemName: appState.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(appState.isRecording ? Color.red : Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: appState.isRecording)
            }

            Text(appState.isRecording ? appState.recordElapsedLabel : recordIdleTitle)
                .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(appState.isRecording
                 ? "停止后可转写或导出录音文件"
                 : "录音保存为 m4a（16kHz 单声道），并记入当前会话")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if appState.isRecording {
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

            if !appState.isRecording, let name = appState.selectedFileName.nilIfEmpty {
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

            if appState.micPermissionDenied {
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
