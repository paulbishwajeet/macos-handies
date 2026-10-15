# Video Tools — SwiftUI App for Transposing and Cutting Videos

## Purpose

`video-transposer` currently ships one Finder Quick Action, "Transpose
audio", which asks for semitones in an AppleScript dialog and runs
`scripts/transpose-audio.sh`. This adds a second feature — cutting a
section out of a video and joining the remaining pieces — and replaces the
dialog with a small native SwiftUI app, **Video Tools.app**, that has a
video preview and two tabs: **Transpose audio** and **Cut video**.

An AppleScript dialog cannot show tabs or a video player, which is why a
real app is needed. The app works on **one video at a time**.

## Decisions already made

- **Cutting uses stream copy (no re-encode).** Both approaches were tried on
  `Bole Chudiyan - karaoke_down1st.mp4` (remove 6:38–7:11). Stream copy took
  0.3s, kept the original encoding untouched (no quality loss), and removed 6:38.03 → 7:11.17. A
  frame-accurate re-encode took 28s, was visually lossless (PSNR ~50 dB),
  and came out larger than the original. Stream copy was chosen. Its cost:
  playback can only resume at a keyframe, so the removed section may extend
  past End by up to one keyframe interval (5–6s in the sample videos). The
  UI shows exactly where it will resume before cutting.
- **Resume at the next keyframe at or after End.** Nothing marked for removal
  is ever kept.
- **One section per cut.** To remove another section, cut the output again.
- **Two Quick Actions, one app.** "Transpose audio" and "Cut video" both open
  Video Tools, on the matching tab.
- **No live pitch preview.** The Transpose tab plays the original audio.
- **`transpose-audio.sh` is deleted.** Its logic moves into Swift, so there
  is one implementation. The command-line `--semitones` usage goes away.
- **Native SwiftUI app** built with `swiftc` from the Command Line Tools —
  no Xcode project.

## Layout

```
video-transposer/
  app/
    Info.plist                 # bundle id com.macoshandies.videotools, registers videotools://
    Sources/
      VideoToolsApp.swift      # @main, single Window scene, handles videotools:// URLs
      ContentView.swift        # title, player, frame-step + time readout, tab switcher, footer
      CutTab.swift
      TransposeTab.swift
      VideoEngine.swift        # ffprobe/ffmpeg calls, keyframes, snapping, naming, time parsing — no UI
  tests/
    EngineTests.swift          # assert-based test runner, compiled with VideoEngine.swift
    run-tests.sh
  Transpose Audio.workflow     # rewired to launch the app (tab=transpose)
  Cut Video.workflow           # new (tab=cut)
  build-app.sh                 # swiftc -> build/Video Tools.app, ad-hoc codesign
  install.sh, uninstall.sh, README.md
  .gitignore                   # build/
```

`scripts/transpose-audio.sh` (and the `scripts/` folder) is removed.

## Launching: Quick Actions → app

Both workflows are thin launchers. For the **first** selected file only,
they percent-encode the path and run:

```
open "videotools://open?tab=cut&path=<percent-encoded absolute path>"
```

(`tab=transpose` for the other action.) The app registers the `videotools`
URL scheme in its `Info.plist`. A URL works whether or not the app is
already running; launch arguments are ignored by a running app. When a URL
arrives, the window loads that video (replacing any current one), switches
to the requested tab, and comes to the front.

Percent-encoding in the workflow uses JavaScript for Automation
(`osascript -l JavaScript`, `encodeURIComponent`), which ships with macOS.

**Risk to validate first:** that `open` with a custom URL is allowed from
inside the Quick Action sandbox. If it isn't, fall back to
`open -a "Video Tools" <file>` plus a per-action marker (for example a
`defaults` key holding the requested tab, read by the app on open).

The app runs outside the Quick Action sandbox, so the "Operation not
permitted" rename restriction seen with the old script does not apply.
macOS asks once per protected folder (Downloads, Documents, Desktop)
whether Video Tools may access it.

## App: shared window

- **Single window** (`Window` scene, not `WindowGroup`), titled with the
  file name.
- **Player:** `AVPlayerView` (AppKit, wrapped for SwiftUI) with the standard
  play/pause, scrubbing and volume controls.
- **Below the player:** ◀ / ▶ buttons that step one frame, and a time
  readout `mm:ss.xx / mm:ss.xx`.
- **Tabs:** Transpose audio | Cut video. Switching tabs keeps the playhead.
- **Footer:** `aipathstudio · https://aipathstudio.com`, the same branding
  as the redactor and the old transpose dialog.
- **Empty state:** with no video loaded (for example the app was launched
  directly), the window says to right-click a video in Finder and choose a
  Quick Action.
- **Unreadable file / no video stream:** a message replaces the player and
  both tabs' action buttons are disabled.
- **`ffmpeg`/`ffprobe` missing:** a message says to run `install.sh`, and
  action buttons are disabled. Binaries are found at `/opt/homebrew/bin`
  then `/usr/local/bin`.

### While working and afterwards (both tabs)

- Action buttons are disabled and a spinner shows "Cutting…" or
  "Transposing…".
- **Success:** "Saved `<output file name>`" with a **Show in Finder** button
  (it selects the file). The window stays open for further work.
- **Failure:** `ffmpeg`'s error output is shown in the window, and any
  partial output file is deleted.
- An output file with the same name is overwritten.

## Cut video tab

### UI

- A **timeline bar** under the player, spanning the whole duration. It shades
  the section that will actually be removed (Start → resume point K) and
  shows the playhead. The bar is display-only; dragging is out of scope.
- **Start** and **End** text fields, each with a **Set to playhead** button.
  Fields accept `ss`, `ss.xx`, `m:ss`, `m:ss.xx`, `h:mm:ss` and
  `h:mm:ss.xx`. Invalid text is shown in red and disables Cut.
- A **status line**, recomputed whenever a mark changes:
  - Middle cut: "Removes 06:38.00 → 07:11.17 (33.17s). Resumes at keyframe
    +0.17s after End."
  - Start at 0:00: "Removes the start through 00:12.00."
  - No keyframe at or after End: "Removes 06:38.00 to the end."
  - While keyframes are loading: "Finding keyframes…"
- The **Cut** button is enabled only when keyframes are loaded,
  0 ≤ Start < End ≤ duration, and the cut would not remove the whole video
  (Start = 0 with no keyframe at or after End).

### Keyframe list

Read when a video loads, in the background, from packets (no decoding):

```
ffprobe -v error -select_streams v:0 -show_entries packet=pts_time,flags -of csv=p=0 <in>
```

Keep the `pts_time` of every packet whose flags contain `K`, sorted.

### Algorithm

Let **K** be the first keyframe ≥ End, or none.

| Case | Kept | ffmpeg |
|---|---|---|
| Start > 0, K exists | [0, Start) + [K, end] | part 1, part 2, concat |
| Start = 0, K exists | [K, end] | part 2 written straight to the output |
| Start > 0, no K | [0, Start) | part 1 written straight to the output |
| Start = 0, no K | nothing | not allowed (Cut disabled) |

- **Part 1:** `ffmpeg -y -i <in> -t <Start> -map 0:v -map 0:a? -c copy -avoid_negative_ts make_zero <out>`
- **Part 2:** `ffmpeg -y -ss <K> -i <in> -map 0:v -map 0:a? -c copy -avoid_negative_ts make_zero <out>`
- **Concat:** write both parts into a fresh folder under the system temp
  directory (`seg1.<ext>`, `seg2.<ext>`), list them in `list.txt`, then run
  `ffmpeg -y -f concat -safe 0 -i list.txt -c copy <output>`. Delete the temp
  folder afterwards, on success or failure.
- `-movflags +faststart` is added to the final write when the extension is
  `mp4`, `m4v` or `mov`.
- Keyframe times are passed to ffmpeg exactly as ffprobe printed them.
- **Known limit:** part 1 may run about one frame past Start (0.03s in the
  test). This is accepted.

### Output naming

`<name>-cut<A>-<B>.<ext>` next to the original, where A = Start and
B = K (or the duration when there is no K). Times are rounded down to whole
seconds and formatted `<minutes>m<ss>s`, with minutes unpadded and allowed to
exceed 59. Examples:

- `Bole Chudiyan - karaoke_down1st-cut6m38s-7m11s.mp4`
- Start at 0:00, K = 12.0 → `-cut0m00s-0m12s`
- 6:38 to the end of a 7:19 video → `-cut6m38s-7m19s`

## Transpose audio tab

- A **Semitones** field with a ± stepper. The default is −1 every time the
  tab opens (not remembered). Allowed values are whole numbers −12…12,
  excluding 0. Invalid values disable Transpose and show a hint.
- A live output-name preview, e.g. `→ …-transposedDown1.mp4`.
- A **Transpose** button.
- A video with no audio stream shows "No audio track" instead of the
  controls.

Processing is identical to the deleted script:

- The sample rate SR comes from the first audio stream (`ffprobe`), and
  r = 2^(semitones/12).
- Filter: `asetrate=SR·r,aresample=SR,atempo=1/r`.
- `ffmpeg -y -i <in> -map 0:v? -map 0:a -c:v copy -af <filter> -c:a aac -b:a 256k <output>`
- ffmpeg writes straight to the final name, with no temp-and-rename step.
- Naming: `<name>-transposedDown<N>.<ext>` / `<name>-transposedUp<N>.<ext>`.

## Build, install, uninstall

- **`build-app.sh`** compiles `app/Sources/*.swift` with `swiftc`
  (`-target arm64-apple-macos14`, `-O`, `-parse-as-library`), assembles
  `build/Video Tools.app` (`Contents/MacOS/VideoTools`,
  `Contents/Info.plist`), and ad-hoc signs it (`codesign -s -`). It targets
  arm64 only; there is no universal binary, since this is for this Mac.
- **`install.sh`:**
  1. Requires Homebrew and runs `brew install ffmpeg`.
  2. Runs `build-app.sh`.
  3. Copies the app to `~/Applications/Video Tools.app`.
  4. Registers it with LaunchServices (`lsregister -f`), so `videotools://`
     resolves.
  5. Installs both workflows to `~/Library/Services` and flushes the
     services cache (`pbs -flush`).
- **`uninstall.sh`** removes the app and both workflows.
- **`README.md`** is rewritten for the app, both actions and stream-copy
  cutting (including the keyframe note). The root `README.md` entry is
  updated to mention cutting.

Sharing with other Macs (a `.pkg`, notarization, universal binary) is out of
scope.

## Testing

### Engine (automated)

`tests/run-tests.sh` compiles `VideoEngine.swift` and `EngineTests.swift`
into a test binary with `swiftc` and runs it. It exits non-zero on any
failure.

**Pure checks:**

- Time parsing for every accepted format, plus invalid input.
- Time formatting.
- Choosing K, including End exactly on a keyframe, End after the last
  keyframe, and Start = 0.
- Which of the four cut cases applies.
- Output names for cuts (middle, start, end) and transposes (up/down).
- Semitone validation.

**Real ffmpeg runs**, on clips generated with `ffmpeg -f lavfi` (testsrc2
plus a 440 Hz sine, forced keyframes every 2s with `-g`):

- **Middle cut:** output duration equals the input duration − (K − Start),
  within one frame. The frames just after the join match the original at K
  (PSNR > 40 dB).
- **Start cut** and **end cut:** durations as expected.
- **Transpose ±:** the measured tone is within 1% of 440·2^(n/12), and the
  duration is unchanged.
- **No-audio clip:** reported as having no audio.

### App (manual, by the implementer)

- Build and launch through `open "videotools://open?tab=cut&path=…"` and
  `tab=transpose`, and screenshot both tabs to check the layout.
- Run a real cut and transpose on generated clips through the UI.

### End to end (the user)

- Use both Quick Actions from Finder on a video in Downloads.
- Confirm the one-time folder permission prompt.
- Re-run the Bole Chudiyan 6:38–7:11 cut and compare it with the earlier
  stream-copy result (expected: removes 06:38.00 → 07:11.17).
