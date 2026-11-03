import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: appState.selectedFileURL == nil
                  ? "waveform.badge.mic"
                  : "doc.badge.waveform")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .symbolEffect(.pulse, isActive: isTargeted)

            if appState.selectedFileURL == nil {
                Text("拖入音频文件")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("mp3 / wav / m4a / aac / flac 等，上限 50MB")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.selectedFileName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !appState.fileSizeLabel.isEmpty {
                    Text(appState.fileSizeLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Button(appState.selectedFileURL == nil ? "选择文件…" : "更换文件…") {
                appState.pickFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appState.isBusy)

            if appState.showsPlaybackBar {
                AudioPlayerBar()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [7, 5])
                        )
                }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in
                    appState.setFile(url)
                }
            }
            return true
        }
        .animation(.easeInOut(duration: 0.18), value: isTargeted)
    }
}
