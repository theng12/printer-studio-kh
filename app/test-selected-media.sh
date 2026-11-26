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
# Same pin as build.sh:42-47 — the CLT 27.2 SDK's SwiftUI macro plugin ships only with Xcode.
# shortcut: SDK 26.5 until the CLT ships the plugin; upgrade when it does.
SDK="$(/usr/bin/xcrun --show-sdk-path --sdk macosx26.5 2>/dev/null || true)"
[ -n "$SDK" ] || SDK="$(/usr/bin/xcrun --show-sdk-path)"
/usr/bin/swiftc -typecheck -parse-as-library -swift-version 5 -sdk "$SDK" -framework SwiftUI -framework AppKit "$ROOT/Sources/PrinterStudio"/*.swift
