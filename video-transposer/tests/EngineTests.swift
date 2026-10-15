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
}
