import SwiftUI

@main
struct MacVoiceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建会话") {
                    appState.createSession(select: true)
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(appState.isBusy)
            }
            CommandGroup(after: .pasteboard) {
                Button("复制转写结果") {
                    appState.copyResult()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.resultText.isEmpty)

                Button("导出文稿为 TXT…") {
                    appState.exportResult()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.resultText.isEmpty)

                Button("导出录音…") {
                    appState.exportAudio()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!appState.canExportAudio || appState.isBusy)

                Button(appState.isPlayingAudio ? "暂停播放" : "播放音频") {
                    appState.togglePlayback()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(!appState.showsPlaybackBar || appState.isRecording)
            }
            CommandMenu("转写") {
                Button("配置 API Key…") {
                    appState.showAPIKeySheet = true
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button(appState.isRecording ? "停止录音" : "开始录音") {
                    if appState.isRecording {
                        appState.stopRecording(transcribeAfter: false)
                    } else {
                        appState.inputMode = .record
                        appState.startRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appState.isTranscribing)

                Button("开始转写") {
                    appState.startTranscribe()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(appState.isBusy || appState.selectedFileURL == nil)

                Divider()

                Button("删除当前会话", role: .destructive) {
                    appState.deleteCurrentSession()
                }
                .disabled(appState.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
