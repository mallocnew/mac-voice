import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum RecordingMode: String, CaseIterable, Identifiable {
    case standard
    case allScene

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "普通录音"
        case .allScene: return "全场景"
        }
    }

    var help: String {
        switch self {
        case .standard: return "仅录制麦克风"
        case .allScene: return "同时录制麦克风与系统声音，可后台持续录制"
        }
    }
}

enum InputMode: String, CaseIterable, Identifiable {
    case file
    case record

    var id: String { rawValue }

    var label: String {
        switch self {
        case .file: return "文件"
        case .record: return "录音"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedModel: AsrModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelKey) }
    }

    @Published var inputMode: InputMode = .file
    @Published var showAPIKeySheet = false

    @Published var recordingMode: RecordingMode {
        didSet { UserDefaults.standard.set(recordingMode.rawValue, forKey: Self.recordingModeKey) }
    }

    @Published var apiKeyInput: String = ""
    @Published var hasSavedKey: Bool = false

    @Published var selectedFileURL: URL?
    @Published var selectedFileName: String = ""
    @Published var selectedFileSize: Int64 = 0

    @Published var isTranscribing = false
    @Published var statusHint = "拖入音频，录音，或点选文件转写"
    @Published var errorMessage = ""

    @Published var resultText = "" {
        didSet { scheduleTranscriptPersist() }
    }
    @Published var segments: [TranscriptSegment] = []
    @Published var duration: Double = 0

    @Published var micPermissionDenied = false

    @Published var sessions: [VoiceSession] = []
    @Published var currentSessionID: UUID?

    private var task: Task<Void, Never>?
    /// 高频电平/进度由面板直接观察，避免经 AppState 整树刷新。
    let recorder = AudioRecorder()
    let allSceneRecorder = AllSceneRecorder()
    let audioPlayer = AudioPlayer()
    private var cancellables = Set<AnyCancellable>()
    private var persistTranscriptTask: Task<Void, Never>?
    private var suppressPersist = false
    private static let modelKey = "fileAsrFn"
    private static let recordingModeKey = "recordingMode"

    var isRecording: Bool { recorder.isRecording || allSceneRecorder.isRecording }

    var isPlayingAudio: Bool { audioPlayer.isPlaying }
    var canPlayAudio: Bool { audioPlayer.isReady && !isRecording }
    var showsPlaybackBar: Bool {
        selectedFileURL != nil && !isRecording
    }

    var currentSession: VoiceSession? {
        sessions.first { $0.id == currentSessionID }
    }

    var canExportAudio: Bool {
        if let url = selectedFileURL, FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        if let session = currentSession, SessionStore.mediaFileURL(for: session) != nil {
            return true
        }
        return false
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.modelKey) ?? ""
        selectedModel = AsrModel(rawValue: saved) ?? .general
        let savedMode = UserDefaults.standard.string(forKey: Self.recordingModeKey) ?? ""
        recordingMode = RecordingMode(rawValue: savedMode) ?? .standard
        reloadAPIKey()
        // 只转发低频状态（开始/停止录音、播放就绪等），不要转发电平与进度 tick。
        recorder.$isRecording
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        allSceneRecorder.$isRecording
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        Publishers.Merge3(
            audioPlayer.$isPlaying.map { _ in () },
            audioPlayer.$isReady.map { _ in () },
            audioPlayer.$lastError.map { _ in () }
        )
        .dropFirst()
        .sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        sessions = SessionStore.loadSessions()
        if let first = sessions.first {
            selectSession(first.id)
        } else {
            createSession(select: true)
        }
    }

    var fileSizeLabel: String {
        guard selectedFileSize > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: selectedFileSize, countStyle: .file)
    }

    var durationLabel: String {
        guard duration > 0 else { return "" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var isBusy: Bool { isTranscribing || isRecording }

    // MARK: - Sessions

    @discardableResult
    func createSession(select: Bool = true) -> VoiceSession {
        let session = VoiceSession.blank(title: defaultSessionTitle())
        sessions.insert(session, at: 0)
        persistSessions()
        if select {
            loadSessionIntoUI(session)
        }
        statusHint = "已新建会话"
        return session
    }

    func selectSession(_ id: UUID) {
        guard !isBusy else { return }
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        loadSessionIntoUI(session)
        statusHint = "已打开「\(session.title)」"
    }

    func renameSession(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = trimmed
        sessions[index].updatedAt = Date()
        persistSessions()
    }

    func deleteSession(_ id: UUID) {
        guard !isBusy || currentSessionID != id else { return }
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let removed = sessions.remove(at: index)
        SessionStore.deleteMedia(for: removed)
        persistSessions()

        if currentSessionID == id {
            if let next = sessions.first {
                selectSession(next.id)
            } else {
                createSession(select: true)
            }
        }
        statusHint = "已删除会话"
    }

    func deleteCurrentSession() {
        guard let id = currentSessionID else { return }
        deleteSession(id)
    }

    private func loadSessionIntoUI(_ session: VoiceSession) {
        suppressPersist = true
        defer { suppressPersist = false }

        cancelTranscribe()
        errorMessage = ""
        currentSessionID = session.id
        inputMode = session.source == .record ? .record : .file
        if let model = session.model {
            selectedModel = model
        }

        resultText = session.transcript
        segments = session.segments
        duration = session.duration
        selectedFileName = session.originalName
        selectedFileSize = session.fileSize

        if let media = SessionStore.mediaFileURL(for: session) {
            selectedFileURL = media
        } else {
            selectedFileURL = nil
        }
        reloadPlayback()
    }

    private func ensureCurrentSession() -> VoiceSession {
        if let id = currentSessionID, let existing = sessions.first(where: { $0.id == id }) {
            return existing
        }
        return createSession(select: true)
    }

    private func updateCurrentSession(_ mutate: (inout VoiceSession) -> Void) {
        let id = ensureCurrentSession().id
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sessions[index])
        sessions[index].updatedAt = Date()
        // 保持最近更新在前
        let updated = sessions.remove(at: index)
        sessions.insert(updated, at: 0)
        persistSessions()
    }

    private func persistSessions() {
        SessionStore.saveSessions(sessions)
    }

    private func scheduleTranscriptPersist() {
        guard !suppressPersist else { return }
        persistTranscriptTask?.cancel()
        persistTranscriptTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.updateCurrentSession { session in
                session.transcript = self.resultText
                session.segments = self.segments
                session.duration = self.duration
            }
        }
    }

    private func defaultSessionTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: Date())
    }

    private func attachMedia(from url: URL, source: VoiceSession.Source, displayName: String) {
        do {
            var active = ensureCurrentSession()
            let existingPath = SessionStore.mediaFileURL(for: active)?.standardizedFileURL.path
            let incomingPath = url.standardizedFileURL.path
            let isSameMedia = existingPath == incomingPath

            // 已有文稿或其它音频时，再导入新材料 → 新开会话，避免覆盖
            if !isSameMedia, active.hasTranscript || active.hasMedia {
                active = createSession(select: true)
            }

            if let old = sessions.first(where: { $0.id == active.id }), !isSameMedia {
                SessionStore.deleteMedia(for: old)
            }

            let imported = try SessionStore.importMedia(from: url, sessionID: active.id)
            let mediaURL = SessionStore.mediaURL.appendingPathComponent(imported.fileName)

            selectedFileURL = mediaURL
            selectedFileName = displayName
            selectedFileSize = imported.fileSize

            updateCurrentSession { session in
                session.source = source
                session.mediaFileName = imported.fileName
                session.originalName = displayName
                session.fileSize = imported.fileSize
                session.transcript = ""
                session.segments = []
                session.duration = 0
                if session.title.hasPrefix("新会话")
                    || session.title.isEmpty
                    || Self.isAutoTimeTitle(session.title)
                {
                    session.title = source == .record
                        ? Self.titleFromFileName(displayName)
                        : Self.titleFromFileName(displayName)
                }
            }

            suppressPersist = true
            resultText = ""
            segments = []
            duration = 0
            suppressPersist = false
            inputMode = source == .record ? .record : .file
            reloadPlayback()
        } catch {
            errorMessage = "无法保存音频：\(error.localizedDescription)"
        }
    }

    // MARK: - Playback

    func reloadPlayback() {
        audioPlayer.load(selectedFileURL)
    }

    func togglePlayback() {
        guard !isRecording else { return }
        if selectedFileURL == nil {
            errorMessage = AudioPlaybackError.missingFile.localizedDescription
            return
        }
        audioPlayer.togglePlay()
    }

    func seekPlayback(progress: Double) {
        audioPlayer.seek(progress: progress)
    }

    func stopPlayback() {
        audioPlayer.stop()
    }

    /// 按句回听：播放云端分段的 [start, end]。
    func toggleSegmentPlayback(_ seg: TranscriptSegment) {
        guard !isRecording else { return }
        guard let url = selectedFileURL ?? currentSession.flatMap(SessionStore.mediaFileURL),
              FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = AudioPlaybackError.missingFile.localizedDescription
            return
        }
        if audioPlayer.loadedURLPath != url.path {
            audioPlayer.load(url)
        }
        guard audioPlayer.isReady else { return }
        audioPlayer.toggleSegmentPlay(start: seg.start, end: seg.end)
    }

    private static func isAutoTimeTitle(_ title: String) -> Bool {
        // 匹配「M月d日 HH:mm」自动标题，便于被文件名覆盖
        title.range(of: #"^\d{1,2}月\d{1,2}日 \d{2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func titleFromFileName(_ name: String) -> String {
        let base = name.split(separator: ".").dropLast().joined(separator: ".")
        return base.isEmpty ? name : base
    }

    // MARK: - API Key

    func reloadAPIKey() {
        let key = KeychainStore.loadAPIKey()
        apiKeyInput = key
        hasSavedKey = !key.isEmpty
    }

    func saveAPIKey() {
        KeychainStore.saveAPIKey(apiKeyInput)
        reloadAPIKey()
        if hasSavedKey {
            errorMessage = ""
            statusHint = "API Key 已保存，可以开始转写"
        }
    }

    func clearAPIKey() {
        KeychainStore.deleteAPIKey()
        apiKeyInput = ""
        hasSavedKey = false
    }

    func requireAPIKey() -> Bool {
        reloadAPIKey()
        guard hasSavedKey else {
            errorMessage = ""
            showAPIKeySheet = true
            statusHint = "请先配置 API Key"
            return false
        }
        return true
    }

    // MARK: - File

    func pickFile() {
        guard !isRecording else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.allowedTypes
        panel.message = "选择要转写的音频文件（≤50MB）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFile(url, source: .file)
    }

    func setFile(_ url: URL, source: VoiceSession.Source = .file) {
        cancelTranscribe()
        errorMessage = ""

        let ext = url.pathExtension.lowercased()
        if !Self.allowedExtensions.contains(ext) {
            errorMessage = TranscriptionError.unsupportedFormat(ext).localizedDescription
            statusHint = "拖入音频，录音，或点选文件转写"
            return
        }

        attachMedia(from: url, source: source, displayName: url.lastPathComponent)
        statusHint = "已选择 \(selectedFileName)，点「开始转写」"
    }

    // MARK: - Recording

    func startRecording() {
        guard !isTranscribing else { return }
        Task {
            guard await ensureMicPermission() else { return }

            if recordingMode == .allScene, allSceneRecorder.systemEnabled {
                // 屏幕录音授权：未授权则引导开启（系统授权后需重启应用）
                if !ScreenRecordingPermission.isGranted {
                    ScreenRecordingPermission.request()
                    allSceneRecorder.systemEnabled = false
                    errorMessage = AllSceneError.screenPermissionDenied.localizedDescription
                    statusHint = "请到「系统设置 → 隐私与安全性 → 屏幕与系统录音」授权，并重启本应用"
                    return
                }
            }

            micPermissionDenied = false
            errorMessage = ""
            stopPlayback()
            audioPlayer.load(nil)

            // 已有内容的会话上开录 → 新会话
            if let session = currentSession, session.hasTranscript || session.hasMedia {
                createSession(select: true)
            }

            if recordingMode == .allScene {
                do {
                    try allSceneRecorder.start()
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    return
                }
            } else {
                do {
                    _ = try recorder.start()
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    return
                }
            }

            selectedFileURL = nil
            selectedFileName = ""
            selectedFileSize = 0
            suppressPersist = true
            resultText = ""
            segments = []
            duration = 0
            suppressPersist = false
            inputMode = .record
            statusHint = recordingMode == .allScene ? "全场景录音中（后台可继续）…" : "录音中…"
        }
    }

    func stopRecording(transcribeAfter: Bool) {
        if recordingMode == .allScene {
            guard let url = allSceneRecorder.stop() else { return }
            let name = "全场景录音 \(defaultSessionTitle()).m4a"
            attachMedia(from: url, source: .record, displayName: name)
            try? FileManager.default.removeItem(at: url)
        } else {
            guard let url = recorder.stop() else { return }
            let name = "录音 \(defaultSessionTitle()).m4a"
            attachMedia(from: url, source: .record, displayName: name)
            try? FileManager.default.removeItem(at: url)
        }
        statusHint = transcribeAfter
            ? "录音完成，开始转写…"
            : "录音完成，可转写或导出音频"
        if transcribeAfter {
            startTranscribe()
        }
    }

    func cancelRecording() {
        if recordingMode == .allScene {
            allSceneRecorder.cancel()
        } else {
            recorder.cancel()
        }
        statusHint = "已取消录音"
    }

    /// 请求麦克风权限，未授权时提示并返回 false。
    private func ensureMicPermission() async -> Bool {
        let permission = MicrophonePermission.current
        if permission == .denied {
            micPermissionDenied = true
            errorMessage = AudioRecorderError.permissionDenied.localizedDescription
            return false
        }
        if permission == .undetermined {
            let granted = await MicrophonePermission.request()
            if !granted {
                micPermissionDenied = true
                errorMessage = AudioRecorderError.permissionDenied.localizedDescription
                return false
            }
        }
        return true
    }

    /// 全场景：切换系统声音开关；未授权时请求并回退。
    func setAllSceneSystemEnabled(_ enabled: Bool) {
        guard enabled else {
            allSceneRecorder.systemEnabled = false
            return
        }
        if ScreenRecordingPermission.isGranted {
            allSceneRecorder.systemEnabled = true
        } else {
            ScreenRecordingPermission.request()
            if ScreenRecordingPermission.isGranted {
                allSceneRecorder.systemEnabled = true
            } else {
                allSceneRecorder.systemEnabled = false
                errorMessage = AllSceneError.screenPermissionDenied.localizedDescription
                statusHint = "请到「系统设置 → 隐私与安全性 → 屏幕与系统录音」授权后，重启本应用"
            }
        }
    }

    func exportAudio() {
        guard let source = selectedFileURL ?? currentSession.flatMap(SessionStore.mediaFileURL) else {
            errorMessage = "当前会话没有可导出的录音"
            return
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            errorMessage = "录音文件不存在"
            return
        }

        let panel = NSSavePanel()
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        if let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        } else {
            panel.allowedContentTypes = [.mpeg4Audio, .audio]
        }
        let base = selectedFileName.isEmpty
            ? (currentSession?.title ?? "recording")
            : Self.titleFromFileName(selectedFileName)
        panel.nameFieldStringValue = base.contains(".") ? base : "\(base).\(ext)"
        panel.canCreateDirectories = true
        panel.message = "导出录音文件"

        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            statusHint = "已导出录音 \(dest.lastPathComponent)"
        } catch {
            errorMessage = "导出录音失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Transcribe

    func startTranscribe() {
        guard requireAPIKey() else { return }
        guard let url = selectedFileURL else {
            errorMessage = inputMode == .record ? "请先录一段音" : "请先选择音频文件"
            return
        }
        let key = KeychainStore.loadAPIKey()
        if selectedFileSize > Int64(SiliconFlowClient.maxBytes) {
            errorMessage = TranscriptionError.fileTooLarge(maxMB: 50).localizedDescription
            return
        }

        cancelTranscribe()
        suppressPersist = true
        resultText = ""
        segments = []
        duration = 0
        suppressPersist = false
        errorMessage = ""
        isTranscribing = true
        statusHint = "转写中（\(selectedModel.label)）…"

        let model = selectedModel
        task = Task {
            do {
                let result = try await SiliconFlowClient.shared.transcribe(
                    fileURL: url,
                    model: model,
                    apiKey: key
                )
                guard !Task.isCancelled else { return }
                suppressPersist = true
                resultText = result.text.isEmpty ? "未识别到有效内容" : result.text
                segments = result.segments
                duration = result.duration
                suppressPersist = false
                isTranscribing = false
                statusHint = result.segments.isEmpty ? "转写完成" : "转写完成，可查看分段"

                updateCurrentSession { session in
                    session.model = model
                    session.transcript = self.resultText
                    session.segments = self.segments
                    session.duration = self.duration
                }
            } catch is CancellationError {
                isTranscribing = false
                statusHint = "已取消"
            } catch let urlError as URLError where urlError.code == .cancelled {
                isTranscribing = false
                statusHint = "已取消"
            } catch {
                isTranscribing = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                statusHint = "拖入音频，录音，或点选文件转写"
            }
        }
    }

    func cancel() {
        if isRecording {
            cancelRecording()
        }
        cancelTranscribe()
    }

    private func cancelTranscribe() {
        task?.cancel()
        task = nil
        if isTranscribing {
            isTranscribing = false
            statusHint = "已取消"
        }
    }

    func copyResult() {
        guard !resultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        statusHint = "已复制到剪贴板"
    }

    func exportResult() {
        guard !resultText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let base = selectedFileName.isEmpty
            ? (currentSession?.title ?? "transcript")
            : Self.titleFromFileName(selectedFileName)
        panel.nameFieldStringValue = base + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try resultText.write(to: url, atomically: true, encoding: .utf8)
            statusHint = "已导出 \(url.lastPathComponent)"
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private static let allowedExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "ogg", "flac", "pcm", "mp4", "mov", "caf",
    ]

    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.audio, .mpeg4Movie, .quickTimeMovie]
        for ext in allowedExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}
