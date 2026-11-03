import Foundation

struct TranscriptSegment: Identifiable, Hashable, Codable {
    var id: String { "\(start)-\(end)-\(text.hashValue)-\(speaker)" }
    var start: Double
    var end: Double
    var text: String
    var speaker: String
    var rawText: String
    var refinedText: String

    var timeLabel: String {
        "\(Self.format(start)) – \(Self.format(end))"
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct TranscriptionResult: Equatable {
    var text: String
    var segments: [TranscriptSegment]
    var duration: Double

    static let empty = TranscriptionResult(text: "", segments: [], duration: 0)

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !segments.isEmpty
    }
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case emptyAudio
    case fileTooLarge(maxMB: Int)
    case unsupportedFormat(String)
    case httpStatus(Int, String)
    case emptyResult
    case cancelled
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在设置中填写 SiliconFlow API Key"
        case .emptyAudio:
            return "音频数据为空"
        case .fileTooLarge(let maxMB):
            return "音频过大（上限 \(maxMB)MB）"
        case .unsupportedFormat(let ext):
            return "不支持的格式：.\(ext)"
        case .httpStatus(let code, let message):
            return message.isEmpty ? "ASR 请求失败 (\(code))" : message
        case .emptyResult:
            return "未识别到有效内容"
        case .cancelled:
            return "已取消"
        case .underlying(let message):
            return message
        }
    }
}
