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
