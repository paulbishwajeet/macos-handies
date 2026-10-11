#!/bin/bash
#
# transpose-audio.sh
#
# Finder Quick Action entry point for "Transpose audio". Prompts once for a
# number of semitones (default -1), then pitch-shifts the audio of every
# selected video by that amount without changing its speed. The video stream
# is copied untouched. Output is written next to each original as
# "<name>-transposedDown1.<ext>" / "<name>-transposedUp2.<ext>".
#
# Usage: transpose-audio.sh video1.mp4 video2.mov ...
# For non-interactive testing, skip the dialog: transpose-audio.sh --semitones -1 video.mp4

set -uo pipefail

# Finder Quick Actions run with a minimal PATH that doesn't include Homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DEFAULT_SEMITONES=-1
MAX_SEMITONES=12
AUDIO_BITRATE="256k"

# Escape a string for safe interpolation inside a double-quoted AppleScript
# string literal (backslashes first, then double quotes).
applescript_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '%s' "$s"
}

alert() {
  local escaped
  escaped=$(applescript_escape "$1")
  osascript -e "display alert \"Transpose audio\" message \"$escaped\"" >/dev/null 2>&1
}

semitones_input=""
if [ "${1:-}" = "--semitones" ]; then
  semitones_input="${2:-}"
  shift 2
else
  dialog_result=$(osascript <<EOF
try
  set userInput to text returned of (display dialog "Semitones to transpose by (negative = down, positive = up):

aipathstudio · https://aipathstudio.com" default answer "$DEFAULT_SEMITONES" with title "Transpose audio")
  return userInput
on error number -128
  return "__CANCELLED__"
end try
EOF
)
  if [ "$dialog_result" = "__CANCELLED__" ]; then
    exit 0
  fi
  semitones_input="$dialog_result"
fi

# Trim whitespace and validate: a non-zero whole number within range.
semitones_input=$(echo "$semitones_input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if ! [[ "$semitones_input" =~ ^[+-]?[0-9]+$ ]]; then
  alert "\"$semitones_input\" is not a whole number of semitones."
  exit 1
fi
sign=""
digits="${semitones_input#[+-]}"
[ "${semitones_input:0:1}" = "-" ] && sign="-"
abs=$((10#$digits))
if [ "$abs" -eq 0 ] || [ "$abs" -gt "$MAX_SEMITONES" ]; then
  alert "Semitones must be between -$MAX_SEMITONES and $MAX_SEMITONES, and not 0."
  exit 1
fi
semitones="${sign}${abs}"

if [ -n "$sign" ]; then
  suffix="-transposedDown${abs}"
else
  suffix="-transposedUp${abs}"
fi

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  alert "ffmpeg is not installed. Please re-run install.sh for this Quick Action."
  exit 1
fi

# Pitch ratio for the requested shift: 2^(semitones/12).
ratio=$(awk -v s="$semitones" 'BEGIN { printf "%.10f", 2 ^ (s / 12) }')

for input in "$@"; do
  [ -f "$input" ] || continue

  dir=$(dirname "$input")
  base=$(basename "$input")
  ext="${base##*.}"
  name="${base%.*}"
  output="${dir}/${name}${suffix}.${ext}"

  sample_rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate \
    -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null | head -n 1)
  if ! [[ "$sample_rate" =~ ^[0-9]+$ ]]; then
    alert "\"$base\" has no audio track to transpose."
    continue
  fi

  # Resample to shift pitch (which also changes speed), then time-stretch
  # back to the original speed so the audio stays in sync with the video.
  filter=$(awk -v sr="$sample_rate" -v r="$ratio" \
    'BEGIN { printf "asetrate=%.4f,aresample=%d,atempo=%.10f", sr * r, sr, 1 / r }')

  # ffmpeg writes straight to the final name: the Quick Action sandbox
  # forbids renaming files that ffmpeg created, so a temp-file-then-mv
  # approach fails with "Operation not permitted".
  if ! error_output=$(ffmpeg -nostdin -hide_banner -loglevel error -y -i "$input" \
      -map 0:v? -map 0:a -c:v copy -af "$filter" -c:a aac -b:a "$AUDIO_BITRATE" \
      "$output" 2>&1); then
    rm -f "$output"
    alert "Failed to transpose \"$base\": $error_output"
    continue
  fi
done
