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
