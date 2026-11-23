# Release receipt — Printer Studio KH 1.0.43

app: printer-studio
version: 1.0.43
commit: 9682325557b7dcbaf8bab53b59833d57e8c0812d
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.43.dmg
sha256: 005579eb4851b6345f0c2b05ce7b2cd21bdfdbf1250ea139567109c8f37290bc
bytes: 4585008
scan: sha256=005579eb4851b6345f0c2b05ce7b2cd21bdfdbf1250ea139567109c8f37290bc clean (dmg-scan, gate run)
gate config: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/1.0.43-20261123/gate.cfg
gate exit: 0 — GATE PASS printer-studio 9682325557b7dcbaf8bab53b59833d57e8c0812d 2026-11-23T15:20:47Z,
  evidence lead/gate-20261123-221039-63649, 16 steps ok, idle-footprint UNMEASURED
  scanner: `tool studio-gate.sh 727408ba…91028 at _orchestra/tools/pinned/studio-gate-727408ba92f53258.sh`
  then `scan clean export of 9682325557b7dcbaf8bab53b59833d57e8c0812d`
deep verify: `codesign --verify --deep --strict` exit 0, printed by the build step
dist: 1.0.43 + 1.0.42 (1.0.41 moved to the Desktop trash with a manifest)
github release: CREATED — https://github.com/theng12/printer-studio-kh/releases/tag/1.0.43, tag on the docs commit
  `fd58427`, non-draft, stored asset `005579eb4851-Printer.Studio.KH-1.0.43.dmg`, GitHub digest
  sha256:005579eb…90bc, 4,585,008 B
readback: anonymous download of the release asset hashed to 005579eb4851b6345f0c2b05ce7b2cd21bdfdbf1250ea139567109c8f37290bc
  at 4,585,008 bytes — the bytes the gate scanned; READBACK OK
feed readback: PENDING the next feed pass — the row is System's; the release is the newest published in the repo,
  which is what the generator reads
appcast: `appcast.xml` at the repo root updated to offer 1.0.43 (commit `527f7b7`), signed from the published DMG
  and verified `SIGNATURE OK`; serving is confirmed by the served-copy check below
feed/appcast agreement: printer-studio-kh  appcast 200 → 1.0.42   feed row 1.0.42   ✓ agree — measured by this
  session 2026-11-23T15:20:47Z (feed `published_at` 15:07:48Z per U001); for most of tonight they did not,
  and that is exactly the mismatch a user cannot diagnose, so the measurement time is part of the claim.
appcast served: https://theng12.github.io/printer-studio-kh/appcast.xml — fetched from the internet in this
  session: 200, one item, `sparkle:shortVersionString` 1.0.43, served sha256
  fe2d3df6f387c0d749f20eefd9bf32d7eacc077b0d0add968ea3737595dec93e; the served `edSignature` verified against
  the published DMG (4,585,008 B, sha 005579eb…) → **SIGNATURE OK**
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
commits: gated commit 9682325; the docs commit that carries `docs/receipts/` follows it and differs only in
  `docs/receipts/` — check with `git diff --stat 9682325..<tag>`; the released image is the gated build
retired: Printer Studio KH-1.0.41.dmg, with a manifest in $HOME/Desktop/_trash/printer-studio-kh/
self-update: **enabled in code; the end-to-end loop still unproven** — 1.0.43 vendors the fixed shim
  (`818826a7…`, `expand_tilde()` via `getpwuid` at `khsparkle.m:182`), which the shim's harness proves on
  these exact bytes: `5/token-home-missing-names-path` passes with the expanded path printed in full
  (`refused: hold token file missing or unreadable: $HOME/…/studio.kh.harness/missing-token`) — that line is the
  expansion, visible in a refusal. **Not** `2b/token-home`: that case passes an absolute path, so it proves only
  that an explicit token path reads, and the comment above it in the harness overclaims.
not proven: a version changing by itself (needs an install of this build plus a later release); **the shipped
  plist's own `~/…` resolving end to end on this Mac** — proving that needs a real launch of the app, which puts
  a menu-bar item on the owner's desktop and is not done without his word or a quiet point; physical print; the
  login after a restart; ten-minute idle footprint

## Evidence

- Hold suite and signing smoke pass on the built app at this commit; the packaged build launches hidden and
  stays alive with the framework embedded.
- `codesign --verify --deep --strict` exit 0 after the app seal, with Sparkle signed inside-out first.
- Shim harness on the vendored bytes: `HARNESS: all assertions passed`, zero FAIL lines, including
  `ASSERT 11` — without the entitlement the app is dead on `Library not loaded: @rpath/Sparkle.framework/…`,
  with it alive after 1.2 s.
- Run order checked, not assumed: the library was built 19:59:28, vendored 21:55:02, and the harness ran
  21:59:21 — after the bytes it is cited for.
- **Two facts that stop a test passing for the wrong reason:** the app's own token file does not exist on this
  Mac yet (`~/Library/Application Support/PrinterStudio/hold-token` absent; only the legacy one), so any case-1
  run would first depend on the migration, which itself runs at launch; and a disposable `HOME` cannot redirect
  the lookup — the fix resolves via `getpwuid(getuid())->pw_dir`, which is precisely why the harness assertion
  exists.
- Two of Displays' three hold-configuration cases (shipped `~/…`, absent key, absolute path) were **not** run
  against the shipped app for the reason in "not proven"; the property they would show is proven on the same
  library bytes by the harness, and the shipped hold route is proven separately by
  `test-maintenance-hold-live.sh`.
