//
// EngineTests.swift
//
// Assert-based tests for VideoEngine.swift. Compiled together with it by
// run-tests.sh; exits non-zero if any check fails.

import Foundation

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    check(actual == expected, "\(message): expected \(expected), got \(actual)", line: line)
}

func checkClose(_ actual: Double?, _ expected: Double, _ message: String, line: Int = #line) {
    check(actual.map { abs($0 - expected) < 1e-9 } ?? false,
          "\(message): expected \(expected), got \(String(describing: actual))", line: line)
}

@main
struct EngineTests {
    static func main() {
        testLaunchURL()
        testParseTime()
        testFormatTimes()
        testSemitones()
        testNaming()
        testKeyframes()
        testPlanCut()
        testStatusLine()
        testWithFFmpeg()
        if failures == 0 {
            print("All engine tests passed.")
        } else {
            print("\(failures) check(s) failed.")
            exit(1)
        }
    }

    // MARK: - Pure

    static func testLaunchURL() {
        let path = "/Users/me/Downloads/it's a clip & more #1?.mp4"
        var c = URLComponents()
        c.scheme = "videotools"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "tab", value: "cut"), URLQueryItem(name: "path", value: path)]
        // Encode like JavaScript's encodeURIComponent does in the workflow.
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let url = URL(string: "videotools://open?tab=cut&path=\(encoded)")!
        checkEqual(parseLaunchURL(url), LaunchRequest(tab: .cut, path: path), "launch URL with special characters")
        checkEqual(parseLaunchURL(c.url!), LaunchRequest(tab: .cut, path: path), "launch URL from URLComponents")
        // Exactly what the Quick Action's encodeURIComponent produces (it leaves ' unencoded).
        let fromWorkflow = "videotools://open?tab=cut&path=%2FUsers%2Fme%2FDownloads%2Fit's%20a%20clip%20%26%20more%20%231%3F.mp4"
        checkEqual(parseLaunchURL(URL(string: fromWorkflow)!), LaunchRequest(tab: .cut, path: path),
                   "launch URL as the workflow encodes it")
        checkEqual(parseLaunchURL(URL(string: "videotools://open?tab=transpose&path=%2Fa.mov")!),
                   LaunchRequest(tab: .transpose, path: "/a.mov"), "transpose tab")
        checkEqual(parseLaunchURL(URL(string: "videotools://open?tab=resize&path=%2Fa.mov")!), nil, "unknown tab")
        checkEqual(parseLaunchURL(URL(string: "videotools://open?tab=cut")!), nil, "missing path")
        checkEqual(parseLaunchURL(URL(string: "other://open?tab=cut&path=%2Fa.mov")!), nil, "wrong scheme")
    }

    static func testParseTime() {
        checkClose(parseTime("12"), 12, "ss")
        checkClose(parseTime("398"), 398, "ss above 59")
        checkClose(parseTime("12.5"), 12.5, "ss.xx")
        checkClose(parseTime("6:38"), 398, "m:ss")
        checkClose(parseTime("6:38.17"), 398.17, "m:ss.xx")
        checkClose(parseTime("75:00"), 4500, "minutes above 59")
        checkClose(parseTime("1:02:03"), 3723, "h:mm:ss")
        checkClose(parseTime("1:02:03.5"), 3723.5, "h:mm:ss.xx")
        checkClose(parseTime(" 6:38 "), 398, "surrounding spaces")
        for bad in ["", "abc", "6:5", "6:75", "-3", "1:2:03", "1:02:60", "6:38:", ":38", "6,5", "1:02:03:04", "6.38.1"] {
            checkEqual(parseTime(bad), nil, "invalid time \"\(bad)\"")
        }
    }

    static func testFormatTimes() {
        checkEqual(formatClock(398), "06:38.00", "clock")
        checkEqual(formatClock(431.17), "07:11.17", "clock hundredths")
        checkEqual(formatClock(4500.5), "75:00.50", "clock above an hour")
        checkEqual(formatClock(0), "00:00.00", "clock zero")
        checkEqual(formatNameTime(398.9), "6m38s", "name time rounds down")
        checkEqual(formatNameTime(12), "0m12s", "name time under a minute")
        checkEqual(formatNameTime(4500), "75m00s", "name time above an hour")
    }

    static func testSemitones() {
        checkEqual(parseSemitones("-1"), -1, "-1")
        checkEqual(parseSemitones("+2"), 2, "+2")
        checkEqual(parseSemitones(" 12 "), 12, "12 with spaces")
        checkEqual(parseSemitones("-12"), -12, "-12")
        for bad in ["0", "13", "-13", "1.5", "", "abc", "--1", "99999999999999999999"] {
            checkEqual(parseSemitones(bad), nil, "invalid semitones \"\(bad)\"")
        }
    }

    static func testNaming() {
        let input = URL(fileURLWithPath: "/v/Bole Chudiyan - karaoke_down1st.mp4")
        checkEqual(cutOutputURL(for: input, from: 398, to: 431.17).path,
                   "/v/Bole Chudiyan - karaoke_down1st-cut6m38s-7m11s.mp4", "middle cut name")
        checkEqual(cutOutputURL(for: input, from: 0, to: 12).lastPathComponent,
                   "Bole Chudiyan - karaoke_down1st-cut0m00s-0m12s.mp4", "start cut name")
        checkEqual(cutOutputURL(for: input, from: 398, to: 439).lastPathComponent,
                   "Bole Chudiyan - karaoke_down1st-cut6m38s-7m19s.mp4", "end cut name")
        let upper = URL(fileURLWithPath: "/v/clip.MOV")
        checkEqual(cutOutputURL(for: upper, from: 1, to: 2).lastPathComponent, "clip-cut0m01s-0m02s.MOV",
                   "extension case kept")
        checkEqual(transposeOutputURL(for: input, semitones: -1).lastPathComponent,
                   "Bole Chudiyan - karaoke_down1st-transposedDown1.mp4", "transpose down name")
        checkEqual(transposeOutputURL(for: upper, semitones: 3).lastPathComponent,
                   "clip-transposedUp3.MOV", "transpose up name")
        check(needsFaststart(upper), "faststart for .MOV")
        check(needsFaststart(input), "faststart for .mp4")
        check(!needsFaststart(URL(fileURLWithPath: "/v/a.mkv")), "no faststart for .mkv")
    }

    static let kf = [0.0, 2.0, 4.0, 6.0, 8.0].map { Keyframe(time: $0, text: String(format: "%.6f", $0)) }

    static func testKeyframes() {
        let csv = "0.000000,K__\n0.040000,___\n2.000000,K__\nN/A,K__\n4.000000,K_D\n"
        checkEqual(parseKeyframes(csv: csv).map(\.text), ["0.000000", "2.000000", "4.000000"], "parse keyframes")
        // .ts/.mts files start at a non-zero timestamp: times become relative
        // to the file's start, while ffmpeg still gets the raw text.
        let ts = parseKeyframes(csv: "11.400000,K__,\n13.400000,K__,\n", startTime: 11.4)
        checkEqual(ts.map(\.text), ["11.400000", "13.400000"], "offset keyframes keep raw text")
        check(ts.count == 2 && abs(ts[0].time) < 1e-9 && abs(ts[1].time - 2) < 1e-9,
              "offset keyframes relative to start, got \(ts.map(\.time))")
        checkEqual(firstKeyframe(atOrAfter: 5, in: kf)?.time, 6, "next keyframe")
        checkEqual(firstKeyframe(atOrAfter: 6, in: kf)?.time, 6, "end exactly on a keyframe")
        checkEqual(firstKeyframe(atOrAfter: 8.5, in: kf), nil, "end after the last keyframe")
        checkEqual(firstKeyframe(atOrAfter: 0, in: kf)?.time, 0, "time zero")
    }

    static func testPlanCut() {
        checkEqual(planCut(start: 3, end: 5, duration: 10, keyframes: kf), .middle(start: 3, resume: kf[3]), "middle")
        checkEqual(planCut(start: 0, end: 3, duration: 10, keyframes: kf), .fromStart(resume: kf[2]), "from start")
        checkEqual(planCut(start: 7, end: 9, duration: 10, keyframes: kf), .toEnd(start: 7), "to end")
        checkEqual(planCut(start: 0, end: 9, duration: 10, keyframes: kf), nil, "whole video")
        checkEqual(planCut(start: 5, end: 5, duration: 10, keyframes: kf), nil, "start == end")
        checkEqual(planCut(start: 6, end: 5, duration: 10, keyframes: kf), nil, "start > end")
        checkEqual(planCut(start: 3, end: 11, duration: 10, keyframes: kf), nil, "end past duration")
        checkEqual(planCut(start: 3, end: 10, duration: 10, keyframes: kf), .toEnd(start: 3), "end == duration")
    }

    static func testStatusLine() {
        let kf2 = [Keyframe(time: 0, text: "0.000000"), Keyframe(time: 431.17, text: "431.170000")]
        checkEqual(cutStatusLine(start: 398, end: 431, duration: 439, keyframes: kf2),
                   "Removes 06:38.00 → 07:11.17 (33.17s). Resumes at keyframe +0.17s after End.", "middle status")
        checkEqual(cutStatusLine(start: 0, end: 3, duration: 10, keyframes: kf),
                   "Removes the start through 00:04.00.", "start status")
        checkEqual(cutStatusLine(start: 7, end: 9, duration: 10, keyframes: kf),
                   "Removes 00:07.00 to the end.", "end status")
        checkEqual(cutStatusLine(start: 3, end: 5, duration: 10, keyframes: nil), "Finding keyframes…", "loading")
        checkEqual(cutStatusLine(start: nil, end: 5, duration: 10, keyframes: kf), "Enter Start and End.", "missing")
        checkEqual(cutStatusLine(start: 5, end: 3, duration: 10, keyframes: kf),
                   "Start must be before End, and End within the video (00:10.00).", "bad range")
        checkEqual(cutStatusLine(start: 0, end: 9, duration: 10, keyframes: kf),
                   "That would remove the whole video.", "whole video")
    }

    // MARK: - Real ffmpeg runs

    static func testWithFFmpeg() {
        guard let tools = Tools.locate() else {
            check(false, "ffmpeg/ffprobe not found in /opt/homebrew/bin or /usr/local/bin")
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("videotools-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try testProbe(tools, dir)
            try testCuts(tools, dir)
            try testCutFailure(tools, dir)
            try testOffsetCut(tools, dir)
            try testTranspose(tools, dir)
        } catch {
            check(false, "unexpected error: \(error)")
        }
    }

    /// A 10s 25fps clip with keyframes every 2s and, optionally, a 440 Hz tone.
    static func makeClip(_ tools: Tools, _ url: URL, seconds: Int = 10, audio: Bool = true) throws {
        var args = ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25"]
        if audio { args += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100"] }
        args += ["-t", "\(seconds)", "-c:v", "libx264", "-g", "50", "-keyint_min", "50",
                 "-sc_threshold", "0", "-pix_fmt", "yuv420p"]
        if audio { args += ["-c:a", "aac", "-shortest"] }
        try runTool(tools.ffmpeg, args + [url.path])
    }

    /// MD5 of every decoded video frame, in order.
    static func frameHashes(_ tools: Tools, _ url: URL) throws -> [String] {
        let data = try runTool(tools.ffmpeg, ["-v", "error", "-i", url.path, "-map", "0:v", "-f", "framemd5", "-"])
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }
            .compactMap { $0.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) }
    }

    static func testProbe(_ tools: Tools, _ dir: URL) throws {
        let clip = dir.appendingPathComponent("probe.mp4")
        try makeClip(tools, clip)
        let info = try probeMedia(clip, tools: tools)
        check(abs(info.duration - 10) < 0.1, "clip duration ~10s, got \(info.duration)")
        check(info.hasVideo, "clip has video")
        checkEqual(info.audioSampleRate, 44100, "clip sample rate")
        checkEqual(try readKeyframes(clip, tools: tools).map(\.time), [0, 2, 4, 6, 8], "clip keyframes")

        let silent = dir.appendingPathComponent("silent.mp4")
        try makeClip(tools, silent, seconds: 4, audio: false)
        let silentInfo = try probeMedia(silent, tools: tools)
        checkEqual(silentInfo.audioSampleRate, nil, "no-audio clip has no sample rate")
        check(silentInfo.hasVideo, "no-audio clip has video")

        let junk = dir.appendingPathComponent("junk.mp4")
        try "not a video".write(to: junk, atomically: true, encoding: .utf8)
        check((try? probeMedia(junk, tools: tools)) == nil, "unreadable file throws")
    }

    static func testCuts(_ tools: Tools, _ dir: URL) throws {
        // Spaces, an apostrophe and non-ASCII in the name, like real downloads.
        let clip = dir.appendingPathComponent("it's a clip – ü.mp4")
        try makeClip(tools, clip)
        let original = try frameHashes(tools, clip)
        checkEqual(original.count, 250, "original frame count")
        let keyframes = try readKeyframes(clip, tools: tools)

        // Middle: remove 3s-5s, resumes at the 6s keyframe (frame 150).
        let middlePlan = planCut(start: 3, end: 5, duration: 10, keyframes: keyframes)!
        let middle = try performCut(input: clip, plan: middlePlan, duration: 10, tools: tools)
        checkEqual(middle.lastPathComponent, "it's a clip – ü-cut0m03s-0m06s.mp4", "middle output name")
        let m = try frameHashes(tools, middle)
        // Part 1 can overrun Start by a few frames (2 measured with x264 B-frames).
        check((175...178).contains(m.count), "middle cut keeps 175-178 frames, got \(m.count)")
        checkEqual(Array(m.prefix(75)), Array(original.prefix(75)), "frames before Start kept")
        checkEqual(Array(m.suffix(100)), Array(original[150...]), "frames after the join match the original at K")

        // Start: remove 0-3s, resumes at the 4s keyframe (frame 100).
        let startPlan = planCut(start: 0, end: 3, duration: 10, keyframes: keyframes)!
        let start = try performCut(input: clip, plan: startPlan, duration: 10, tools: tools)
        checkEqual(start.lastPathComponent, "it's a clip – ü-cut0m00s-0m04s.mp4", "start output name")
        checkEqual(try frameHashes(tools, start), Array(original[100...]), "start cut keeps frames from K")

        // End: remove 7s-9s, no keyframe after 9s, so everything from 7s goes.
        let endPlan = planCut(start: 7, end: 9, duration: 10, keyframes: keyframes)!
        let end = try performCut(input: clip, plan: endPlan, duration: 10, tools: tools)
        checkEqual(end.lastPathComponent, "it's a clip – ü-cut0m07s-0m10s.mp4", "end output name")
        let e = try frameHashes(tools, end)
        check((175...178).contains(e.count), "end cut keeps 175-178 frames, got \(e.count)")
        checkEqual(Array(e.prefix(175)), Array(original.prefix(175)), "end cut keeps frames before Start")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("videotools-") && !$0.hasPrefix("videotools-tests-") }
        checkEqual(leftovers, [], "concat temp folders removed")
    }

    /// A transport stream starting at 11.4s, like camcorder .MTS files: marks are
    /// on a timeline from 0, and the cut must resume at the keyframe the status
    /// line names.
    static func testOffsetCut(_ tools: Tools, _ dir: URL) throws {
        let mp4 = dir.appendingPathComponent("offset-source.mp4")
        try makeClip(tools, mp4)
        let clip = dir.appendingPathComponent("cam.ts")
        try runTool(tools.ffmpeg, ["-v", "error", "-y", "-i", mp4.path, "-c", "copy",
                                   "-output_ts_offset", "10", clip.path])
        let original = try frameHashes(tools, clip)
        checkEqual(original.count, 250, "offset clip frame count")
        let keyframes = try readKeyframes(clip, tools: tools)
        check(keyframes.count == 5 && keyframes.allSatisfy { abs($0.time - $0.time.rounded()) < 0.05 }
              && abs(keyframes[3].time - 6) < 0.05,
              "offset keyframes near 0, 2, 4, 6, 8, got \(keyframes.map(\.time))")

        let plan = planCut(start: 3, end: 5, duration: 10, keyframes: keyframes)!
        check(abs((plan.resume?.time ?? 0) - 6) < 0.05, "offset cut resumes near 6s, got \(String(describing: plan.resume))")
        let output = try performCut(input: clip, plan: plan, duration: 10, tools: tools)
        checkEqual(output.lastPathComponent, "cam-cut0m03s-0m06s.ts", "offset output name")
        let m = try frameHashes(tools, output)
        check((175...178).contains(m.count), "offset middle cut keeps 175-178 frames, got \(m.count)")
        checkEqual(Array(m.prefix(75)), Array(original.prefix(75)), "offset: frames before Start kept")
        checkEqual(Array(m.suffix(100)), Array(original[150...]), "offset: frames after the join match the original at K")
    }

    static func testCutFailure(_ tools: Tools, _ dir: URL) throws {
        let junk = dir.appendingPathComponent("broken.mp4")
        try "not a video".write(to: junk, atomically: true, encoding: .utf8)
        let plan = CutPlan.middle(start: 1, resume: Keyframe(time: 2, text: "2.000000"))
        do {
            _ = try performCut(input: junk, plan: plan, duration: 3, tools: tools)
            check(false, "cutting a broken file should throw")
        } catch let error as EngineError {
            check(!error.message.isEmpty, "failure carries ffmpeg's error output")
        }
        let output = cutOutputURL(for: junk, plan: plan, duration: 3)
        check(!FileManager.default.fileExists(atPath: output.path), "no partial output left behind")
    }

    /// Dominant frequency of the audio between 1s and 3s, by counting upward zero crossings.
    static func measureTone(_ tools: Tools, _ url: URL) throws -> Double {
        let pcm = try runTool(tools.ffmpeg, ["-v", "error", "-i", url.path, "-map", "0:a", "-ac", "1",
                                             "-ar", "44100", "-f", "s16le", "-"])
        let samples = pcm.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let window = samples[44100..<(3 * 44100)]
        var crossings = 0
        var previous = window.first!
        for s in window.dropFirst() {
            if previous < 0 && s >= 0 { crossings += 1 }
            previous = s
        }
        return Double(crossings) / 2.0
    }

    static func testTranspose(_ tools: Tools, _ dir: URL) throws {
        let clip = dir.appendingPathComponent("tone.mp4")
        try makeClip(tools, clip)
        checkEqual(transposeFilter(sampleRate: 44100, semitones: -1),
                   "asetrate=41624.8572,aresample=44100,atempo=1.0594630944", "filter for -1")
        for n in [-1, 2] {
            let out = try performTranspose(input: clip, semitones: n, sampleRate: 44100, tools: tools)
            let expected = 440 * pow(2, Double(n) / 12)
            let measured = try measureTone(tools, out)
            check(abs(measured - expected) / expected < 0.01,
                  "tone after \(n) semitones: expected \(expected), measured \(measured)")
            let info = try probeMedia(out, tools: tools)
            check(abs(info.duration - 10) < 0.1, "transposed duration unchanged, got \(info.duration)")
            check(info.hasVideo, "transposed output keeps video")
        }
        check(abs(try measureTone(tools, clip) - 440) / 440 < 0.01, "original tone is 440 Hz")
    }
}
