#!/bin/bash
#
# redact-personals.sh
#
# Finder Quick Action entry point for "Redact Personals". Prompts once for
# a comma-separated list of words/strings, then redacts them out of every
# selected PDF, writing "<name>_Red.pdf" next to each original.
#
# Usage: redact-personals.sh file1.pdf file2.pdf ...
# For non-interactive testing, skip the dialog: redact-personals.sh --words "a,b" file1.pdf

set -uo pipefail

# Finder Quick Actions run with a minimal PATH that doesn't include Homebrew
# or user-installed pip scripts.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Python/3.9/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_DOMAIN="com.macoshandies.pdfredactor"
PYTHON_BIN="${PDF_REDACTOR_PYTHON:-python3}"

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
  osascript -e "display alert \"Redact Personals\" message \"$escaped\"" >/dev/null 2>&1
}

words_input=""
if [ "${1:-}" = "--words" ]; then
  words_input="${2:-}"
  shift 2
else
  last_words="$(defaults read "$DEFAULTS_DOMAIN" lastWords 2>/dev/null || echo "")"
  escaped_default=$(applescript_escape "$last_words")
  dialog_result=$(osascript <<EOF
try
  set userInput to text returned of (display dialog "Words to redact (comma-separated):" default answer "$escaped_default" with title "Redact Personals")
  return userInput
on error number -128
  return "__CANCELLED__"
end try
EOF
)
  if [ "$dialog_result" = "__CANCELLED__" ]; then
    exit 0
  fi
  words_input="$dialog_result"
  defaults write "$DEFAULTS_DOMAIN" lastWords "$words_input"
fi

# Split on commas, trim whitespace, drop empty entries.
IFS=',' read -ra raw_words <<< "$words_input"
words=()
# macOS ships /bin/bash 3.2, where "${arr[@]}" on a zero-element array is an
# unbound-variable error under `set -u`. The ${arr[@]+"${arr[@]}"} idiom
# expands to nothing (instead of erroring) when the array is empty.
for w in "${raw_words[@]+"${raw_words[@]}"}"; do
  trimmed=$(echo "$w" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$trimmed" ] && words+=("$trimmed")
done

if [ ${#words[@]} -eq 0 ]; then
  alert "No words entered. Nothing was redacted."
  exit 0
fi

if ! "$PYTHON_BIN" -c "import fitz" >/dev/null 2>&1; then
  alert "PyMuPDF is not installed. Please re-run install.sh for this Quick Action."
  exit 1
fi

for input in "$@"; do
  [ -f "$input" ] || continue

  dir=$(dirname "$input")
  base=$(basename "$input")
  name="${base%.*}"
  output="${dir}/${name}_Red.pdf"

  if ! error_output=$("$PYTHON_BIN" "$SCRIPT_DIR/redact.py" "$input" "$output" "${words[@]}" 2>&1); then
    alert "Failed to redact \"$base\": $error_output"
  fi
done
