import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SessionListView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .sheet(isPresented: $appState.showAPIKeySheet) {
            APIKeyGuideView()
                .environmentObject(appState)
        }
    }

    private var detail: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider().opacity(0.35)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !appState.hasSavedKey {
                            APIKeyGuideBanner {
                                appState.showAPIKeySheet = true
                            }
                        }

                        Picker("输入方式", selection: $appState.inputMode) {
                            ForEach(InputMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(appState.isBusy)
                        .frame(maxWidth: 280)

                        Group {
                            switch appState.inputMode {
                            case .file:
                                DropZoneView()
                            case .record:
                                RecordPanelView()
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: appState.inputMode)

                        ModelPickerView(
                            selection: $appState.selectedModel,
                            disabled: appState.isBusy
                        )
                        actionRow
                        statusBlock
                        ResultPanelView()
                            .frame(minHeight: 220)
                    }
                    .padding(24)
                }
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(red: 0.12, green: 0.28, blue: 0.30).opacity(0.18),
                Color(red: 0.95, green: 0.78, blue: 0.42).opacity(0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(appState.currentSession?.title ?? "MiniVoice")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(AppVersion.shortDisplay)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Text("文件与录音转写")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.createSession(select: true)
            } label: {
                Label("新建会话", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .disabled(appState.isBusy)

            Button {
                appState.showAPIKeySheet = true
            } label: {
                Label(
                    appState.hasSavedKey ? "API Key" : "配置 API Key",
                    systemImage: appState.hasSavedKey ? "key.fill" : "key"
                )
            }
            .buttonStyle(.bordered)
            .tint(appState.hasSavedKey ? nil : .orange)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                appState.startTranscribe()
            } label: {
                Label(
                    appState.isTranscribing ? "转写中…" : "开始转写",
                    systemImage: appState.isTranscribing ? "hourglass" : "text.bubble"
                )
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                appState.isBusy
                    || appState.selectedFileURL == nil
            )

            if appState.canExportAudio {
                Button {
                    appState.exportAudio()
                } label: {
                    Label("导出录音", systemImage: "square.and.arrow.up")
                }
                .controlSize(.large)
                .disabled(appState.isBusy)
            }

            if appState.isTranscribing {
                Button("取消") { appState.cancel() }
                    .controlSize(.large)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        if !appState.errorMessage.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(appState.errorMessage)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(spacing: 8) {
                if appState.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(appState.statusHint)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 980, height: 640)
}
