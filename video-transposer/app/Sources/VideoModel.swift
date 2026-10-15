//
// VideoModel.swift
//
// State shared by the window and both tabs: the loaded video, its probe
// results and keyframes, the player, and the running/finished job.

import AppKit
import AVFoundation
import Observation

enum JobState: Equatable {
    case idle
    case running(String)
    case succeeded(URL)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

@MainActor
@Observable
final class VideoModel {
    var tab: Tab = .transpose
    private(set) var url: URL?
    private(set) var info: MediaInfo?
    /// nil while still being read.
    private(set) var keyframes: [Keyframe]?
    /// Set when the file can't be read or has no video; replaces the player.
    private(set) var loadError: String?
    private(set) var keyframeError: String?
    private(set) var currentTime: Double = 0
    private(set) var job: JobState = .idle

    let player = AVPlayer()
    let tools = Tools.locate()

    @ObservationIgnored private var timeObserver: Any?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                if time.isNumeric { self?.currentTime = time.seconds }
            }
        }
    }

    /// Ready for Cut/Transpose: tools found, video readable, nothing running.
    var canAct: Bool {
        tools != nil && info?.hasVideo == true && loadError == nil && !job.isRunning
    }

    func open(_ request: LaunchRequest) {
        let url = URL(fileURLWithPath: request.path)
        tab = request.tab
        self.url = url
        info = nil
        keyframes = nil
        loadError = nil
        keyframeError = nil
        if !job.isRunning { job = .idle }
        currentTime = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))

        guard let tools else { return }
        Task.detached {
            let result = Result { try probeMedia(url, tools: tools) }
            await MainActor.run {
                // A newer video may have been opened meanwhile; drop stale results.
                guard self.url == url else { return }
                switch result {
                case .success(let info) where info.hasVideo:
                    self.info = info
                case .success:
                    self.loadError = "\(url.lastPathComponent) has no video stream."
                case .failure:
                    self.loadError = "Could not read \(url.lastPathComponent) as a video."
                }
            }
        }
        Task.detached {
            let result = Result { try readKeyframes(url, tools: tools) }
            await MainActor.run {
                guard self.url == url else { return }
                switch result {
                case .success(let keyframes): self.keyframes = keyframes
                case .failure(let error): self.keyframeError = (error as? EngineError)?.message ?? "\(error)"
                }
            }
        }
    }

    func stepFrame(_ count: Int) {
        player.pause()
        player.currentItem?.step(byCount: count)
    }

    func cut(_ plan: CutPlan) {
        guard let url, let info, let tools else { return }
        run("Cutting…") { try performCut(input: url, plan: plan, duration: info.duration, tools: tools) }
    }

    func transpose(semitones: Int) {
        guard let url, let rate = info?.audioSampleRate, let tools else { return }
        run("Transposing…") { try performTranspose(input: url, semitones: semitones, sampleRate: rate, tools: tools) }
    }

    func showInFinder(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// Only one job runs at a time. Opening another video doesn't cancel or
    /// hide it; its result names the output file, so it always lands.
    private func run(_ label: String, _ work: @escaping @Sendable () throws -> URL) {
        guard !job.isRunning else { return }
        job = .running(label)
        Task.detached {
            let result = Result { try work() }
            await MainActor.run {
                switch result {
                case .success(let output): self.job = .succeeded(output)
                case .failure(let error): self.job = .failed((error as? EngineError)?.message ?? "\(error)")
                }
            }
        }
    }
}
