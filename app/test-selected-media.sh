#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/test-selected-media.XXXXXX")"
SOURCES=()
while IFS= read -r file; do
  case "$(basename "$file")" in App.swift|Views.swift|RenderFixtures.swift) continue ;; esac
  SOURCES+=("$file")
done < <(find "$ROOT/Sources/PrinterStudio" -name '*.swift' | sort)
/usr/bin/swiftc -parse-as-library -swift-version 5 "${SOURCES[@]}" "$ROOT/Tools/TestSelectedMedia.swift" -o "$OUT/check"
"$OUT/check"
/usr/bin/swiftc -typecheck -parse-as-library -swift-version 5 -framework SwiftUI -framework AppKit "$ROOT/Sources/PrinterStudio"/*.swift
