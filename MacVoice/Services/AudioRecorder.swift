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
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var meteringLevel: Float = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

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
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw AudioRecorderError.setupFailed("录音器未能启动")
            }
            self.recorder = recorder
            self.outputURL = url
            self.elapsed = 0
            self.meteringLevel = 0
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
        meteringLevel = 0
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
                recorder.updateMeters()
                // averagePower 约 -160…0 dB，映射到 0…1
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (power + 50) / 50))
                self.meteringLevel = normalized
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
