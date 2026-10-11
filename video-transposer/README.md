# Transpose Audio

A macOS Finder Quick Action that shifts the pitch of a video's audio up or
down by a number of semitones, without changing its speed or touching the
picture.

Right-click one or more video files in Finder, choose
**Quick Actions > Transpose audio**, and enter the number of semitones
(default `-1`, i.e. one semitone down). Negative values transpose down,
positive values transpose up, from `-12` to `12`.

A new video is written next to each original, which is left untouched:

- `song.mp4` transposed by `-1` -> `song-transposedDown1.mp4`
- `song.mp4` transposed by `2` -> `song-transposedUp2.mp4`

An existing file with the same output name is overwritten.

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- [`ffmpeg`](https://ffmpeg.org/) (installed automatically by `install.sh`)

## Install

```sh
./install.sh
```

This installs `ffmpeg` via Homebrew and copies the "Transpose audio" Quick
Action to `~/Library/Services`.

If the menu item doesn't appear right away, log out/in or run:

```sh
/System/Library/CoreServices/pbs -flush
```

## Uninstall

```sh
./uninstall.sh
```

## How transposing works

The video stream is copied as-is (no re-encode, no quality loss). The audio
is pitch-shifted with ffmpeg's built-in filters: `asetrate` + `aresample`
change the pitch (which also changes speed), then `atempo` stretches it back
to the original speed so it stays in sync with the video. The result is
re-encoded as AAC at 256 kbps (constant at the top of
`scripts/transpose-audio.sh`).

This is clean for speech and for music at small shifts; large shifts
(beyond a few semitones) can introduce some audible artifacts.

## Running the script directly

You can also run the underlying script without Finder. `--semitones` skips
the dialog:

```sh
scripts/transpose-audio.sh --semitones -1 path/to/video.mp4
```
