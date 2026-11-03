import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button {
                    appState.createSession(select: true)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建会话")
                .disabled(appState.isBusy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            List(selection: Binding(
                get: { appState.currentSessionID },
                set: { id in
                    guard let id else { return }
                    appState.selectSession(id)
                }
            )) {
                ForEach(appState.sessions) { session in
                    sessionRow(session)
                        .tag(session.id)
                        .contextMenu {
                            Button("重命名…") {
                                renamingID = session.id
                                renameText = session.title
                            }
                            Button("导出录音…") {
                                appState.selectSession(session.id)
                                appState.exportAudio()
                            }
                            .disabled(!session.hasMedia)

                            Divider()

                            Button("删除", role: .destructive) {
                                appState.deleteSession(session.id)
                            }
                            .disabled(appState.isBusy && appState.currentSessionID == session.id)
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(item: Binding(
            get: { renamingID.map(RenameTarget.init) },
            set: { renamingID = $0?.id }
        )) { target in
            RenameSheet(
                title: $renameText,
                onCancel: { renamingID = nil },
                onSave: {
                    appState.renameSession(target.id, to: renameText)
                    renamingID = nil
                }
            )
        }
    }

    private func sessionRow(_ session: VoiceSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: session.source == .record ? "mic.fill" : "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.title)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .lineLimit(1)
            }
            Text(session.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(Self.dateLabel(session.updatedAt))
                if session.hasTranscript {
                    Text("已转写")
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct RenameTarget: Identifiable {
    let id: UUID
}

private struct RenameSheet: View {
    @Binding var title: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名会话")
                .font(.headline)
            TextField("会话名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
