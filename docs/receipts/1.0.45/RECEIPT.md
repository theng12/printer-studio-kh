# Release receipt — Printer Studio KH 1.0.45

app: printer-studio
version: 1.0.45 (build 46)
commit: e376d6900a54cfaaab6a1cdd36e1900f2e552c32
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.45.dmg
sha256: c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124
bytes: 4597721
scan: sha256=c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124 clean (dmg-scan step:
  110 files, excused [], scanner scan-dmg/2026-11-20, exit 0). The scan receipt in the same summary names that
  sha, so the scanned artifact and the built artifact are one file.
runner: `runner: gate-run.sh f05b010c16e5 at /Users/vengtheng/Developer/_orchestra/tools/gate-run.sh`, quoted from
  the run's own summary. `shasum -a 256` of that file at launch and after:
  f05b010c16e577986c796341a43b41b450e4639b82159f664c15b7b89d06bd5a, 43,672 B — the sha Release Tooling froze.
scanner: `tool studio-gate.sh 76dbf7aa09f5109bee4bb97705a0af3d1737e0b87230270c2f1bd3c779235ae9 at
  _orchestra/tools/pinned/studio-gate-76dbf7aa09f5109b.sh`, then `scan clean export of e376d6900a54cfaaab6a1cdd36e1900f2e552c32`,
  `SHIM PASS libkhsparkle.a matches the required sha`, `-- app: 0 failing check(s)`.
shim: `vendor/khsparkle/libkhsparkle.a` = `2bce760e…` — the first (current) entry in
  `_orchestra/tools/pinned/REQUIRED-SHIM.txt`, adopted in this release. Headers and exported symbols identical to
  the previous library, so it is the same source rebuilt reproducibly (`ZERO_AR_DATE=1`).
  The gate's own shim step: `SHIM OK vendor/khsparkle/libkhsparkle.a matches REQUIRED-SHIM.txt
  (2bce760e…, 2026-11-24)`.
gate config: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/1.0.45-20261123/gate.cfg
gate exit: 0 — `GATE PASS printer-studio e376d6900a54cfaaab6a1cdd36e1900f2e552c32 2026-11-24T09:16:47Z`,
  evidence lead/gate-20261124-155641-67402, 20 steps ok, idle-footprint UNMEASURED in the gate by design (it
  needs a running app; measured separately against the same artifact, below).
deep verify: `codesign --verify --deep --strict: exit 0`, printed by the build step
install-launch (blocking, the released image): `tool: install-launch-check.sh 847e77db5c99 at
  _orchestra/tools/pinned/install-launch-check-847e77db5c99d5d6.sh`, `artifact: dist/Printer Studio KH-1.0.45.dmg
  sha256:c989484b69f76dd0...`, `PASS: Printer Studio KH.app 1.0.45 launched hidden and is alive after 10s
  (pid 70502; com.theng12.printerstudio)`. It mounts the DMG, copies the app out of the image and launches that copy.
screenshots: `tool: check-app-screenshots.sh 7a035b7b380c at _orchestra/tools/check-app-screenshots.sh`,
  `PASS: 4 screenshots, each within size, named, referenced, and clean in text and metadata`, `rc=0`.
removal guard: `app/test-removal-guard.sh` — six decision PASS lines (missing, stale and future-dated refused; fresh
  and inside-window permitted; token equality), then `PASS: the command path asks, and the dialog is the only issuer`
  and `Removal guard checks passed.`
idle footprint: ten minutes, hidden instance of this build, own data dir, one real cycle first.
  `idle footprint: pid 97201 = 22 MB after 600s, -59 MB while idle (ceiling 500 MB)` then `OK`;
  ports 1 → 1, open files 37 → 37, threads 8 → 4, RSS 81 MB at the start of the window → 22 MB at the end.
  Pass is "flat" (nothing grew) and the number is the settled one, 22 MB. Log: lead/1.0.45-20261123/idle-sigterm-1045.log.
sigterm: `PASS: SIGTERM ended it in 169 ms`, `PASS: no crash report was added`, on the same instance. The app
  installs no signal handler (`SIGTERM` appears nowhere in app/Sources/PrinterStudio), so 143 is the default
  disposition; the status itself was measured on the same source at 1.0.40 by direct launch (BACKLOG, row
  20261122-314).
login item: registered: **no** — the system's own database has no row for this app. `sfltool dumpbtm` (unprivileged)
  exits 0, 242 lines, records for UID 501 present, 0 rows mentioning `printer`, 0 mentioning `theng12.printerstudio`;
  `launchctl print gui/501` has no Printer service; no `com.theng12.printerstudio.app` LaunchAgent; the app is in
  neither /Applications nor ~/Applications. Evidence: lead/1.0.45-20261123/LOGIN-ITEM-STATE.txt.
  Re-approval after the 2026-11-19 certificate reissue: UNMEASURED — with nothing registered there is no earlier
  registration here that could have lost its approval. Needs a Mac where the login item was registered before
  2026-11-19; Printer's own install is the Launcher's job.
publish state: **PUBLISHED.** The owner gave the authorisation in his own message in this transcript — "oh. you run it.
  i won't. please publish it." — after the two refusals quoted under Run history below. The publish protection cleared on
  that message, because it is the user's own words in this transcript; this session then ran `gh release create 1.0.45`
  at 10:07Z itself, and the remaining steps ran in the order the coordinating session gave, each with its readback.
publish rule: the coordinating session also relays the owner's standing rule — publish on a green gate without asking
  again each time. Recorded as a peer relay, not as a message in this transcript; the words that cleared this session's
  guard were his own ("oh. you run it. i won't. please publish it."), and that is what this publish rests on.
release: https://github.com/theng12/printer-studio-kh/releases/tag/1.0.45 — non-draft, not a prerelease. Asset
  c989484b69f7-Printer.Studio.KH-1.0.45.dmg, GitHub digest
  sha256:c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124, 4,597,721 B.
readback: anonymous download (curl, no token) of the release asset hashed to
  c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124 at 4,597,721 bytes — the bytes the gate scanned;
  READBACK OK. `gh release view` reports isDraft false, isPrerelease false, and the same digest.
anonymous download  https://github.com/theng12/printer-studio-kh/releases/download/1.0.45/c989484b69f7-Printer.Studio.KH-1.0.45.dmg
                   -> HTTP 200, 4,597,721 B, sha256 c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124
appcast item       -> SIGNATURE OK over that downloaded copy
  Everyone can fetch the file, and the signature is over the bytes they fetch — not over a local file that happens to
  share a name. The copy signed here was the anonymous download in the line above; the build-tree file was never signed.
appcast: item added on main (1cff57e), signed over the **downloaded published DMG**, not the build-tree copy, with
  ~/.kh-sparkle/com.theng12/printerstudio/private.key. Verified twice, the producer not grading its own work:
  1. `_orchestra/tools/appcast-verify.sh` → `PASS signature verifies against this artifact`, rc=0;
  2. after Pages redeployed, the **served** appcast at https://theng12.github.io/printer-studio-kh/appcast.xml —
     200, application/xml, 2,046 bytes, `<title>1.0.45</title>` present, enclosure
     …/releases/download/1.0.45/c989484b69f7-Printer.Studio.KH-1.0.45.dmg, length 4597721 — and the signature in that
     served file verified against the downloaded artifact → `PASS signature verifies against this artifact`, rc=0.
feed readback: **SERVED 1.0.45.** Read back from Pages (https://theng12.github.io/kh-releases/release.json, decoded
  from the signed envelope) at 10:31Z: version `1.0.45`, tagline "Print from any device to a USB-only printer", sha
  matching c989484b…, url
  https://github.com/theng12/printer-studio-kh/releases/download/1.0.45/c989484b69f7-Printer.Studio.KH-1.0.45.dmg,
  feed published_at 2026-11-24T10:30:40Z. The row was still 1.0.44 when the release went up; the publisher's own pass
  moved it. Nothing on this Mac ran that pass (`~/Library/LaunchAgents/com.khupdater.agent.plist` points at
  `khu-stub` and is not loaded), so the row is cited as an observation, not as a step this session performed.
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
retired: Printer Studio KH-1.0.43.dmg (4,585,008 B) moved to
  $HOME/Desktop/_trash/printer-studio-kh/2026-11-24 1.0.43 retired/ with MANIFEST.md, after checks found nothing
  pointing at it (no appcast item, no app-meta pointer, no process, no mounted image).
dist: 1.0.45 + 1.0.44 (current + previous)
github release: CREATED — URL and digests above
tag: `1.0.45` — annotated (object 337632a0), peels to `e376d6900a54cfaaab6a1cdd36e1900f2e552c32`; `git show
  1.0.45:app-meta.json` names 1.0.45. Pushed before the release existed.
retired (gate artifact): Printer Studio KH-1.0.45.dmg from gate run gate-20261124-152857-22737 (the run that failed
  studio-scan on the accepted-previous library) is in
  `$HOME/Desktop/_trash/printer-studio-kh/2026-11-24 gate-failed-1.0.45/` with a MANIFEST.md; it was never published.
not proven: a physical print; the login after a restart (needs the owner to restart this Mac); the idle number's
  coverage — a hidden run returns before the job watcher and Sparkle start, so 22 MB is the app's floor, not a
  claim about a full session; SIGTERM with work in flight (unisolatable today, unchanged from 1.0.40); the
  login-item re-approval question above.

## Run history (why three gate runs exist for one commit)

- `gate-20261124-152857-22737` — ran runner `abe8bf4a1a22`; **FAILED** at `studio-scan`, `SHIM`: the tree carried
  62ca9510 (accepted-previous) while the scanner requires the first entry, 2bce760e. Real finding; fixed by adopting
  the current library. Issue row `20261124-59`. Its artifact was moved to the Desktop trash (above).
- Second run (started 15:41, pid 89141) — **stopped on instruction**: it loaded runner `5f368fb48cab` before Release
  Tooling froze the runner, and an in-place rewrite of a running zsh script can execute shifted text. Lane hold
  released. No artifact was produced.
- `gate-20261124-155641-67402` — the run this receipt cites: frozen runner `f05b010c16e5`, 20 steps ok, GATE PASS.

## Not done here, named so nobody assumes it

- The screenshots were rendered offscreen from this build with invented printers; no window was ever put on screen
  and no live printer data was photographed.
- The idle instance was the shipped bundle launched hidden through its own launchd job on the app's signing-smoke
  entry with `PRINTER_STUDIO_TEST_DATA_DIR` pointed at a temporary folder; it never opened a window, registered a
  login item or touched printer services. The ACCEPTANCE row originally named `PRINTER_STUDIO_NO_WINDOW=1`; a docs
  commit after the gate corrects it to the entry actually used. No code changed after e376d69.