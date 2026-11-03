import Foundation

/// 对齐 mini-voice 云函数：multipart 调用 SiliconFlow `/v1/audio/transcriptions`。
actor SiliconFlowClient {
    static let shared = SiliconFlowClient()

    static let endpoint = URL(string: "https://api.siliconflow.cn/v1/audio/transcriptions")!
    static let maxBytes = 50 * 1024 * 1024
    static let requestTimeout: TimeInterval = 140

    static let contentTypes: [String: String] = [
        "mp3": "audio/mpeg",
        "wav": "audio/wav",
        "m4a": "audio/mp4",
        "aac": "audio/aac",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
        "pcm": "audio/pcm",
        "mp4": "audio/mp4",
        "mov": "video/quicktime",
        "caf": "audio/x-caf",
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(
        fileURL: URL,
        model: AsrModel,
        apiKey: String
    ) async throws -> TranscriptionResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranscriptionError.missingAPIKey }

        let access = fileURL.startAccessingSecurityScopedResource()
        defer {
            if access { fileURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw TranscriptionError.emptyAudio }
        guard data.count <= Self.maxBytes else {
            throw TranscriptionError.fileTooLarge(maxMB: 50)
        }

        let format = Self.resolveFormat(fileURL.lastPathComponent)
        guard Self.contentTypes[format] != nil else {
            throw TranscriptionError.unsupportedFormat(format)
        }

        let filename = "audio.\(format)"
        let contentType = Self.contentTypes[format] ?? "audio/mpeg"

        // 与云函数一致：优先 verbose_json；失败或空结果再回退 plain
        if let verbose = try await postTranscription(
            data: data,
            filename: filename,
            contentType: contentType,
            model: model,
            apiKey: key,
            verbose: true
        ) {
            let parsed = Self.parseBody(verbose, model: model)
            if parsed.hasContent { return parsed }
        }

        guard let plain = try await postTranscription(
            data: data,
            filename: filename,
            contentType: contentType,
            model: model,
            apiKey: key,
            verbose: false
        ) else {
            throw TranscriptionError.emptyResult
        }

        let parsed = Self.parseBody(plain, model: model)
        guard parsed.hasContent else { throw TranscriptionError.emptyResult }
        return parsed
    }

    // MARK: - HTTP

    private func postTranscription(
        data: Data,
        filename: String,
        contentType: String,
        model: AsrModel,
        apiKey: String,
        verbose: Bool
    ) async throws -> Any? {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                    .data(using: .utf8)!
            )
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model.apiModel)
        if verbose {
            appendField("response_format", "verbose_json")
            appendField("timestamp_granularities[]", "segment")
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.underlying("无效的网络响应")
        }

        if http.statusCode != 200 {
            if verbose {
                // 与云函数一致：verbose 失败不抛，交给 plain 回退
                return nil
            }
            throw TranscriptionError.httpStatus(
                http.statusCode,
                Self.extractErrorMessage(responseData)
            )
        }

        if responseData.isEmpty { return nil }

        if let obj = try? JSONSerialization.jsonObject(with: responseData) {
            return obj
        }
        if let text = String(data: responseData, encoding: .utf8) {
            return text
        }
        return nil
    }

    // MARK: - Parse（对齐四套云函数）

    static func resolveFormat(_ nameOrFormat: String) -> String {
        let raw = nameOrFormat.lowercased()
        let ext = raw.contains(".") ? (raw.split(separator: ".").last.map(String.init) ?? raw) : raw
        return contentTypes[ext] != nil ? ext : "mp3"
    }

    static func parseBody(_ data: Any, model: AsrModel) -> TranscriptionResult {
        if let text = data as? String {
            return TranscriptionResult(text: text, segments: [], duration: 0)
        }
        guard let obj = data as? [String: Any] else {
            return .empty
        }

        switch model {
        case .gsr:
            return parseGsr(obj)
        case .diarize:
            return parseDiarize(obj)
        case .general, .ultra:
            return parseStandard(obj)
        }
    }

    private static func parseStandard(_ data: [String: Any]) -> TranscriptionResult {
        let text = string(data["text"])
        let duration = number(data["duration"])
        let segments = array(data["segments"]).compactMap { seg -> TranscriptSegment? in
            guard let dict = seg as? [String: Any] else { return nil }
            let text = string(dict["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = number(dict["start"])
            let end = number(dict["end"])
            guard !text.isEmpty, end > start else { return nil }
            return TranscriptSegment(
                start: start,
                end: end,
                text: text,
                speaker: "",
                rawText: "",
                refinedText: ""
            )
        }
        return TranscriptionResult(text: text, segments: segments, duration: duration)
    }

    private static func parseGsr(_ data: [String: Any]) -> TranscriptionResult {
        let duration = number(data["duration"])
        let segments = array(data["segments"]).compactMap { seg -> TranscriptSegment? in
            guard let dict = seg as? [String: Any] else { return nil }
            let text = pickSegText(dict)
            let rawText = string(dict["raw_text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let refinedText = string(dict["refined_text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = number(dict["start"])
            let end = number(dict["end"])
            guard !text.isEmpty, end > start else { return nil }
            return TranscriptSegment(
                start: start,
                end: end,
                text: text,
                speaker: "",
                rawText: rawText != text ? rawText : "",
                refinedText: refinedText != text ? refinedText : ""
            )
        }

        var text = string(data["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, !segments.isEmpty {
            text = segments.map(\.text).joined()
        }

        var extras: [String] = []
        for seg in segments {
            let extra = seg.refinedText.isEmpty ? seg.rawText : seg.refinedText
            if !extra.isEmpty, extra != text, !extras.contains(extra) {
                extras.append(extra)
            }
        }
        if !extras.isEmpty {
            text = text.isEmpty ? extras.joined(separator: "\n") : "\(text)\n\n\(extras.joined(separator: "\n"))"
        }

        return TranscriptionResult(text: text, segments: segments, duration: duration)
    }

    private static func parseDiarize(_ data: [String: Any]) -> TranscriptionResult {
        let duration = number(data["duration"])
        var indexMap: [String: String] = [:]
        var nextIndex = 1

        func speakerLabel(_ raw: String) -> String {
            guard !raw.isEmpty else { return "" }
            if let existing = indexMap[raw] { return existing }
            let label = "说话人\(nextIndex)"
            nextIndex += 1
            indexMap[raw] = label
            return label
        }

        let rawList: [Any] = {
            let segments = array(data["segments"])
            if !segments.isEmpty { return segments }
            return array(data["utterances"])
        }()

        let segments = rawList.compactMap { seg -> TranscriptSegment? in
            guard let dict = seg as? [String: Any] else { return nil }
            let text = string(dict["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = number(dict["start"])
            let end = number(dict["end"])
            guard !text.isEmpty, end > start else { return nil }
            return TranscriptSegment(
                start: start,
                end: end,
                text: text,
                speaker: speakerLabel(rawSpeaker(dict)),
                rawText: "",
                refinedText: ""
            )
        }

        var text = string(data["text"])
        let hasSpeaker = segments.contains { !$0.speaker.isEmpty }
        if hasSpeaker {
            var turns: [(speaker: String, text: String)] = []
            for seg in segments {
                if let last = turns.last, last.speaker == seg.speaker {
                    turns[turns.count - 1].text += seg.text
                } else {
                    turns.append((seg.speaker, seg.text))
                }
            }
            text = turns
                .map { turn in
                    turn.speaker.isEmpty ? turn.text : "\(turn.speaker)：\(turn.text)"
                }
                .joined(separator: "\n")
        }

        return TranscriptionResult(text: text, segments: segments, duration: duration)
    }

    private static func pickSegText(_ seg: [String: Any]) -> String {
        let candidates = [seg["text"], seg["refined_text"], seg["raw_text"]]
        for value in candidates {
            let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func rawSpeaker(_ seg: [String: Any]) -> String {
        let keys = ["speaker", "spk", "speaker_id", "speakerId", "spk_id"]
        for key in keys {
            if let value = seg[key] {
                let text = string(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    private static func extractErrorMessage(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let message = obj["message"] as? String, !message.isEmpty { return message }
        if let error = obj["error"] as? String, !error.isEmpty { return error }
        if let error = obj["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            return message
        }
        return ""
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func number(_ value: Any?) -> Double {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let n = Double(s) { return n }
        return 0
    }

    private static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }
}
