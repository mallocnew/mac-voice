import AVFoundation
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit

// MARK: - 屏幕（系统声音）录音权限

enum ScreenRecordingPermission {
    /// 是否已获得「屏幕与系统录音」权限（TCC，非沙盒 entitlement）。
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 触发系统授权弹窗（macOS 10.15+）。返回是否已授权。
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

// MARK: - 单声道环形缓冲（线程安全）

/// 供录音源（麦克风/系统声音）写入、混音器读取。容量固定，写满丢弃最旧样本，控制内存占用。
final class AudioRingBuffer {
    private var samples: [Float]
    private let capacity: Int
    private var head = 0
    private var count = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.samples = [Float](repeating: 0, count: self.capacity)
    }

    /// 写入一段样本；超容量时丢弃最旧数据（用于对齐/防积累，牺牲极小精度换稳定）。
    func write(_ new: [Float]) {
        guard !new.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let excess = count + new.count - capacity
        if excess > 0 {
            head = (head + excess) % capacity
            count -= excess
        }
        for v in new {
            samples[(head + count) % capacity] = v
            count += 1
        }
    }

    /// 读取最多 out.count 个样本到 out，返回实际读取数。
    @discardableResult
    func read(_ out: inout [Float]) -> Int {
        lock.lock(); defer { lock.unlock() }
        let n = Swift.min(out.count, count)
        for i in 0..<n { out[i] = samples[(head + i) % capacity] }
        head = (head + n) % capacity
        count -= n
        return n
    }
}

// MARK: - 系统声音采集（ScreenCaptureKit）

enum SystemCaptureError: LocalizedError {
    case noDisplay
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "未检测到可采集的屏幕"
        case .captureFailed(let message): return "系统声音采集失败：\(message)"
        }
    }
}

/// 仅添加 .audio 输出类型，不消费视频帧，最大程度节省资源。
final class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var converterCache: [String: AVAudioConverter] = [:]
    private let onSample: ([Float]) -> Void
    private let targetRate: Double
    private let targetFormat: AVAudioFormat
    private let sampleQueue = DispatchQueue(label: "allscene.system.audio", qos: .userInitiated)

    init(targetRate: Double, targetChannels: AVAudioChannelCount, onSample: @escaping ([Float]) -> Void) {
        self.targetRate = targetRate
        self.targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: targetChannels)!
        self.onSample = onSample
        super.init()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw SystemCaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.showsCursor = false
        // 仅采音频：不投递视频帧，且把视频尺寸压到最小以进一步降开销。
        config.width = 1
        config.height = 1
        config.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            self.stream = nil
            throw SystemCaptureError.captureFailed(error.localizedDescription)
        }
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let fmt = AVAudioFormat(cmAudioFormatDescription: fmtDesc)
        guard let src = Self.extractPCM(from: sampleBuffer, format: fmt) else { return }

        let key = "\(fmt.sampleRate)-\(fmt.channelCount)"
        let conv: AVAudioConverter
        if let cached = converterCache[key] {
            conv = cached
        } else {
            guard let c = AVAudioConverter(from: fmt, to: targetFormat) else { return }
            converterCache[key] = c
            conv = c
        }

        let cap = AVAudioFrameCount(Double(src.frameLength) * targetRate / fmt.sampleRate) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }
        var err: NSError?
        let status = conv.convert(to: out, error: &err) { _, inStatus in
            inStatus.pointee = .haveData
            return src as AVAudioBuffer
        }
        if status == .haveData, let ch = out.floatChannelData, out.frameLength > 0 {
            let arr = Array(UnsafeMutableBufferPointer(start: ch[0], count: Int(out.frameLength)))
            onSample(arr)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // 采集被系统打断（如授权被撤销/显示器变化），静默置空，停止后由上层恢复。
        self.stream = nil
    }

    /// 从 CMSampleBuffer 抽取音频到 AVAudioPCMBuffer（原生格式）。
    private static func extractPCM(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }
        var sizeNeeded: Int = 0
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: nil
        )
        guard sizeNeeded > 0 else { return nil }
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else { return nil }
        out.frameLength = AVAudioFrameCount(numSamples)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: out.mutableAudioBufferList,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }
        return out
    }
}

// MARK: - 全场景录音器

enum AllSceneError: LocalizedError {
    case alreadyRecording
    case notRecording
    case micSetupFailed(String)
    case screenPermissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "正在录音中"
        case .notRecording: return "当前没有进行中的录音"
        case .micSetupFailed(let message): return "麦克风初始化失败：\(message)"
        case .screenPermissionDenied: return "未获得「屏幕与系统录音」权限，无法录制系统声音。"
        }
    }
}

/// 同时采集麦克风 + 系统扬声器，混成 16kHz 单声道 AAC（m4a）。
/// 资源策略：16k 单声道、不采集视频帧、仅 10ms 混音节拍、环形缓冲限长。
final class AllSceneRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var micEnabled = true
    @Published var systemEnabled = true
    @Published var elapsedLabel = "00:00"
    @Published private(set) var screenPermissionGranted = ScreenRecordingPermission.isGranted

    let sampleRate: Double = 16_000
    let channelCount: AVAudioChannelCount = 1
    let blockFrames = 160 // 10ms @ 16k

    private let micEngine = AVAudioEngine()
    private var micConverter: AVAudioConverter?
    private let micRing = AudioRingBuffer(capacity: 160_000)    // 10s
    private let systemRing = AudioRingBuffer(capacity: 160_000) // 10s
    private var systemCapture: SystemAudioCapture?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var mixerTimer: DispatchSourceTimer?
    private let mixerQueue = DispatchQueue(label: "allscene.mixer", qos: .userInitiated)
    private var elapsedTimer: Timer?
    private var activity: NSObjectProtocol?
    private let lock = NSLock()
    private var frameCount: Int64 = 0

    // MARK: - Start / Stop

    func start() throws {
        lock.lock()
        if isRecording { lock.unlock(); throw AllSceneError.alreadyRecording }
        lock.unlock()

        frameCount = 0
        try createFile()
        try startMic()
        if systemEnabled && screenPermissionGranted {
            startSystemCapture()
        }
        beginActivity()
        startMixer()
        startElapsedTimer()
        lock.lock(); isRecording = true; lock.unlock()
    }

    func stop() -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard isRecording else { return nil }
        isRecording = false

        if let systemCapture {
            Task { await systemCapture.stop() }
            self.systemCapture = nil
        }
        stopMic()
        stopMixer()
        stopElapsedTimer()
        endActivity()
        flushRings()
        let url = fileURL
        file = nil
        fileURL = nil
        return url
    }

    func cancel() {
        let url = stop()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - 麦克风

    private func startMic() throws {
        let input = micEngine.inputNode
        let srcFmt = input.outputFormat(forBus: 0)
        let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
        guard let conv = AVAudioConverter(from: srcFmt, to: target) else {
            throw AllSceneError.micSetupFailed("无法初始化采样率转换")
        }
        micConverter = conv

        input.installTap(onBus: 0, bufferSize: 512, format: srcFmt) { [weak self] buffer, _ in
            guard let self, let conv = self.micConverter else { return }
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / srcFmt.sampleRate) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
            var err: NSError?
            let status = conv.convert(to: out, error: &err) { _, inStatus in
                inStatus.pointee = .haveData
                return buffer as AVAudioBuffer
            }
            if status == .haveData, let ch = out.floatChannelData, out.frameLength > 0 {
                let arr = Array(UnsafeMutableBufferPointer(start: ch[0], count: Int(out.frameLength)))
                self.micRing.write(arr)
            }
        }

        // 采音不播放：静音主混音器，避免回放麦克风。
        micEngine.mainMixerNode.outputVolume = 0
        micEngine.connect(input, to: micEngine.mainMixerNode, format: nil)
        try micEngine.start()
    }

    private func stopMixer() {
        mixerTimer?.cancel()
        mixerTimer = nil
    }

    private func stopMic() {
        micEngine.stop()
        micEngine.inputNode.removeTap(onBus: 0)
        micConverter = nil
    }

    // MARK: - 系统声音

    private func startSystemCapture() {
        let capture = SystemAudioCapture(targetRate: sampleRate, targetChannels: channelCount) { [weak self] samples in
            self?.systemRing.write(samples)
        }
        systemCapture = capture
        Task {
            try? await capture.start()
        }
    }

    // MARK: - 混音 + 写文件

    private func startMixer() {
        let timer = DispatchSource.makeTimerSource(queue: mixerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.mixerTick() }
        timer.resume()
        mixerTimer = timer
    }

    private func mixerTick() {
        lock.lock()
        let recording = isRecording
        lock.unlock()
        guard recording, let file else { return }
        let processing = file.processingFormat

        let frames = AVAudioFrameCount(blockFrames)
        guard let out = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: frames) else { return }
        out.frameLength = frames

        var a = [Float](repeating: 0, count: blockFrames)
        var b = [Float](repeating: 0, count: blockFrames)
        let micActive = micEnabled ? micRing.read(&a) : 0
        let sysActive = systemEnabled ? systemRing.read(&b) : 0
        _ = micActive
        _ = sysActive

        let activeCount = (micEnabled ? 1 : 0) + (systemEnabled ? 1 : 0)
        let scale: Float = activeCount >= 2 ? 0.5 : 1.0

        guard let dst = out.floatChannelData?[0] else { return }
        for i in 0..<blockFrames {
            let v = (a[i] + b[i]) * scale
            dst[i] = max(-1, min(1, v))
        }
        try? file.write(from: out)

        lock.lock(); frameCount += Int64(blockFrames); lock.unlock()
    }

    private func flushRings() {
        guard let file else { return }
        let processing = file.processingFormat
        let frames = AVAudioFrameCount(blockFrames)
        while true {
            var a = [Float](repeating: 0, count: blockFrames)
            var b = [Float](repeating: 0, count: blockFrames)
            let ac = micRing.read(&a)
            let bc = systemRing.read(&b)
            if ac == 0 && bc == 0 { break }
            guard let out = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: frames) else { break }
            out.frameLength = frames
            guard let dst = out.floatChannelData?[0] else { break }
            let scale: Float = (micEnabled && systemEnabled) ? 0.5 : 1.0
            for i in 0..<blockFrames {
                let v = (a[i] + b[i]) * scale
                dst[i] = max(-1, min(1, v))
            }
            try? file.write(from: out)
        }
    }

    // MARK: - 输出文件

    /// 开始录音时创建临时 AAC(m4a) 文件。
    private func createFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("allscene-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        file = f
        fileURL = url
    }

    // MARK: - 定时器与资源

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let sec = Int(self.frameCount) / Int(self.sampleRate)
            self.lock.unlock()
            DispatchQueue.main.async {
                self.elapsedLabel = Self.formatElapsed(sec)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func beginActivity() {
        endActivity()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "全场景录音进行中"
        )
    }

    private func endActivity() {
        if let a = activity {
            ProcessInfo.processInfo.endActivity(a)
        }
        activity = nil
    }

    private static func formatElapsed(_ total: Int) -> String {
        let clamped = max(0, total)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}