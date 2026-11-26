#!/bin/bash
# Compiles and runs the announcement-voice checks: the built-in clips, the
# five-second limit on a replacement recording, and the stored choice.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-voice-clip.XXXXXX")"
/usr/bin/swiftc -parse-as-library -swift-version 5 -framework AVFoundation \
  "$ROOT/Sources/PrinterStudio/VoiceClip.swift" "$ROOT/Tools/TestVoiceClip.swift" -o "$OUT/check"
"$OUT/check"