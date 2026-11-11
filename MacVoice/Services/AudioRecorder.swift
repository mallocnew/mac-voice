import AVFoundation
import Foundation

enum MicrophonePermission {
    case undetermined
    case granted
    case denied

    static var current: MicrophonePermission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得麦克风权限。请在「系统设置 → 隐私与安全性 → 麦克风」中允许本应用。"
        case .alreadyRecording:
            return "正在录音中"
        case .notRecording:
            return "当前没有进行中的录音"
        case .setupFailed(let message):
            return "无法开始录音：\(message)"
        }
    }
}

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    /// 每秒更新一次计时文案；不做实时电平绘制。
    @Published private(set) var elapsedLabel = "00:00"

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    func start() throws -> URL {
        guard !isRecording else { throw AudioRecorderError.alreadyRecording }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = false
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw AudioRecorderError.setupFailed("录音器未能启动")
            }
            self.recorder = recorder
            self.outputURL = url
            self.elapsedLabel = Self.formatElapsed(0)
            self.isRecording = true
            startTimer()
            return url
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            throw AudioRecorderError.setupFailed(error.localizedDescription)
        }
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        recorder?.stop()
        stopTimer()
        isRecording = false
        let url = outputURL
        recorder = nil
        outputURL = nil
        return url
    }

    func cancel() {
        guard isRecording else { return }
        let url = stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let recorder else { return }
        elapsedLabel = Self.formatElapsed(Int(recorder.currentTime))
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func formatElapsed(_ total: Int) -> String {
        let clamped = max(0, total)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
