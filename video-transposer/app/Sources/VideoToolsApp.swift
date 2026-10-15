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
