import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSegments = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("转写结果")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)

                if !appState.durationLabel.isEmpty {
                    Text(appState.durationLabel)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !appState.segments.isEmpty {
                    Picker("视图", selection: $showSegments) {
                        Text("全文").tag(false)
                        Text("分段").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                Button("复制") { appState.copyResult() }
                    .disabled(appState.resultText.isEmpty)
                Button("导出…") { appState.exportResult() }
                    .disabled(appState.resultText.isEmpty)
            }

            if appState.resultText.isEmpty && !appState.isTranscribing {
                Text("转写完成后文稿会出现在这里")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if showSegments && !appState.segments.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.segments) { seg in
                            segmentRow(seg)
                        }
                    }
                }
            } else {
                TextEditor(text: Binding(
                    get: { appState.resultText },
                    set: { appState.resultText = $0 }
                ))
                .font(.system(.body, design: .default))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onChange(of: appState.segments) { _, newValue in
            if newValue.isEmpty { showSegments = false }
            else if appState.selectedModel == .diarize { showSegments = true }
        }
    }

    @ViewBuilder
    private func segmentRow(_ seg: TranscriptSegment) -> some View {
        let playing = appState.audioPlayer.activeRange.map {
            $0.start == seg.start && $0.end == seg.end
        } ?? false

        HStack(alignment: .top, spacing: 10) {
            Button {
                appState.toggleSegmentPlayback(seg)
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(playing ? "停止回听本句" : "回听本句（云端 VAD 起止）")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(seg.timeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !seg.speaker.isEmpty {
                        Text(seg.speaker)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(seg.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            playing ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
