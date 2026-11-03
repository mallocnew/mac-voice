import Foundation

/// 与 mini-voice 四种文件转写云函数一一对应（直连 SiliconFlow，不经微信云开发）。
enum AsrModel: String, CaseIterable, Identifiable, Codable {
    case general
    case ultra
    case gsr
    case diarize

    var id: String { rawValue }

    /// SiliconFlow model 字段
    var apiModel: String {
        switch self {
        case .general: return "XingChenAGI/XingChenASR-V3.2"
        case .ultra: return "XingChenAGI/XingChenASR-V3.2-Ultra"
        case .gsr: return "XingChenAGI/XingChenGSR-V1.0"
        case .diarize: return "XingChenAGI/XingChenASR-Diarize-V3.0"
        }
    }

    var label: String {
        switch self {
        case .general: return "通用"
        case .ultra: return "Ultra"
        case .gsr: return "生成"
        case .diarize: return "发言人"
        }
    }

    var hint: String {
        switch self {
        case .general: return "按原话转写，保留口语和方言用词"
        case .ultra: return "精简口语、理顺语句；粤语、上海话可转成普通话"
        case .gsr: return "结合语义理解润色，输出更贴近书面表达的文稿"
        case .diarize: return "适合已录好的会议，自动标出发言人"
        }
    }

    /// 产品文案：当前内置四种 ASR 在 SiliconFlow 上均为免费模型。
    static let freePricingNote = "通用 / Ultra / 生成 / 发言人 均为免费模型，不收费"
}
