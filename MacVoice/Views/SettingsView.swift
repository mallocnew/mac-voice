import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var revealKey = false
    @State private var savedFlash = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 打开 SiliconFlow → API 密钥，新建并复制 Key")
                    Button("打开 API 密钥页面") {
                        if let url = URL(string: "https://cloud.siliconflow.cn/account/ak") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    Text("2. 粘贴到下方，保存到本机钥匙串")
                    Text("3. 返回主界面即可文件转写或录音转写")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } header: {
                Text("如何获取")
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    if revealKey {
                        TextField("sk-…", text: $appState.apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-…", text: $appState.apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button(revealKey ? "隐藏" : "显示") {
                        revealKey.toggle()
                    }
                }

                HStack {
                    Button("保存到钥匙串") {
                        appState.saveAPIKey()
                        savedFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            savedFlash = false
                        }
                    }
                    .disabled(appState.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("清除", role: .destructive) {
                        appState.clearAPIKey()
                    }
                    .disabled(!appState.hasSavedKey && appState.apiKeyInput.isEmpty)

                    if savedFlash {
                        Text("已保存")
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else if appState.hasSavedKey {
                        Label("已配置", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }
            } header: {
                Text("SiliconFlow API Key")
            } footer: {
                Text("Key 只存本机钥匙串，用于鉴权直连 api.siliconflow.cn；内置 ASR 免费不收费，不会上传到其他服务器。")
            }

            Section {
                LabeledContent("通用", value: "XingChenASR-V3.2")
                LabeledContent("Ultra", value: "XingChenASR-V3.2-Ultra")
                LabeledContent("生成", value: "XingChenGSR-V1.0")
                LabeledContent("发言人", value: "XingChenASR-Diarize-V3.0")
            } header: {
                Text("转写模型")
            } footer: {
                Text("以上四种 ASR 均为 SiliconFlow 免费模型，调用不收费。需要 API Key 仅用于鉴权，不代表付费。")
            }

            Section("关于") {
                LabeledContent("应用", value: "MiniVoice")
                LabeledContent("版本", value: AppVersion.marketing)
                LabeledContent("构建", value: AppVersion.build)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 540, height: 560)
        .onAppear { appState.reloadAPIKey() }
    }
}
