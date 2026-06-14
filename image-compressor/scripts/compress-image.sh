#!/bin/bash
#
# compress-image.sh
#
# Compresses JPEG and PNG images in place without resizing them.
# For each input file:
#   - Compresses to a temp file (jpegoptim for JPEG, pngquant for PNG)
#   - If the compressed file is smaller, renames the original to
#     "<name>_old.<ext>" and replaces it with the compressed version.
#   - If compression doesn't shrink the file (or required tools are
#     missing), the original is left untouched.
#
# Usage: compress-image.sh file1.jpg file2.png ...

set -uo pipefail

# Quality settings (tune as needed)
JPEG_MAX_QUALITY=85
PNG_QUALITY_RANGE="65-90"

for input in "$@"; do
  [ -f "$input" ] || continue

  dir=$(dirname "$input")
  base=$(basename "$input")
  ext="${base##*.}"
  name="${base%.*}"
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  case "$ext_lower" in
    jpg|jpeg)
      if ! command -v jpegoptim >/dev/null 2>&1; then
        continue
      fi
      tmp=$(mktemp "${dir}/.${name}.XXXXXX.${ext}")
      cp -p "$input" "$tmp"
      jpegoptim --max="$JPEG_MAX_QUALITY" --strip-all --quiet "$tmp" || { rm -f "$tmp"; continue; }
      ;;
    png)
      if ! command -v pngquant >/dev/null 2>&1; then
        continue
      fi
      tmp=$(mktemp "${dir}/.${name}.XXXXXX.${ext}")
      pngquant --quality="$PNG_QUALITY_RANGE" --strip --speed 1 --force --output "$tmp" "$input" || { rm -f "$tmp"; continue; }
      ;;
    *)
      continue
      ;;
  esac

  orig_size=$(stat -f%z "$input")
  new_size=$(stat -f%z "$tmp")

  if [ "$new_size" -lt "$orig_size" ]; then
    mv "$input" "${dir}/${name}_old.${ext}"
    mv "$tmp" "$input"
  else
    rm -f "$tmp"
  fi
done
