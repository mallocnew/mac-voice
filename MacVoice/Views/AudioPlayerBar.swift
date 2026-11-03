import SwiftUI

struct AudioPlayerBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    appState.togglePlayback()
                } label: {
                    Image(systemName: appState.isPlayingAudio ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.canPlayAudio || appState.isRecording)
                .help(appState.canPlayAudio ? "播放 / 暂停" : "当前格式暂不支持试听")

                VStack(alignment: .leading, spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubProgress : appState.playbackProgress },
                            set: { scrubProgress = $0 }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing {
                                isScrubbing = true
                                scrubProgress = appState.playbackProgress
                            } else {
                                appState.seekPlayback(progress: scrubProgress)
                                isScrubbing = false
                            }
                        }
                    )
                    .disabled(!appState.canPlayAudio || appState.isRecording)

                    HStack {
                        Text(isScrubbing
                             ? format(scrubProgress * max(appState.playbackDuration, 0.001))
                             : appState.playbackCurrentLabel)
                        Spacer()
                        Text(appState.playbackDurationLabel)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            if let message = appState.playbackErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
