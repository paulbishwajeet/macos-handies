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
