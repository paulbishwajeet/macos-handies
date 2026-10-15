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
