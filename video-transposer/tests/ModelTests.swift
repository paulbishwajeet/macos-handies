//
// ModelTests.swift
//
// Tests for VideoModel's job handling, compiled with VideoModel.swift and
// VideoEngine.swift by run-tests.sh. Exits non-zero if any check fails.

import Foundation

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

@MainActor
func waitUntil(_ condition: () -> Bool, timeout: Double = 30) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@main
struct ModelTests {
    @MainActor
    static func main() async {
        guard let tools = Tools.locate() else {
            print("FAIL: ffmpeg/ffprobe not found")
            exit(1)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("videotools-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.mp4"), b = dir.appendingPathComponent("b.mp4")
        for clip in [a, b] {
            try! runTool(tools.ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25",
                                        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "10",
                                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", clip.path])
        }

        await testJobSurvivesOpeningVideos(a, b)

        if failures == 0 {
            print("All model tests passed.")
        } else {
            print("\(failures) check(s) failed.")
            exit(1)
        }
    }

    /// Only one ffmpeg job runs at a time: opening a video (another one, or the
    /// same one again) must not re-enable the buttons or hide the job's result.
    @MainActor
    static func testJobSurvivesOpeningVideos(_ a: URL, _ b: URL) async {
        let model = VideoModel()
        model.open(LaunchRequest(tab: .transpose, path: a.path))
        await waitUntil { model.info != nil }
        model.transpose(semitones: -1)
        check(model.job.isRunning, "transpose is running")

        model.open(LaunchRequest(tab: .cut, path: b.path))
        check(model.job.isRunning, "job still running after opening another video")
        model.open(LaunchRequest(tab: .transpose, path: a.path))
        check(model.job.isRunning, "job still running after re-opening the same video")
        await waitUntil { model.info != nil }
        check(!model.canAct, "buttons stay disabled while the job runs")

        await waitUntil { !model.job.isRunning }
        let expected = transposeOutputURL(for: a, semitones: -1)
        check(model.job == .succeeded(expected), "job result is shown, got \(model.job)")
        check(model.canAct, "buttons enabled again once the job is done")
    }
}
