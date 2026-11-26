# Release receipt — printer-studio 1.0.48

app: printer-studio
version: 1.0.48 (build 49)
commit: 17b740b9f582bd0d5ecc6ecba3242112ed972654
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.48.dmg
sha256: 6b57ae1630ffb21f55eb90d74cd66ccef446d0e1c6f0bcec0e1dac9a7f7d6bae
bytes: 4597909
scan: sha256=6b57ae1630ffb21f55eb90d74cd66ccef446d0e1c6f0bcec0e1dac9a7f7d6bae clean — scan-dmg/2026-11-20, exit 0, 110 files, 0 excused
gate config: $HOME/Developer/_orchestra/tools/gate-configs/printer-1.0.48.sh
gate exit: 0 — `GATE PASS printer-studio 17b740b9f582bd0d5ecc6ecba3242112ed972654 2026-11-26T15:29:52Z`,
  `runner: gate-run.sh 8df512ad14da` at `$HOME/Developer/_orchestra/tools/gate-run.sh`,
  evidence `$HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/gate-20261126-222542-17801`,
  24 steps ok
feed readback: appcast **SERVED 1.0.48** `length="4597909"` (`https://theng12.github.io/printer-studio-kh/appcast.xml`,
  Ed25519 signature `dvNKEQB0VGixTyjt+fD0NlR7N9lmPREQEimXFrssDhf2+QrYls9PF3NGU6tIPY1Fy8gC18uMKXOMjT46SkbiAg==`
  verified rc=0 via `appcast-verify.sh` against anonymous download and `SUPublicEDKey`); estate feed row
  **SERVED 1.0.48**, published `2026-11-26T15:47:03.557Z` (14 rows, publisher commit `9226a557054c`), verified
  here independently with `feed-verify.sh --public-key app/Resources/PublisherKey.txt` →
  `PASS signature — Ed25519 verified` (24,149 feed bytes, 64 signature bytes), row version `1.0.48`,
  sha256 `6b57ae1630ffb21f55eb90d74cd66ccef446d0e1c6f0bcec0e1dac9a7f7d6bae`, 4,597,909 B, file
  `Printer Studio KH-1.0.48.dmg`, tagline present, rc=0. The row is S001's; its pass landed after the
  sha/bytes/tag/asset handoff (msg `94e8128f`).
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
retired: `Printer Studio KH-1.0.46.dmg` (sha256 `364149355c853be29f9d21f83e2c18e3ca44ba7bae7a554d27b44d80bc88117c`,
  4,598,040 B) moved to
  `$HOME/Desktop/_trash/printer-studio-kh/2026-11-26 installers retired at 1.0.48/dist/` with `MANIFEST.md`;
  worktree `1.0.48` (26 MB) and 1.0.47 `dist/Printer Studio KH.app` residue (12 MB) retired to
  `$HOME/Desktop/_trash/printer-studio-kh/` with manifests
not proven: three items are **not exercised** by this release — recorded once, never as passed:
  - **a physical print** — not exercised; no paper was printed.
  - **the login-after-restart half** — not exercised; needs a restart of this Mac on an installed copy.
  - **a real self-update** — not exercised; no unattended version change was observed on this Mac.
  Also `idle-footprint: UNMEASURED — no IDLE_PID in the config`.
not run by any gate: test-airprint-bridge.sh, test-airprint-installer.sh, test-appearance.sh, test-automatic-usb.py, test-bridge-reannounce.sh, test-helper-orphan.sh, test-label-media.sh, test-label-printing.sh, test-list-presentation.sh, test-paper-sizes.sh, test-remote-print.sh, test-urf-to-pdf.sh

## What changed

No app source and no screen changed.

1. **Fast subset wired into the gate (`fast-subset` step in `gate-configs/printer-1.0.48.sh`).**
   Seven suites, all verified exit 0 and each ≤5 s (12.4 s total):
   - `python3 -I app/Tools/test-signing-verifier.py` — 0.1 s (also verified exit 0 under `/usr/bin:/bin`)
   - `bash app/test-test-page.sh` — 1.0 s
   - `bash app/test-voice-clip.sh` — 1.0 s
   - `bash app/test-job-watch.sh` — 0.7 s
   - `bash app/test-helper-ceiling.sh` — 2.8 s
   - `bash app/test-disk-space.sh` — 2.2 s
   - `bash app/test-shell-ceiling.sh` — 4.6 s
2. **Two red full-UI typecheck tests pinned to `macosx26.5` (same fallback as `app/build.sh:46-47`).**
   - `app/test-selected-media.sh`: exited 0 in 14 s (was red on CLT-27.2 SwiftUI `@State` macro gap).
   - `app/test-error-report.sh` + `app/Tools/TestErrorReport.swift`: exited 0 in 26–31 s; also moved
     `TestErrorReport.testTailFileFixtures()` scratch from relative `_trash/test-fixtures-*` into
     `fm.temporaryDirectory` (`$TMPDIR`) with `defer` cleanup, and retired the stale `_trash` fixture
     dirs to `$HOME/Desktop/_trash/printer-studio-kh/2026-11-26 stale TestErrorReport fixtures/`.
   Both stay outside the gated fast subset and are listed in `docs/UNGATED-TESTS.txt`.
3. **All ungated tests made visible (`docs/UNGATED-TESTS.txt` + `app/Tools/check-ungated-tests.sh`).**
   Gate step `ungated-list` enforces that every `test-*.sh` / `test-*.py` in the repo is either run
   by some gate config or explicitly named in `docs/UNGATED-TESTS.txt` (14 total: the 12 `not run by any gate`
   above plus `test-selected-media.sh` and `test-error-report.sh`).

## Publish & readback

- **Tag:** `1.0.48` (annotated, peels to `17b740b9f582bd0d5ecc6ecba3242112ed972654`, pushed to `origin`).
- **Release:** `https://github.com/theng12/printer-studio-kh/releases/tag/1.0.48` (non-draft, not prerelease;
  body from `app/release-notes.sh 1.0.48 CHANGELOG.md` with no duplicate `##` heading; asset
  `Printer.Studio.KH-1.0.48.dmg`, 4,597,909 B, `sha256:6b57ae1630ffb21f55eb90d74cd66ccef446d0e1c6f0bcec0e1dac9a7f7d6bae`).
  Note: `release-preflight.sh` passed sha/bytes/scan/anonymous-download/screenshots/home-path, and
  recorded a `release-asset-name-check.sh` finding on the unprefixed asset name (`Printer.Studio.KH-1.0.48.dmg`
  without `<sha12>-`; fix forward in the next release).
- **Appcast:** commit `a9970927892b7001a904a8169a3b63dbf89f2c07` on `main`, Pages workflow `45850694149`
  succeeded; anonymous readback of `https://theng12.github.io/printer-studio-kh/appcast.xml` serves item
  `1.0.48` (`length="4597909"`), and `appcast-verify.sh` verified its `sparkle:edSignature` (`rc=0`) against
  the anonymous release asset download and `app/Resources/Info.plist` `SUPublicEDKey`.
- **Estate feed (`kh-releases`):** handed sha/bytes/tag/asset to S001 (`msg 94e8128f`); S001's pass landed —
  `published 2026-11-26T15:47:03.557Z`, publisher commit `9226a557054c`, `14 rows, integrity: 1 row(s) changed,
  0 removed by name`, verified here independently with `feed-verify.sh --public-key app/Resources/PublisherKey.txt`
  → `PASS signature — Ed25519 verified` (24,149 feed bytes, 64 signature bytes), `rc=0`.
  S001 also confirmed the notes body carries no duplicate heading this time (560 chars, no home path or
  internal names), and that the asset-name finding is the same shape as 1.0.47 (recorded in `BACKLOG.md`
  as a 1.0.49 fix-forward through `packaging/github-asset.sh`; a published asset is never renamed).

## Closeout

retired: `Printer Studio KH-1.0.46.dmg` (4,598,040 B) via `app/finalize-dist.sh` (`dist/` now holds `1.0.48` + `1.0.47`);
  `worktrees/1.0.48` (26 MB) and 1.0.47 `dist/Printer Studio KH.app` residue (12 MB) moved to `$HOME/Desktop/_trash/printer-studio-kh/` with manifests.

## Evidence

- gate log: `$HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/gate-20261126-222542-17801/summary.txt`
- readback command and output: `curl -fsSL -o "$APPCAST" https://theng12.github.io/printer-studio-kh/appcast.xml` + `appcast-verify.sh` → `PASS signature verifies against this artifact` (`1.0.48`, `length="4597909"`);
  `feed-verify.sh printer-studio --expect-version 1.0.48 --expect-sha 6b57ae16… --public-key app/Resources/PublisherKey.txt` → `PASS signature — Ed25519 verified`, row `1.0.48` / `6b57ae16…` / `4,597,909 B`
- install acceptance: `UNMEASURED` on an end-user Mac (covered by gate step `install-launch` mounting `Printer Studio KH-1.0.48.dmg` and launching hidden). Automatic install now has a served row; S001 reports all four install drives refreshing and will report the result — that readback is not yet in hand, so "installed everywhere" is NOT claimed.
