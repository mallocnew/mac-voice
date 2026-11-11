import SwiftUI

struct AudioPlayerBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AudioPlayerBarContent(appState: appState, player: appState.audioPlayer)
    }
}

private struct AudioPlayerBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var player: AudioPlayer
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    appState.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!player.isReady || appState.isRecording)
                .help(player.isReady ? "播放 / 暂停" : "当前格式暂不支持试听")

                VStack(alignment: .leading, spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubProgress : player.progress },
                            set: { scrubProgress = $0 }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing {
                                isScrubbing = true
                                scrubProgress = player.progress
                            } else {
                                appState.seekPlayback(progress: scrubProgress)
                                isScrubbing = false
                            }
                        }
                    )
                    .disabled(!player.isReady || appState.isRecording)

                    HStack {
                        Text(isScrubbing
                             ? format(scrubProgress * max(player.duration, 0.001))
                             : player.currentTimeLabel)
                        Spacer()
                        Text(player.durationLabel)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            if let message = player.lastError {
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
