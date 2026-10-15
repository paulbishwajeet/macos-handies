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
