#!/usr/bin/env bash
# Upsert one AI-owned marker block inside a markdown document.
#
# Usage:
#   update-doc-section.sh <file> <doc-id> <section-id> <heading-line> [content-file]
#
# If the marker block already exists, replace it in place.
# If the heading exists but the marker does not, insert the block right after the heading.
# If neither exists, append the heading and block at the end of the file.

set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  echo "usage: $0 <file> <doc-id> <section-id> <heading-line> [content-file]" >&2
  exit 1
fi

TARGET_FILE="$1"
DOC_ID="$2"
SECTION_ID="$3"
HEADING_LINE="$4"
CONTENT_FILE="${5:-}"

START_MARKER="<!-- AI-SYMBIOTE:START ${DOC_ID}:${SECTION_ID} -->"
END_MARKER="<!-- AI-SYMBIOTE:END ${DOC_ID}:${SECTION_ID} -->"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

BLOCK_FILE="$TMP_DIR/block.md"
OUTPUT_FILE="$TMP_DIR/output.md"

if [ -n "$CONTENT_FILE" ]; then
  cat "$CONTENT_FILE" > "$TMP_DIR/content.md"
else
  cat > "$TMP_DIR/content.md"
fi

{
  printf '%s\n' "$START_MARKER"
  cat "$TMP_DIR/content.md"
  [ -s "$TMP_DIR/content.md" ] && [ "$(tail -c 1 "$TMP_DIR/content.md" 2>/dev/null || true)" != "" ] && printf '\n'
  printf '%s\n' "$END_MARKER"
} > "$BLOCK_FILE"

mkdir -p "$(dirname "$TARGET_FILE")"

if [ ! -f "$TARGET_FILE" ]; then
  {
    printf '%s\n\n' "$HEADING_LINE"
    cat "$BLOCK_FILE"
    printf '\n'
  } > "$TARGET_FILE"
  exit 0
fi

if grep -qF "$START_MARKER" "$TARGET_FILE" 2>/dev/null; then
  awk -v start="$START_MARKER" -v end="$END_MARKER" -v block="$BLOCK_FILE" '
    BEGIN { replacing = 0 }
    $0 == start {
      while ((getline line < block) > 0) print line
      close(block)
      replacing = 1
      next
    }
    $0 == end {
      replacing = 0
      next
    }
    replacing == 0 { print }
  ' "$TARGET_FILE" > "$OUTPUT_FILE"
  mv "$OUTPUT_FILE" "$TARGET_FILE"
  exit 0
fi

if grep -qxF "$HEADING_LINE" "$TARGET_FILE" 2>/dev/null; then
  awk -v heading="$HEADING_LINE" -v block="$BLOCK_FILE" '
    BEGIN { inserted = 0 }
    {
      print
      if ($0 == heading && inserted == 0) {
        print ""
        while ((getline line < block) > 0) print line
        close(block)
        inserted = 1
      }
    }
  ' "$TARGET_FILE" > "$OUTPUT_FILE"
  mv "$OUTPUT_FILE" "$TARGET_FILE"
  exit 0
fi

cp "$TARGET_FILE" "$OUTPUT_FILE"
[ -s "$OUTPUT_FILE" ] && printf '\n' >> "$OUTPUT_FILE"
{
  printf '%s\n\n' "$HEADING_LINE"
  cat "$BLOCK_FILE"
  printf '\n'
} >> "$OUTPUT_FILE"
mv "$OUTPUT_FILE" "$TARGET_FILE"
