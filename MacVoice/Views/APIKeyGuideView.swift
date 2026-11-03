import AppKit
import SwiftUI

struct APIKeyGuideBanner: View {
    var onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始前先配置 API Key")
                        .font(.system(.headline, design: .rounded))
                    Text("四种转写模型均免费不收费；Key 只用于鉴权，保存在本机钥匙串。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                guideStep(1, "打开 SiliconFlow 控制台，登录账号")
                guideStep(2, "进入「API 密钥」，新建一把 Key 并复制")
                guideStep(3, "回到本应用粘贴并保存")
            }
            .padding(.leading, 2)

            HStack(spacing: 10) {
                Button("打开获取页面") {
                    if let url = URL(string: "https://cloud.siliconflow.cn/account/ak") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("填写 API Key…", action: onConfigure)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                }
        )
    }

    private func guideStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.2), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
        }
    }
}

struct APIKeyGuideView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var revealKey = false
    @State private var savedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("配置 API Key")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepsCard
                    keyFieldCard
                    privacyNote
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 480)
        .onAppear { appState.reloadAPIKey() }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("获取步骤")
                .font(.headline)

            numbered(1, "访问 SiliconFlow 开放平台并登录") {
                Button("cloud.siliconflow.cn") {
                    NSWorkspace.shared.open(URL(string: "https://cloud.siliconflow.cn/account/ak")!)
                }
                .buttonStyle(.link)
            }
            numbered(2, "左侧进入「API 密钥」→「新建 API 密钥」") {
                EmptyView()
            }
            numbered(3, "复制以 sk- 开头的密钥（只显示一次，请妥善保存）") {
                EmptyView()
            }
            numbered(4, "粘贴到下方并点「保存到钥匙串」") {
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var keyFieldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Key")
                .font(.headline)

            HStack {
                if revealKey {
                    TextField("sk-…", text: $appState.apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("sk-…", text: $appState.apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                Button(revealKey ? "隐藏" : "显示") { revealKey.toggle() }
            }

            HStack {
                Button("保存到钥匙串") {
                    appState.saveAPIKey()
                    savedFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        savedFlash = false
                    }
                    if appState.hasSavedKey {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("清除", role: .destructive) {
                    appState.clearAPIKey()
                }
                .disabled(!appState.hasSavedKey && appState.apiKeyInput.isEmpty)

                if savedFlash || appState.hasSavedKey {
                    Label(savedFlash ? "已保存" : "已配置", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
        }
    }

    private var privacyNote: some View {
        Text("内置四种 ASR 均为免费模型，不收费。Key 仅保存在本机钥匙串做鉴权，直连 SiliconFlow；不会上传到其他服务器，也不会写入应用日志。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func numbered<Accessory: View>(
        _ n: Int,
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                accessory()
            }
        }
    }
}
