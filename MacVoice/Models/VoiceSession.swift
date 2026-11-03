import Foundation

struct VoiceSession: Identifiable, Codable, Equatable, Hashable {
    enum Source: String, Codable {
        case file
        case record
    }

    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var source: Source
    /// 相对 Application Support/media/ 下的文件名；无音频时为 nil
    var mediaFileName: String?
    var originalName: String
    var modelRaw: String?
    var transcript: String
    var segments: [TranscriptSegment]
    var duration: Double
    var fileSize: Int64

    var model: AsrModel? {
        get { modelRaw.flatMap(AsrModel.init(rawValue:)) }
        set { modelRaw = newValue?.rawValue }
    }

    var preview: String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        if !originalName.isEmpty { return originalName }
        return source == .record ? "未命名录音" : "空会话"
    }

    var hasMedia: Bool { mediaFileName != nil && !(mediaFileName?.isEmpty ?? true) }
    var hasTranscript: Bool { !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func blank(title: String = "新会话") -> VoiceSession {
        let now = Date()
        return VoiceSession(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now,
            source: .file,
            mediaFileName: nil,
            originalName: "",
            modelRaw: nil,
            transcript: "",
            segments: [],
            duration: 0,
            fileSize: 0
        )
    }
}
