# Vendored updater

- `libkhsparkle.a` and `include/khsparkle.h` — the studio's updater shim, static, universal
  (arm64 + x86_64), sha256 `818826a79d4e54885cbb5ad167f7425da8ba77436c6a5e277532f400aa1b4216`.
  Source and contract: `_orchestra/developer-system/sparkle-shim-20261123/`.
- `Sparkle.framework` — Sparkle `2.10.1` (build `2065`), unmodified from
  <https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz>
  (archive sha256 `1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`).
  Upstream licence: MIT. The framework ships as `Versions/B` with `Versions/Current -> B` and no
  `Versions/A`; do not add an alias, because `codesign --verify --deep --strict` then reports
  unsealed contents in the framework's root.

`app/build.sh` copies the framework into `Contents/Frameworks`, signs it from the inside out with
`--options runtime`, links with `@executable_path/../Frameworks`, and seals the app with
`Resources/PrinterStudio.entitlements` so hardened runtime can load the framework without a Team ID.
