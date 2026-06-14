# Compress Image

A macOS Finder Quick Action that compresses `.jpg`/`.jpeg`/`.png` images as
much as possible without noticeably affecting quality or resolution.

Right-click one or more JPEG/PNG files in Finder, choose
**Quick Actions > Compress Image**, and each file is compressed in place:

- The compressed version replaces the original filename.
- The original file is kept alongside it, renamed with an `_old` suffix
  (e.g. `photo.jpg` -> compressed `photo.jpg` + original `photo_old.jpg`).
- If compression wouldn't actually reduce the file size, the original is
  left untouched.

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- [`pngquant`](https://pngquant.org/) and [`jpegoptim`](https://github.com/tjko/jpegoptim)
  (installed automatically by `install.sh`)

## Install

```sh
./install.sh
```

This installs `pngquant` and `jpegoptim` via Homebrew and copies the
"Compress Image" Quick Action to `~/Library/Services`.

If the menu item doesn't appear right away, log out/in or run:

```sh
/System/Library/CoreServices/pbs -flush
```

## Uninstall

```sh
./uninstall.sh
```

## How compression works

- **JPEG**: re-encoded with [`jpegoptim`](https://github.com/tjko/jpegoptim)
  at a max quality of 85 and metadata stripped.
- **PNG**: re-encoded with [`pngquant`](https://pngquant.org/) using a
  quality range of 65-90 and metadata stripped.

Both tools preserve image dimensions (resolution) - only file size and
fine compression detail change. The quality settings are constants at the
top of `scripts/compress-image.sh` and can be adjusted if you want
smaller files at lower quality or vice versa.

## Running the script directly

You can also run the underlying script on files without using Finder:

```sh
scripts/compress-image.sh path/to/image.jpg path/to/image.png
```
