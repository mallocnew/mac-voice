import AVFoundation
import Combine
import Foundation

enum AudioPlaybackError: LocalizedError {
    case missingFile
    case unsupported
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "没有可播放的音频"
        case .unsupported:
            return "当前格式暂不支持试听，仍可转写或导出"
        case .failed(let message):
            return "播放失败：\(message)"
        }
    }
}

/// 按句回听的音频区间（秒）。起止点来自云端 VAD 结果。
struct PlaybackRange: Equatable {
    let start: Double
    let end: Double
}

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?
    /// 当前按句回听的区间（云端 VAD 起止），无则 nil。
    @Published private(set) var activeRange: PlaybackRange?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var segmentEndObserver: Any?
    private var loadedURL: URL?

    var currentTimeLabel: String { Self.format(currentTime) }
    var durationLabel: String { Self.format(duration) }
    /// 当前已加载音频的路径（用于判断是否需要重新 load）。
    var loadedURLPath: String? { loadedURL?.path }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    func load(_ url: URL?) {
        stop()
        clearObservers()
        clearSegmentPlayback()
        player = nil
        loadedURL = nil
        isReady = false
        currentTime = 0
        duration = 0
        lastError = nil

        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = AudioPlaybackError.missingFile.localizedDescription
            return
        }

        let ext = url.pathExtension.lowercased()
        if ["ogg", "pcm"].contains(ext) {
            lastError = AudioPlaybackError.unsupported.localizedDescription
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.loadedURL = url

        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite ? seconds : 0
                    self.isReady = true
                    self.lastError = nil
                case .failed:
                    self.isReady = false
                    self.lastError = AudioPlaybackError.unsupported.localizedDescription
                    if let underlying = item.error?.localizedDescription, !underlying.isEmpty {
                        self.lastError = AudioPlaybackError.failed(underlying).localizedDescription
                    }
                default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero)
                self?.isPlaying = false
                self?.currentTime = 0
            }
        }

        // 与录音计时一致：仅按整秒刷新进度 UI，不做亚秒级实时绘制。
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = time.seconds.isFinite ? time.seconds : 0
                let displayed = Int(seconds)
                if displayed != Int(self.currentTime) {
                    self.currentTime = TimeInterval(displayed)
                }
                let playing = self.player?.rate != 0
                if self.isPlaying != playing {
                    self.isPlaying = playing
                }
            }
        }
    }

    func togglePlay() {
        guard let player, isReady else { return }
        if isPlaying {
            pause()
        } else {
            if currentTime >= duration, duration > 0 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    // MARK: - 按句回听（区间播放）

    /// 播放云端分段的 [start, end]；再次点击同一句则停止。
    func toggleSegmentPlay(start: Double, end: Double) {
        guard let player, isReady else { return }
        // 正在回听同一句 → 停止
        if let active = activeRange, active.start == start, active.end == end, isPlaying {
            stopSegmentPlayback()
            player.pause()
            isPlaying = false
            currentTime = 0
            return
        }
        // 切到别的句或重新播放
        clearSegmentObserver()
        seek(to: start)
        setupSegmentEndBoundary(at: end)
        player.play()
        isPlaying = true
        activeRange = PlaybackRange(start: start, end: end)
    }

    func stopSegmentPlayback() {
        clearSegmentObserver()
        activeRange = nil
    }

    private func setupSegmentEndBoundary(at seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        segmentEndObserver = player?.addBoundaryTimeObserver(
            forTimes: [NSValue(time: time)],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.clearSegmentObserver()
                self.activeRange = nil
                self.player?.pause()
                self.isPlaying = false
                self.currentTime = seconds
            }
        }
    }

    private func clearSegmentObserver() {
        if let segmentEndObserver, let player {
            player.removeTimeObserver(segmentEndObserver)
        }
        segmentEndObserver = nil
    }

    private func clearSegmentPlayback() {
        clearSegmentObserver()
        activeRange = nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
        clearSegmentPlayback()
    }

    func seek(to seconds: TimeInterval) {
        guard let player, duration > 0 else { return }
        let clamped = min(max(0, seconds), duration)
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func seek(progress: Double) {
        guard duration > 0 else { return }
        seek(to: duration * min(1, max(0, progress)))
    }

    private func clearObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
