# Video Tools App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Transpose audio" AppleScript dialog with a native SwiftUI app, **Video Tools.app**, that previews one video and offers two tabs, Transpose audio and Cut video (stream-copy removal of one section), opened from two Finder Quick Actions.

**Architecture:** All non-UI logic (time parsing, naming, keyframe snapping, ffprobe/ffmpeg calls) lives in one Foundation-only file, `VideoEngine.swift`, that a separate `swiftc` test binary compiles and exercises against real ffmpeg runs on generated clips. A thin SwiftUI layer (`VideoModel` + views) calls the engine on background tasks. The Quick Actions are tiny launchers that `open videotools://open?tab=…&path=…`; the app's `NSApplicationDelegate` receives the URL whether or not the app is running.

**Tech Stack:** Swift 6.1 compiler (Swift 5 language mode, the `swiftc` default), SwiftUI + AVKit + Observation (macOS 14), Command Line Tools `swiftc` only (no Xcode project), Homebrew `ffmpeg`/`ffprobe`, Automator Quick Actions, bash.

**Spec:** `docs/superpowers/specs/2026-10-14-video-tools-app-design.md`

## Global Constraints

- Bundle id `com.macoshandies.videotools`; URL scheme `videotools`; executable `VideoTools`; app name `Video Tools.app`.
- Compile with `swiftc -target arm64-apple-macos14 -O -parse-as-library`; arm64 only, no universal binary; ad-hoc sign with `codesign -s -`.
- ffmpeg/ffprobe are found at `/opt/homebrew/bin` then `/usr/local/bin`.
- Cutting is stream copy only (`-c copy`); resume at the first keyframe **at or after** End; one section per cut.
- Keyframe times are passed to ffmpeg exactly as ffprobe printed them.
- `-movflags +faststart` on the final write only when the extension is `mp4`, `m4v` or `mov` (case-insensitive).
- Cut output: `<name>-cut<A>-<B>.<ext>`, times rounded down, `<minutes>m<ss>s`, minutes unpadded and may exceed 59.
- Transpose output: `<name>-transposedDown<N>.<ext>` / `<name>-transposedUp<N>.<ext>`; semitones are whole numbers −12…12, not 0, default −1 every time the tab opens.
- Transpose filter `asetrate=SR·r,aresample=SR,atempo=1/r`, r = 2^(semitones/12); audio `aac` at `256k`; video `-c:v copy`; writes straight to the final name.
- Existing output with the same name is overwritten; on failure any partial output is deleted and ffmpeg's error text is shown.
- Footer text: `aipathstudio · https://aipathstudio.com`.
- `scripts/transpose-audio.sh` and the `scripts/` folder are deleted; there is no command-line `--semitones` mode any more.
- Out of scope: `.pkg`, notarization, universal binary, dragging on the timeline, live pitch preview, multiple sections per cut, batch processing.

## Review Focus

1. **File names with spaces, apostrophes, non-ASCII, `&`, `#`, `?`** (real downloads look like `Bole Chudiyan - karaoke_down1st.mp4`): the launch URL must round-trip the path and ffmpeg must get it intact. Pinned in Task 1 (`testLaunchURL` with `it's a clip & more #1?.mp4`) and Task 2 (cuts run on `it's a clip – ü.mp4`).
2. **ffmpeg failing partway through a cut** (corrupt file, disk full): no partial output file left next to the original, concat temp folder removed. Pinned in Task 2 (`testCutFailure`, temp-folder leftover check in `testCuts`).
3. **Uppercase extensions** (`.MOV` from iPhones, `.MP4`): output keeps the original case and still gets `+faststart`. Pinned in Task 1 (`testNaming`).
4. **Videos longer than an hour**: `75:00`, `1:02:03.5` parse; clock shows `75:00.50`; names show `75m00s`. Pinned in Task 1 (`testParseTime`, `testFormatTimes`).
5. **A second Quick Action fired while the first video is still loading or cutting**: late results for the old video must not overwrite the new one's state. Handled by the `self.url == url` guards in `VideoModel`; pinned by the back-to-back launch check in Task 3, Step 7.

## Notes on the spec (decisions made while planning, all verified on this Mac)

- **Extra file `app/Sources/VideoModel.swift`** holds shared state (the spec's layout didn't name one). `VideoEngine.swift` sits in `app/Sources/` so `build-app.sh` compiles it into the app; the test runner compiles it on its own.
- **Cut tests check decoded frame hashes (`-f framemd5`) instead of PSNR.** Stream copy means kept frames decode bit-identically, so "frames after the join equal the original from K" is checked exactly.
- **Part 1 overruns Start by up to 2 frames**, not 1, on x264 clips with B-frames (measured: 77 frames kept for Start = 3s at 25 fps). The tests allow up to 3 extra frames. Container duration also includes AAC padding, so the tests count video frames rather than comparing durations.
- **Status lines for incomplete marks** that the spec didn't word: "Enter Start and End.", "Start must be before End, and End within the video (mm:ss.xx).", "That would remove the whole video."
- **Closing the window quits the app** (`applicationShouldTerminateAfterLastWindowClosed`), so a later Quick Action always finds a window to load into.
- **LaunchServices won't bind a URL scheme for an app under `/private/tmp`.** Manual testing uses `video-transposer/build/`; `install.sh` unregisters that build copy after installing to `~/Applications` so the two copies never compete.
- **Screenshots:** capture only the app window (`screencapture -l <window id>`, id from a `CGWindowListCopyWindowInfo` helper; the owner name is `Video Tools`). Never script System Events (it pops an Accessibility prompt) and never capture the full screen.
- **Validated during planning:** a SwiftUI + AVKit app builds with CLT `swiftc`; a cold launch via `open "videotools://open?tab=cut&path=…"` loads the video on the Cut tab; a second URL to the running app swaps the video and switches tabs. **Still to validate (Task 4, by the user):** that `open` with the custom URL works from inside a Finder Quick Action.

---

### Task 1: Engine — pure logic and test runner

**Files:**
- Create: `video-transposer/app/Sources/VideoEngine.swift` (pure part)
- Create: `video-transposer/tests/EngineTests.swift` (pure part)
- Create: `video-transposer/tests/run-tests.sh`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 2–3):
  - `enum Tab: String { case transpose, cut }`, `struct LaunchRequest: Equatable { let tab: Tab; let path: String }`, `func parseLaunchURL(_ url: URL) -> LaunchRequest?`
  - `func parseTime(_ text: String) -> Double?`, `func formatClock(_ seconds: Double) -> String` (`"06:38.00"`), `func formatNameTime(_ seconds: Double) -> String` (`"6m38s"`)
  - `func parseSemitones(_ text: String) -> Int?`
  - `func cutOutputURL(for input: URL, from a: Double, to b: Double) -> URL`, `func cutOutputURL(for input: URL, plan: CutPlan, duration: Double) -> URL`, `func transposeOutputURL(for input: URL, semitones: Int) -> URL`, `func needsFaststart(_ url: URL) -> Bool`
  - `struct Keyframe: Equatable { let time: Double; let text: String }`, `func parseKeyframes(csv: String) -> [Keyframe]`, `func firstKeyframe(atOrAfter time: Double, in keyframes: [Keyframe]) -> Keyframe?`
  - `enum CutPlan: Equatable { case middle(start: Double, resume: Keyframe); case fromStart(resume: Keyframe); case toEnd(start: Double) }` with `var start: Double` and `var resume: Keyframe?`
  - `func planCut(start: Double, end: Double, duration: Double, keyframes: [Keyframe]) -> CutPlan?`
  - `func cutStatusLine(start: Double?, end: Double?, duration: Double?, keyframes: [Keyframe]?) -> String`
  - Test helpers in `EngineTests.swift`: `check`, `checkEqual`, `checkClose`, `static let kf` (keyframes 0, 2, 4, 6, 8).

- [ ] **Step 1: Create the test runner**

`video-transposer/tests/run-tests.sh`:

```bash
#!/bin/bash
#
# Compiles VideoEngine.swift with EngineTests.swift into a throwaway binary
# and runs it. Exits non-zero if any check fails. Needs ffmpeg installed.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

swiftc -target arm64-apple-macos14 -parse-as-library -o "$BUILD_DIR/engine-tests" \
  "$TESTS_DIR/../app/Sources/VideoEngine.swift" "$TESTS_DIR/EngineTests.swift"
"$BUILD_DIR/engine-tests"
```

Run: `chmod +x video-transposer/tests/run-tests.sh`

- [ ] **Step 2: Write the failing tests**

`video-transposer/tests/EngineTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `video-transposer/tests/run-tests.sh`
Expected: `error: no such file or directory: '…/app/Sources/VideoEngine.swift'` and a non-zero exit (the engine doesn't exist yet).

- [ ] **Step 4: Write the implementation**

`video-transposer/app/Sources/VideoEngine.swift`:

```swift
//
// VideoEngine.swift
//
// Everything Video Tools does that isn't UI: parsing and formatting times,
// output naming, choosing where a cut resumes, and running ffprobe/ffmpeg.
// It imports only Foundation so tests/EngineTests.swift can compile it alone.

import Foundation

// MARK: - Launch URLs

enum Tab: String {
    case transpose
    case cut
}

struct LaunchRequest: Equatable {
    let tab: Tab
    let path: String
}

/// Parses `videotools://open?tab=cut&path=<percent-encoded path>`.
func parseLaunchURL(_ url: URL) -> LaunchRequest? {
    guard url.scheme == "videotools", url.host == "open",
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
          let tabText = items.first(where: { $0.name == "tab" })?.value,
          let tab = Tab(rawValue: tabText),
          let path = items.first(where: { $0.name == "path" })?.value,
          !path.isEmpty
    else { return nil }
    return LaunchRequest(tab: tab, path: path)
}

// MARK: - Times

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

/// Parses `ss`, `ss.xx`, `m:ss`, `m:ss.xx`, `h:mm:ss` or `h:mm:ss.xx` into
/// seconds. Returns nil for anything else.
func parseTime(_ text: String) -> Double? {
    let s = text.trimmingCharacters(in: .whitespaces)
    let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    switch parts.count {
    case 1:
        guard matches(s, #"^\d+(\.\d+)?$"#) else { return nil }
        return Double(s)
    case 2:
        guard matches(parts[0], #"^\d+$"#), matches(parts[1], #"^[0-5]\d(\.\d+)?$"#),
              let m = Double(parts[0]), let sec = Double(parts[1]) else { return nil }
        return m * 60 + sec
    case 3:
        guard matches(parts[0], #"^\d+$"#), matches(parts[1], #"^[0-5]\d$"#),
              matches(parts[2], #"^[0-5]\d(\.\d+)?$"#),
              let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + sec
    default:
        return nil
    }
}

/// `mm:ss.xx`, rounded to hundredths. Minutes are not capped at 59.
func formatClock(_ seconds: Double) -> String {
    let cs = Int((max(0, seconds) * 100).rounded())
    return String(format: "%02d:%02d.%02d", cs / 6000, (cs / 100) % 60, cs % 100)
}

/// `<minutes>m<ss>s`, rounded down to whole seconds, minutes unpadded.
func formatNameTime(_ seconds: Double) -> String {
    let whole = Int(max(0, seconds).rounded(.down))
    return String(format: "%dm%02ds", whole / 60, whole % 60)
}

// MARK: - Semitones

/// A whole number from -12 to 12, excluding 0, or nil.
func parseSemitones(_ text: String) -> Int? {
    let s = text.trimmingCharacters(in: .whitespaces)
    guard matches(s, #"^[+-]?\d{1,3}$"#), let n = Int(s), n != 0, abs(n) <= 12 else { return nil }
    return n
}

// MARK: - Output names

private func outputURL(for input: URL, suffix: String) -> URL {
    let ext = input.pathExtension
    let name = input.deletingPathExtension().lastPathComponent + suffix
    let dir = input.deletingLastPathComponent()
    return dir.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
}

/// `<name>-cut<A>-<B>.<ext>` next to the input.
func cutOutputURL(for input: URL, from a: Double, to b: Double) -> URL {
    outputURL(for: input, suffix: "-cut\(formatNameTime(a))-\(formatNameTime(b))")
}

/// `<name>-transposedDown<N>.<ext>` / `<name>-transposedUp<N>.<ext>`.
func transposeOutputURL(for input: URL, semitones: Int) -> URL {
    let direction = semitones < 0 ? "Down" : "Up"
    return outputURL(for: input, suffix: "-transposed\(direction)\(abs(semitones))")
}

/// Whether the final write gets `-movflags +faststart`.
func needsFaststart(_ url: URL) -> Bool {
    ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased())
}

// MARK: - Keyframes and cut planning

struct Keyframe: Equatable {
    let time: Double
    /// Exactly as ffprobe printed it; this is what gets passed to ffmpeg.
    let text: String
}

/// Parses `ffprobe ... -show_entries packet=pts_time,flags -of csv=p=0`
/// output (`0.000000,K__` per line) into sorted keyframes.
func parseKeyframes(csv: String) -> [Keyframe] {
    csv.split(whereSeparator: \.isNewline).compactMap { line -> Keyframe? in
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 2, fields[1].contains("K") else { return nil }
        let text = String(fields[0]).trimmingCharacters(in: .whitespaces)
        guard let time = Double(text) else { return nil }
        return Keyframe(time: time, text: text)
    }.sorted { $0.time < $1.time }
}

/// The first keyframe at or after `time`, or nil.
func firstKeyframe(atOrAfter time: Double, in keyframes: [Keyframe]) -> Keyframe? {
    keyframes.first { $0.time >= time - 1e-6 }
}

enum CutPlan: Equatable {
    /// Keep [0, start) and [resume, end of video].
    case middle(start: Double, resume: Keyframe)
    /// Keep [resume, end of video].
    case fromStart(resume: Keyframe)
    /// Keep [0, start).
    case toEnd(start: Double)

    var start: Double {
        switch self {
        case .middle(let start, _), .toEnd(let start): return start
        case .fromStart: return 0
        }
    }

    /// Where playback resumes, or nil when the cut runs to the end.
    var resume: Keyframe? {
        switch self {
        case .middle(_, let resume), .fromStart(let resume): return resume
        case .toEnd: return nil
        }
    }
}

/// The cut for these marks, or nil when Cut must be disabled: marks out of
/// order or outside the video, or a cut that would remove everything.
func planCut(start: Double, end: Double, duration: Double, keyframes: [Keyframe]) -> CutPlan? {
    guard start >= 0, start < end, end <= duration else { return nil }
    let resume = firstKeyframe(atOrAfter: end, in: keyframes)
    switch (start > 0, resume) {
    case (true, let k?): return .middle(start: start, resume: k)
    case (false, let k?): return .fromStart(resume: k)
    case (true, nil): return .toEnd(start: start)
    case (false, nil): return nil
    }
}

/// The Cut tab's status line for the current marks.
func cutStatusLine(start: Double?, end: Double?, duration: Double?, keyframes: [Keyframe]?) -> String {
    guard let duration, let keyframes else { return "Finding keyframes…" }
    guard let start, let end else { return "Enter Start and End." }
    guard start < end, end <= duration else {
        return "Start must be before End, and End within the video (\(formatClock(duration)))."
    }
    guard let plan = planCut(start: start, end: end, duration: duration, keyframes: keyframes) else {
        return "That would remove the whole video."
    }
    switch plan {
    case .middle(let start, let k):
        return String(format: "Removes %@ → %@ (%.2fs). Resumes at keyframe +%.2fs after End.",
                      formatClock(start), formatClock(k.time), k.time - start, k.time - end)
    case .fromStart(let k):
        return "Removes the start through \(formatClock(k.time))."
    case .toEnd(let start):
        return "Removes \(formatClock(start)) to the end."
    }
}

/// Output file for a cut: B is the resume keyframe, or the duration.
func cutOutputURL(for input: URL, plan: CutPlan, duration: Double) -> URL {
    cutOutputURL(for: input, from: plan.start, to: plan.resume?.time ?? duration)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `video-transposer/tests/run-tests.sh`
Expected: `All engine tests passed.` and exit status 0. If a check fails, fix the engine, not the expected value. Every expected value here was verified (e.g. `44100 / 2^(1/12) = 41624.8572` matches the old script's awk output).

- [ ] **Step 6: Commit**

```bash
git add video-transposer/app/Sources/VideoEngine.swift video-transposer/tests/EngineTests.swift video-transposer/tests/run-tests.sh
git commit -m "Add Video Tools engine: time parsing, naming, cut planning"
```

---

### Task 2: Engine — ffprobe/ffmpeg operations

**Files:**
- Modify: `video-transposer/app/Sources/VideoEngine.swift` (append the running section)
- Modify: `video-transposer/tests/EngineTests.swift` (append the real-ffmpeg section; add one call in `main`)

**Interfaces:**
- Consumes: everything from Task 1.
- Produces (used by Task 3):
  - `struct EngineError: Error, Equatable { let message: String }`
  - `struct Tools { let ffmpeg: URL; let ffprobe: URL; static func locate(in dirs: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) -> Tools? }`
  - `@discardableResult func runTool(_ executable: URL, _ arguments: [String]) throws -> Data`
  - `struct MediaInfo: Equatable { let duration: Double; let hasVideo: Bool; let audioSampleRate: Int? }`, `func probeMedia(_ url: URL, tools: Tools) throws -> MediaInfo`
  - `func readKeyframes(_ url: URL, tools: Tools) throws -> [Keyframe]`
  - `func performCut(input: URL, plan: CutPlan, duration: Double, tools: Tools) throws -> URL`
  - `func transposeFilter(sampleRate: Int, semitones: Int) -> String`, `func performTranspose(input: URL, semitones: Int, sampleRate: Int, tools: Tools) throws -> URL`

- [ ] **Step 1: Write the failing tests**

In `EngineTests.swift`, add `testWithFFmpeg()` as the last call in `main()`, right after `testStatusLine()`:

```swift
        testStatusLine()
        testWithFFmpeg()
```

Then add this section at the end of the `EngineTests` struct, just before its final closing `}`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `video-transposer/tests/run-tests.sh`
Expected: compile errors such as `cannot find 'Tools' in scope` and `cannot find 'runTool' in scope`.

- [ ] **Step 3: Write the implementation**

Append to the end of `VideoEngine.swift`:

```swift
// MARK: - Running ffmpeg / ffprobe

struct EngineError: Error, Equatable {
    let message: String
}

struct Tools {
    let ffmpeg: URL
    let ffprobe: URL

    /// Finds ffmpeg and ffprobe in the first directory that has both.
    static func locate(in dirs: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) -> Tools? {
        let fm = FileManager.default
        for dir in dirs {
            let ffmpeg = URL(fileURLWithPath: dir).appendingPathComponent("ffmpeg")
            let ffprobe = URL(fileURLWithPath: dir).appendingPathComponent("ffprobe")
            if fm.isExecutableFile(atPath: ffmpeg.path), fm.isExecutableFile(atPath: ffprobe.path) {
                return Tools(ffmpeg: ffmpeg, ffprobe: ffprobe)
            }
        }
        return nil
    }
}

/// Runs a tool to completion and returns its stdout. Throws EngineError with
/// its stderr when it exits non-zero.
@discardableResult
func runTool(_ executable: URL, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
        try process.run()
    } catch {
        throw EngineError(message: "Could not run \(executable.lastPathComponent): \(error.localizedDescription)")
    }
    // Drain stderr on another thread so neither pipe fills up and blocks.
    var errData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        errData = err.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    group.wait()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let text = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw EngineError(message: text.isEmpty
            ? "\(executable.lastPathComponent) exited with status \(process.terminationStatus)"
            : text)
    }
    return outData
}

struct MediaInfo: Equatable {
    let duration: Double
    let hasVideo: Bool
    /// Sample rate of the first audio stream, or nil when there is no audio.
    let audioSampleRate: Int?
}

func probeMedia(_ url: URL, tools: Tools) throws -> MediaInfo {
    let data = try runTool(tools.ffprobe, [
        "-v", "error", "-show_entries", "stream=codec_type,sample_rate:format=duration",
        "-of", "json", url.path,
    ])
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let format = json["format"] as? [String: Any],
          let durationText = format["duration"] as? String,
          let duration = Double(durationText)
    else { throw EngineError(message: "Could not read \(url.lastPathComponent) as a video.") }
    let streams = json["streams"] as? [[String: Any]] ?? []
    let hasVideo = streams.contains { $0["codec_type"] as? String == "video" }
    let audio = streams.first { $0["codec_type"] as? String == "audio" }
    let sampleRate = (audio?["sample_rate"] as? String).flatMap { Int($0) }
    return MediaInfo(duration: duration, hasVideo: hasVideo, audioSampleRate: sampleRate)
}

/// Keyframe times of the first video stream, read from packets (no decoding).
func readKeyframes(_ url: URL, tools: Tools) throws -> [Keyframe] {
    let data = try runTool(tools.ffprobe, [
        "-v", "error", "-select_streams", "v:0",
        "-show_entries", "packet=pts_time,flags", "-of", "csv=p=0", url.path,
    ])
    return parseKeyframes(csv: String(decoding: data, as: UTF8.self))
}

private let quiet = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y"]

/// Removes the planned section by stream copy and returns the output file.
/// On failure, deletes any partial output and throws EngineError.
func performCut(input: URL, plan: CutPlan, duration: Double, tools: Tools) throws -> URL {
    let output = cutOutputURL(for: input, plan: plan, duration: duration)
    let faststart = needsFaststart(output) ? ["-movflags", "+faststart"] : []
    let streams = ["-map", "0:v", "-map", "0:a?", "-c", "copy", "-avoid_negative_ts", "make_zero"]

    func part1(to url: URL, extra: [String]) throws {
        try runTool(tools.ffmpeg, quiet + ["-i", input.path, "-t", String(format: "%.6f", plan.start)]
            + streams + extra + [url.path])
    }
    func part2(from k: Keyframe, to url: URL, extra: [String]) throws {
        try runTool(tools.ffmpeg, quiet + ["-ss", k.text, "-i", input.path] + streams + extra + [url.path])
    }

    do {
        switch plan {
        case .fromStart(let k):
            try part2(from: k, to: output, extra: faststart)
        case .toEnd:
            try part1(to: output, extra: faststart)
        case .middle(_, let k):
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("videotools-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            let ext = input.pathExtension.isEmpty ? "" : ".\(input.pathExtension)"
            let seg1 = temp.appendingPathComponent("seg1\(ext)")
            let seg2 = temp.appendingPathComponent("seg2\(ext)")
            try part1(to: seg1, extra: [])
            try part2(from: k, to: seg2, extra: [])
            let list = temp.appendingPathComponent("list.txt")
            try "file '\(seg1.path)'\nfile '\(seg2.path)'\n".write(to: list, atomically: true, encoding: .utf8)
            try runTool(tools.ffmpeg, quiet + ["-f", "concat", "-safe", "0", "-i", list.path, "-c", "copy"]
                + faststart + [output.path])
        }
    } catch {
        try? FileManager.default.removeItem(at: output)
        throw error
    }
    return output
}

/// `asetrate=SR·r,aresample=SR,atempo=1/r` with r = 2^(semitones/12).
func transposeFilter(sampleRate: Int, semitones: Int) -> String {
    let r = pow(2.0, Double(semitones) / 12)
    return String(format: "asetrate=%.4f,aresample=%d,atempo=%.10f", Double(sampleRate) * r, sampleRate, 1 / r)
}

/// Pitch-shifts the audio, copies the video, and returns the output file.
/// On failure, deletes any partial output and throws EngineError.
func performTranspose(input: URL, semitones: Int, sampleRate: Int, tools: Tools) throws -> URL {
    let output = transposeOutputURL(for: input, semitones: semitones)
    do {
        try runTool(tools.ffmpeg, quiet + [
            "-i", input.path, "-map", "0:v?", "-map", "0:a", "-c:v", "copy",
            "-af", transposeFilter(sampleRate: sampleRate, semitones: semitones),
            "-c:a", "aac", "-b:a", "256k", output.path,
        ])
    } catch {
        try? FileManager.default.removeItem(at: output)
        throw error
    }
    return output
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `video-transposer/tests/run-tests.sh`
Expected: `All engine tests passed.` (takes a few seconds; it generates clips with ffmpeg). Requires `brew install ffmpeg`. If ffmpeg is missing, the run fails with `ffmpeg/ffprobe not found`.

- [ ] **Step 5: Commit**

```bash
git add video-transposer/app/Sources/VideoEngine.swift video-transposer/tests/EngineTests.swift
git commit -m "Add Video Tools engine: probing, keyframes, stream-copy cut, transpose"
```

---

### Task 3: The app — bundle, window, both tabs

**Files:**
- Create: `video-transposer/app/Info.plist`
- Create: `video-transposer/app/Sources/VideoModel.swift`
- Create: `video-transposer/app/Sources/VideoToolsApp.swift`
- Create: `video-transposer/app/Sources/ContentView.swift`
- Create: `video-transposer/app/Sources/CutTab.swift`
- Create: `video-transposer/app/Sources/TransposeTab.swift`
- Create: `video-transposer/build-app.sh`
- Create: `video-transposer/.gitignore`

**Interfaces:**
- Consumes: all engine functions and types from Tasks 1–2.
- Produces (used by Task 4): `video-transposer/build-app.sh` builds `video-transposer/build/Video Tools.app`. The app handles `videotools://open?tab=transpose|cut&path=<percent-encoded absolute path>`.

The UI has no automated tests. The engine underneath is already covered, and this task is verified by building and driving the real app (Steps 5–8).

- [ ] **Step 1: Bundle metadata and build script**

`video-transposer/app/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>com.macoshandies.videotools</string>
	<key>CFBundleName</key>
	<string>Video Tools</string>
	<key>CFBundleDisplayName</key>
	<string>Video Tools</string>
	<key>CFBundleExecutable</key>
	<string>VideoTools</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.macoshandies.videotools</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>videotools</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

`video-transposer/build-app.sh`:

```bash
#!/bin/bash
#
# Builds build/Video Tools.app from app/Sources with the Command Line Tools
# swiftc (no Xcode project), arm64 only, ad-hoc signed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/build/Video Tools.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -target arm64-apple-macos14 -O -parse-as-library \
  -o "$APP/Contents/MacOS/VideoTools" "$SCRIPT_DIR"/app/Sources/*.swift
cp "$SCRIPT_DIR/app/Info.plist" "$APP/Contents/Info.plist"
codesign --force -s - "$APP"

echo "Built $APP"
```

`video-transposer/.gitignore`:

```
build/
```

Run: `chmod +x video-transposer/build-app.sh`

- [ ] **Step 2: Shared state**

`video-transposer/app/Sources/VideoModel.swift`:

```swift
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
        job = .idle
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

    private func run(_ label: String, _ work: @escaping @Sendable () throws -> URL) {
        guard let url else { return }
        job = .running(label)
        Task.detached {
            let result = Result { try work() }
            await MainActor.run {
                guard self.url == url else { return }
                switch result {
                case .success(let output): self.job = .succeeded(output)
                case .failure(let error): self.job = .failed((error as? EngineError)?.message ?? "\(error)")
                }
            }
        }
    }
}
```

- [ ] **Step 3: Entry point and window**

`video-transposer/app/Sources/VideoToolsApp.swift`:

```swift
//
// VideoToolsApp.swift
//
// Entry point. Finder Quick Actions open videotools://open?tab=…&path=…;
// the app delegate receives those URLs (whether or not the app was already
// running) and loads the video into the single window.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MainActor.assumeIsolated { VideoModel() }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let request = urls.lazy.compactMap(parseLaunchURL).first else { return }
        MainActor.assumeIsolated {
            model.open(request)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    // One window; closing it quits, so a later Quick Action starts fresh.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct VideoToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Video Tools", id: "main") {
            ContentView(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
    }
}
```

`video-transposer/app/Sources/ContentView.swift`:

```swift
//
// ContentView.swift
//
// The window: player, frame-step buttons and time readout, the tab
// switcher, the job status line, and the footer.

import AVKit
import SwiftUI

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

struct ContentView: View {
    @Bindable var model: VideoModel

    var body: some View {
        VStack(spacing: 12) {
            if model.tools == nil {
                message("ffmpeg isn't installed. Run install.sh in the video-transposer folder.")
            } else if model.url == nil {
                message("Right-click a video in Finder and choose Quick Actions › Transpose audio or Cut video.")
            } else if let error = model.loadError {
                message(error)
            } else {
                PlayerView(player: model.player)
                    .frame(minHeight: 320)
                frameStepRow
            }

            if model.url != nil {
                Picker("", selection: $model.tab) {
                    Text("Transpose audio").tag(Tab.transpose)
                    Text("Cut video").tag(Tab.cut)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                Group {
                    switch model.tab {
                    case .transpose: TransposeTab(model: model)
                    case .cut: CutTab(model: model)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                jobStatus
            }

            Spacer(minLength: 0)
            Text("aipathstudio · [https://aipathstudio.com](https://aipathstudio.com)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 620)
        .navigationTitle(model.url?.lastPathComponent ?? "Video Tools")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 320)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var frameStepRow: some View {
        HStack {
            Button { model.stepFrame(-1) } label: { Image(systemName: "backward.frame") }
                .help("Back one frame")
            Button { model.stepFrame(1) } label: { Image(systemName: "forward.frame") }
                .help("Forward one frame")
            Text("\(formatClock(model.currentTime)) / \(formatClock(model.info?.duration ?? 0))")
                .monospacedDigit()
            Spacer()
        }
    }

    @ViewBuilder private var jobStatus: some View {
        switch model.job {
        case .idle:
            EmptyView()
        case .running(let label):
            HStack {
                ProgressView().controlSize(.small)
                Text(label)
            }
        case .succeeded(let output):
            HStack {
                Text("Saved \(output.lastPathComponent)")
                Button("Show in Finder") { model.showInFinder(output) }
            }
        case .failed(let error):
            ScrollView {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
        }
    }
}
```

- [ ] **Step 4: The two tabs**

`video-transposer/app/Sources/CutTab.swift`:

```swift
//
// CutTab.swift
//
// Start/End marks, a timeline showing what will actually be removed (Start
// to the resume keyframe), the status line, and the Cut button.

import SwiftUI

struct CutTab: View {
    @Bindable var model: VideoModel
    @State private var startText = ""
    @State private var endText = ""

    private var start: Double? { parseTime(startText) }
    private var end: Double? { parseTime(endText) }

    private var plan: CutPlan? {
        guard let start, let end, let info = model.info, let keyframes = model.keyframes else { return nil }
        return planCut(start: start, end: end, duration: info.duration, keyframes: keyframes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineBar(duration: model.info?.duration ?? 0, plan: plan, playhead: model.currentTime)
                .frame(height: 14)

            HStack(spacing: 20) {
                mark("Start", text: $startText)
                mark("End", text: $endText)
            }

            Text(model.keyframeError.map { "Couldn't read keyframes: \($0)" }
                 ?? cutStatusLine(start: start, end: end, duration: model.info?.duration,
                                  keyframes: model.keyframes))
                .foregroundStyle(.secondary)

            Button("Cut") { if let plan { model.cut(plan) } }
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil || !model.canAct)
        }
        .onChange(of: model.url) {
            startText = ""
            endText = ""
        }
    }

    private func mark(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField("m:ss.xx", text: text)
                .frame(width: 90)
                .foregroundStyle(!text.wrappedValue.isEmpty && parseTime(text.wrappedValue) == nil ? .red : .primary)
            Button("Set to playhead") { text.wrappedValue = formatClock(model.currentTime) }
        }
    }
}

/// Display-only bar: the whole duration, the removed section, the playhead.
struct TimelineBar: View {
    let duration: Double
    let plan: CutPlan?
    let playhead: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (t: Double) in duration > 0 ? width * min(max(t / duration, 0), 1) : 0 }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                if let plan {
                    let from = x(plan.start), to = x(plan.resume?.time ?? duration)
                    Rectangle().fill(.red.opacity(0.6))
                        .frame(width: max(to - from, 1))
                        .offset(x: from)
                }
                Rectangle().fill(.primary)
                    .frame(width: 2)
                    .offset(x: x(playhead) - 1)
            }
        }
    }
}
```

`video-transposer/app/Sources/TransposeTab.swift`:

```swift
//
// TransposeTab.swift
//
// Semitones field with a stepper, a live output-name preview, and the
// Transpose button. Plays the original audio; there is no pitch preview.

import SwiftUI

struct TransposeTab: View {
    @Bindable var model: VideoModel
    @State private var semitonesText = "-1"

    private var semitones: Int? { parseSemitones(semitonesText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.info != nil && model.info?.audioSampleRate == nil {
                Text("No audio track").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Semitones")
                    TextField("-1", text: $semitonesText)
                        .frame(width: 60)
                    Stepper("", onIncrement: { nudge(1) }, onDecrement: { nudge(-1) })
                        .labelsHidden()
                }

                if let semitones, let url = model.url {
                    Text("→ \(transposeOutputURL(for: url, semitones: semitones).lastPathComponent)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter a whole number from -12 to 12, not 0.").foregroundStyle(.red)
                }

                Button("Transpose") { if let semitones { model.transpose(semitones: semitones) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(semitones == nil || model.info?.audioSampleRate == nil || !model.canAct)
            }
        }
        // The default is -1 every time the tab opens.
        .onAppear { semitonesText = "-1" }
    }

    /// Steps by one, skipping 0 and staying within -12...12.
    private func nudge(_ delta: Int) {
        var next = (semitones ?? -1) + delta
        if next == 0 { next += delta }
        semitonesText = String(min(max(next, -12), 12))
    }
}
```

- [ ] **Step 5: Build**

Run: `video-transposer/build-app.sh`
Expected: `Built …/video-transposer/build/Video Tools.app`, with no compiler errors or warnings. Then run `video-transposer/tests/run-tests.sh` again. Expected: `All engine tests passed.`

- [ ] **Step 6: Launch on each tab and screenshot the window**

Make test clips and a window-id helper in a scratch folder (`$SCRATCH` = your scratchpad directory, **not** inside the repo):

```bash
SCRATCH=<your scratchpad dir>; mkdir -p "$SCRATCH/clips"
ffmpeg -v error -y -f lavfi -i testsrc2=size=320x240:rate=25 -f lavfi -i sine=frequency=440:sample_rate=44100 \
  -t 10 -c:v libx264 -g 50 -keyint_min 50 -sc_threshold 0 -pix_fmt yuv420p -c:a aac -shortest "$SCRATCH/clips/clip.mp4"
ffmpeg -v error -y -f lavfi -i testsrc2=size=320x240:rate=25 -t 4 -c:v libx264 -g 50 -pix_fmt yuv420p "$SCRATCH/clips/noaudio.mp4"
cat > "$SCRATCH/winid.swift" <<'EOF'
import CoreGraphics
// Prints the window number of the on-screen Video Tools window titled argv[1].
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where w[kCGWindowOwnerName as String] as? String == "Video Tools"
    && w[kCGWindowName as String] as? String == CommandLine.arguments[1] {
    print(w[kCGWindowNumber as String] as! Int); break
}
EOF
swiftc -o "$SCRATCH/winid" "$SCRATCH/winid.swift"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "video-transposer/build/Video Tools.app"
enc() { osascript -l JavaScript -e 'function run(a) { return encodeURIComponent(a[0]) }' "$1"; }
open "videotools://open?tab=cut&path=$(enc "$SCRATCH/clips/clip.mp4")"
```

Wait for the window, then run `screencapture -x -o -l$("$SCRATCH/winid" clip.mp4) "$SCRATCH/cut.png"` and view the image. Expected: the window is titled `clip.mp4` and shows the player, ◀/▶ buttons, `00:00.00 / 00:10.00`, "Cut video" selected, the timeline bar, Start/End fields, "Enter Start and End.", a disabled Cut button, and the footer.

Then run `open "videotools://open?tab=transpose&path=$(enc "$SCRATCH/clips/noaudio.mp4")"` and capture with window title `noaudio.mp4`. Expected: the same single window now shows `noaudio.mp4`, the Transpose tab, and "No audio track".

Do **not** use System Events / AppleScript UI scripting (it triggers an Accessibility prompt) or a full-screen capture.

- [ ] **Step 7: Back-to-back launches (Review Focus 5)**

Run both opens with no pause between them:

```bash
open "videotools://open?tab=cut&path=$(enc "$SCRATCH/clips/clip.mp4")"; open "videotools://open?tab=transpose&path=$(enc "$SCRATCH/clips/noaudio.mp4")"
```

Capture the window titled `noaudio.mp4`. Expected: it shows `00:04.00` duration and "No audio track", not clip.mp4's 10s duration or tone controls.

- [ ] **Step 8: A real cut and transpose through the UI**

Open `clip.mp4` on the Cut tab, type Start `3` and End `5`, and capture the window. Expected status: `Removes 00:03.00 → 00:06.00 (3.00s). Resumes at keyframe +1.00s after End.` with the 3s–6s section shaded on the timeline. Clicking Cut needs a person: ask your human partner to click **Cut**, then **Transpose** (default −1) on the Transpose tab. Confirm that `clip-cut0m03s-0m06s.mp4` and `clip-transposedDown1.mp4` appear in `$SCRATCH/clips` and that the window says `Saved …` with a Show in Finder button. If no person is available, record that these two clicks were not exercised.

Then quit the app (`pkill -f "Video Tools.app/Contents/MacOS/VideoTools"`) and run `"$LSREGISTER" -u "video-transposer/build/Video Tools.app"`.

- [ ] **Step 9: Commit**

```bash
git add video-transposer/app video-transposer/build-app.sh video-transposer/.gitignore
git commit -m "Add Video Tools SwiftUI app with Transpose and Cut tabs"
```

---

### Task 4: Quick Action launchers, install/uninstall, docs

**Files:**
- Modify: `video-transposer/Transpose Audio.workflow/Contents/document.wflow` (command string)
- Create: `video-transposer/Cut Video.workflow/` (copy of the Transpose workflow, then edited)
- Modify: `video-transposer/install.sh` (full rewrite)
- Modify: `video-transposer/uninstall.sh` (full rewrite)
- Delete: `video-transposer/scripts/transpose-audio.sh` (and the `scripts/` folder)
- Modify: `video-transposer/README.md` (full rewrite)
- Modify: `README.md` (root, lines 11–12)

**Interfaces:**
- Consumes: `video-transposer/build-app.sh` and the `videotools://open?tab=…&path=…` contract from Task 3.
- Produces: the installed `~/Applications/Video Tools.app` and the two Quick Actions in `~/Library/Services`.

- [ ] **Step 1: Rewire the Transpose workflow and create the Cut workflow**

Each workflow's Run Shell Script action (bash, input passed as arguments) becomes a launcher for the first selected file. Run from the repo root:

```bash
cd video-transposer
cp -R "Transpose Audio.workflow" "Cut Video.workflow"
set_launcher() {  # $1 = workflow, $2 = tab
  local cmd
  cmd=$(cat <<EOF
# Opens the first selected video in Video Tools on the $2 tab.
[ \$# -ge 1 ] || exit 0
url=\$(/usr/bin/osascript -l JavaScript -e 'function run(argv) { return "videotools://open?tab=$2&path=" + encodeURIComponent(argv[0]) }' "\$1")
/usr/bin/open "\$url"
EOF
)
  plutil -replace actions.0.action.ActionParameters.COMMAND_STRING -string "$cmd" "$1/Contents/document.wflow"
  plutil -convert xml1 "$1/Contents/document.wflow"
}
set_launcher "Transpose Audio.workflow" transpose
set_launcher "Cut Video.workflow" cut
plutil -replace NSServices.0.NSMenuItem.default -string "Cut video" "Cut Video.workflow/Contents/Info.plist"
plutil -convert xml1 "Cut Video.workflow/Contents/Info.plist"
for key in UUID InputUUID OutputUUID; do
  plutil -replace "actions.0.action.$key" -string "$(uuidgen)" "Cut Video.workflow/Contents/document.wflow"
done
plutil -convert xml1 "Cut Video.workflow/Contents/document.wflow"
cd ..
```

Verify: `plutil -extract actions.0.action.ActionParameters.COMMAND_STRING raw "video-transposer/Cut Video.workflow/Contents/document.wflow"` prints the three-line launcher containing `tab=cut&path=`, and the same for Transpose prints `tab=transpose&path=`. `plutil -lint` passes on all four plists. `git diff "video-transposer/Transpose Audio.workflow"` shows only the `COMMAND_STRING` change, with `&` escaped as `&amp;` in the XML.

- [ ] **Step 2: Rewrite install.sh and uninstall.sh; delete the old script**

`video-transposer/install.sh`:

```bash
#!/bin/bash
#
# Installs Video Tools and its two Finder Quick Actions.
#
# - Ensures Homebrew is available and installs ffmpeg
# - Builds Video Tools.app and copies it to ~/Applications
# - Registers it with LaunchServices so videotools:// URLs open it
# - Copies "Transpose Audio" and "Cut Video" into ~/Library/Services

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$HOME/Library/Services"
APP_NAME="Video Tools.app"
APP_DEST="$HOME/Applications/$APP_NAME"
WORKFLOWS=("Transpose Audio.workflow" "Cut Video.workflow")
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required but not installed."
  echo "Install it from https://brew.sh and re-run this script."
  exit 1
fi

echo "Installing dependency (ffmpeg)..."
brew install ffmpeg

echo "Building $APP_NAME..."
"$SCRIPT_DIR/build-app.sh"

echo "Installing app to $APP_DEST..."
mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R "$SCRIPT_DIR/build/$APP_NAME" "$APP_DEST"
# Only the installed copy should answer videotools:// URLs.
"$LSREGISTER" -u "$SCRIPT_DIR/build/$APP_NAME" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$APP_DEST"

mkdir -p "$SERVICES_DIR"
for workflow in "${WORKFLOWS[@]}"; do
  echo "Installing Quick Action to $SERVICES_DIR/$workflow..."
  rm -rf "$SERVICES_DIR/$workflow"
  cp -R "$SCRIPT_DIR/$workflow" "$SERVICES_DIR/$workflow"
done
/System/Library/CoreServices/pbs -flush

echo "Done. Right-click a video file in Finder and choose"
echo "Quick Actions > Transpose audio or Quick Actions > Cut video."
echo
echo "If they don't show up immediately, log out and back in."
```

`video-transposer/uninstall.sh`:

```bash
#!/bin/bash
#
# Removes Video Tools and its two Finder Quick Actions.

set -euo pipefail

APP="$HOME/Applications/Video Tools.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for path in "$APP" \
            "$HOME/Library/Services/Transpose Audio.workflow" \
            "$HOME/Library/Services/Cut Video.workflow"; do
  if [ -d "$path" ]; then
    [ "$path" = "$APP" ] && "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
    rm -rf "$path"
    echo "Removed $path"
  else
    echo "Not installed: $path"
  fi
done
/System/Library/CoreServices/pbs -flush
```

Run: `git rm -r video-transposer/scripts`

- [ ] **Step 3: Install and check the result**

Run: `video-transposer/install.sh`
Expected: it ends with the "Done." message, and:
- `ls ~/Applications/"Video Tools.app"/Contents/MacOS/VideoTools` exists
- `ls ~/Library/Services` lists `Transpose Audio.workflow` and `Cut Video.workflow`
- `lsregister -dump URLSchemeBinding | grep videotools` shows exactly one binding (the `~/Applications` copy)
- with `enc` and `$SCRATCH/clips/clip.mp4` set up as in Task 3, Step 6 (recreate them if needed), `open "videotools://open?tab=cut&path=$(enc "$SCRATCH/clips/clip.mp4")"` launches `~/Applications/Video Tools.app` (check with `pgrep -fl VideoTools`). Quit it afterwards.

- [ ] **Step 4: Rewrite the READMEs**

`video-transposer/README.md`:

````markdown
# Video Tools

A small native macOS app, opened from two Finder Quick Actions, for working
on one video at a time:

- **Transpose audio:** shift the pitch of a video's audio up or down by a
  number of semitones, without changing its speed or touching the picture.
- **Cut video:** remove one section of a video and join the remaining
  pieces, without re-encoding.

Right-click a video in Finder and choose **Quick Actions > Transpose audio**
or **Quick Actions > Cut video**. Video Tools opens with a preview of the
video on the matching tab. You can switch tabs at any time; the playhead
stays where it is. If several files are selected, only the first is opened.

New files are written next to the original, which is left untouched. An
existing file with the same name is overwritten.

## Transpose audio

Enter the number of semitones (default `-1`, one semitone down) or use the
stepper. Negative values transpose down, positive values up, from `-12` to
`12`. The preview plays the original audio.

- `song.mp4` transposed by `-1` -> `song-transposedDown1.mp4`
- `song.mp4` transposed by `2` -> `song-transposedUp2.mp4`

The video stream is copied as-is. The audio is pitch-shifted with ffmpeg's
built-in filters: `asetrate` + `aresample` change the pitch (which also
changes speed), then `atempo` stretches it back to the original speed so it
stays in sync with the video. The result is re-encoded as AAC at 256 kbps.
This is clean for speech and for music at small shifts; large shifts
(beyond a few semitones) can introduce some audible artifacts.

## Cut video

Set **Start** and **End** by typing a time (`12`, `12.5`, `6:38`,
`6:38.17`, `1:02:03` or `1:02:03.50`) or with **Set to playhead**. Use the
◀ / ▶ buttons to step one frame at a time. The timeline bar shades the
section that will be removed, and the line below it says exactly what goes:

- `song.mp4`, removing 6:38–7:11 -> `song-cut6m38s-7m11s.mp4`

One section is removed per cut. To remove another, cut the new file again.

### Why the cut may run a little past End

Cutting uses ffmpeg stream copy: the original audio and video are copied,
not re-encoded, so there is no quality loss and a cut takes well under a
second. The catch is that playback can only resume at a **keyframe**, so the
removed section runs from Start to the first keyframe at or after End. In
typical videos keyframes are a few seconds apart. Video Tools never keeps
anything you marked for removal, and the status line shows where playback
will resume (for example "Resumes at keyframe +0.17s after End") before you
click Cut. The kept part before Start may also run a frame or two past
Start.

## Requirements

- macOS 14 or later on Apple silicon
- [Homebrew](https://brew.sh)
- [`ffmpeg`](https://ffmpeg.org/) (installed automatically by `install.sh`)
- Xcode Command Line Tools (`xcode-select --install`), to build the app

## Install

```sh
./install.sh
```

This installs `ffmpeg` via Homebrew, builds `Video Tools.app` into
`~/Applications`, and installs the "Transpose audio" and "Cut video" Quick
Actions into `~/Library/Services`. The first time you use it on a file in
Downloads, Documents or Desktop, macOS asks whether Video Tools may access
that folder.

If the menu items don't appear right away, log out and back in.

## Uninstall

```sh
./uninstall.sh
```

## Development

- `./build-app.sh` builds `build/Video Tools.app` with `swiftc`.
- `tests/run-tests.sh` runs the engine tests (`app/Sources/VideoEngine.swift`)
  including real ffmpeg runs on generated clips.
````

Root `README.md`, replace lines 11–12:

```markdown
- [`video-transposer`](video-transposer/) - Video Tools app with Finder
  Quick Actions to transpose a video's audio by semitones or cut a section
  out of a video without re-encoding.
```

- [ ] **Step 5: Commit**

```bash
git add -A video-transposer README.md
git commit -m "Wire Quick Actions to Video Tools app; install, uninstall, docs"
```

- [ ] **Step 6: End-to-end check by the user (cannot be automated)**

Ask your human partner to:
1. In Finder, right-click a video in Downloads → Quick Actions → **Cut video**. Video Tools should open on the Cut tab with that video. (If nothing opens, the Quick Action sandbox is blocking `open` with a custom URL. Switch to the spec's fallback, `open -a "Video Tools"` plus a `defaults` key holding the tab, and report back before changing anything.)
2. Allow the one-time "Video Tools would like to access files in your Downloads folder" prompt.
3. Use **Transpose audio** from Finder on the same video, which should switch the open window to the Transpose tab.
4. Re-run the Bole Chudiyan cut: Start `6:38`, End `7:11`. The status should read `Removes 06:38.00 → 07:11.17 …`, and the output should be `Bole Chudiyan - karaoke_down1st-cut6m38s-7m11s.mp4`.
