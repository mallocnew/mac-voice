import Foundation

/// 本地会话：index JSON + media 目录，落在 Application Support。
enum SessionStore {
    private static let folderName = "MiniVoice"
    private static let legacyFolderName = "MacVoice"
    private static let indexName = "sessions.json"

    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        // 从旧目录 MacVoice 迁移一次
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacy.path)
        {
            try? FileManager.default.moveItem(at: legacy, to: url)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var mediaURL: URL {
        let url = rootURL.appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var indexURL: URL {
        rootURL.appendingPathComponent(indexName)
    }

    static func loadSessions() -> [VoiceSession] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            let list = try makeDecoder().decode([VoiceSession].self, from: data)
            return list.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("SessionStore load error:", error)
            return []
        }
    }

    static func saveSessions(_ sessions: [VoiceSession]) {
        do {
            let data = try makeEncoder().encode(sessions)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("SessionStore save error:", error)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 把外部/临时音频拷入 media/，返回相对文件名。
    static func importMedia(from sourceURL: URL, sessionID: UUID) throws -> (fileName: String, fileSize: Int64) {
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension.lowercased()
        let fileName = "\(sessionID.uuidString).\(ext)"
        let dest = mediaURL.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }

        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

        try FileManager.default.copyItem(at: sourceURL, to: dest)
        let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return (fileName, size)
    }

    static func mediaFileURL(for session: VoiceSession) -> URL? {
        guard let name = session.mediaFileName, !name.isEmpty else { return nil }
        let url = mediaURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func deleteMedia(for session: VoiceSession) {
        guard let url = mediaFileURL(for: session) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
