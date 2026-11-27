# Release receipt — printer-studio 1.0.49

app: printer-studio
version: 1.0.49 (build 50)
commit: 9b936346ff0ad292d058825945d25ac94bc4a378
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.49.dmg
sha256: 3399ddb26e7cf5fe5be5d3948597811326d2dad5ae8a3833649aa2c52e5d6dc7
bytes: 4696382
scan: sha256=3399ddb26e7cf5fe5be5d3948597811326d2dad5ae8a3833649aa2c52e5d6dc7 clean — scan-dmg/2026-11-20, exit 0, 110 files, 0 excused
gate config: $HOME/Developer/_orchestra/tools/gate-configs/printer-1.0.49.sh
gate exit: 0 — `GATE PASS printer-studio 9b936346ff0ad292d058825945d25ac94bc4a378 2026-11-27T06:02:55Z`,
  `runner: gate-run.sh 8df512ad14da` at `$HOME/Developer/_orchestra/tools/gate-run.sh`,
  evidence `$HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/gate-20261127-125749-57684`,
  27 steps ok
feed readback: appcast **SERVED 1.0.49** `length="4696382"` (`https://theng12.github.io/printer-studio-kh/appcast.xml`,
  Ed25519 signature `pf8xUqxNq8n/RAgp3K5OAHa1yX/fCWmF9esBPqNfzBILHjjk1FbQMsGBGNrNAjUnSUklwHfSjoSL1axC7EzLBw==`
  verified rc=0 via `appcast-verify.sh` against the anonymous download and `SUPublicEDKey`;
  `appcast-serves-version.sh … --bundle "dist/Printer Studio KH.app"` → `PASS appcast: printer-studio-kh serves 1.0.49
  (feed printer-studio, 6 item, enclosure github.com 4696382 bytes)`).
  Estate feed row **SERVED 1.0.49**, published `2026-11-27T06:12:30.795Z`, verified here with
  `feed-verify.sh printer-studio --expect-version 1.0.49 --expect-sha 3399ddb26e7cf5fe5be5d3948597811326d2dad5ae8a3833649aa2c52e5d6dc7
  --public-key app/Resources/PublisherKey.txt` → `PASS signature — Ed25519 verified against key …`
  (24,949 feed bytes, 64 signature bytes), row version `1.0.49`, sha256 `3399ddb2…`, 4,696,382 B,
  tagline `Print from any device to a USB-only printer`, rc=0. The publisher's own pass (S001, quoted from its
  reply) records the envelope sha256 `516bf3ba83fe07271403fb48f090d881b8b0b581372d837ea56c19deb574eeaa`,
  14 rows, `1 row(s) changed, 0 removed by name`, and confirms the anonymous download, the tag peel and the
  served appcast independently. The row's `file` is the local name `Printer Studio KH-1.0.49.dmg`; the
  GitHub asset carries the `3399ddb26e7c-` prefix — by design (`file` is the local name, `url` is GitHub's
  stored name), not drift.
  Byte identity of the served feed, measured independently by U001 and reproduced here: the served
  `release.json` is **33,393 B**, sha256 `516bf3ba83fe07271403fb48f090d881b8b0b581372d837ea56c19deb574eeaa`,
  `last-modified: Fri, 27 Nov 2026 06:28:01 GMT`, its git blob id `35c20fb43126883e80bcda5ab800d8a93e9178ec`
  equals `kh-releases` `main:release.json` (so the served bytes are the committed bytes, not an earlier
  envelope); the commit that changed it is `2e3bdfd` at 2026-11-27 06:27:23Z. The 24,949 bytes above are the
  signed feed payload inside that envelope, not a different measurement. An earlier read of 1.0.48 was the
  Pages edge cache (`max-age=600`), not a missing row.
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
retired: `Printer Studio KH-1.0.47.dmg` (sha256 `3dfe041fd8111e54b576dda57526b49da3cc82c39b4922b7a02820fafd99fbc7`, 4,598,200 B) moved by
  `app/finalize-dist.sh` to `$HOME/Desktop/_trash/printer-studio-kh/2026-11-27 installers retired at 1.0.49/dist/`
  with `MANIFEST.md`; `dist/` now holds 1.0.49 + 1.0.48 only.
not proven: four items are **not exercised** by this release — recorded once, never as passed:
  - **a physical print** — not exercised on this Mac; no paper was printed from this build.
  - **a page printed from a real iPhone** — not exercised. The AirPrint path was measured from this Mac
    as a remote client (see below); the print step was refused by the owner's queue being offline at the
    time, so the fix is proven in what the app now says, not in paper.
  - **the login-after-restart half** — not exercised; needs a restart of a Mac on an installed copy.
  - **a real self-update** — not exercised; no unattended version change was observed on this Mac.
  `idle-footprint: UNMEASURED by the gate` (no `IDLE_PID` in the config); measured separately on this
  build: **81 MB after 60 s, +0 MB while idle, ceiling 500 MB** (`check-idle-footprint.sh`, OK), on a
  hidden launch of the shipped app on the signing-smoke entry with a temp data dir.
  **Install readback is drives-only from 1.0.48's pass:** no `/Applications/Printer Studio KH.app` on
  this Mac and no printer entry in the Launcher's config, so this release's automatic install is
  `UNMEASURED`.

## What changed

1. **The sidebar stops moving.** Measured in the real `MainWindow` at 860x580 and 1024x720 before the
   fix: selecting every sidebar row moved nothing; a running action made the footer grow 23 pt and the
   list shrink 23 pt; a result banner pushed the page down by its own height. Now the busy line replaces
   the status text in the footer's always-present row (fixed 14 pt row), and the result banner floats at
   the bottom of the page. `app/test-sidebar-stable.sh` drives every measurable sidebar row through the
   list's own selection API, a busy action and a banner, and fails if any nav row, the list, the footer
   or the page moves at either size. Known harness limit: the sticker page cannot be inserted in the
   offscreen host (AttributeGraph), so it is skipped here and covered by its own page render.
2. **A phone print failure is named.** `CUPS.detailedPrinters()` now carries `printer-state-message` and
   `printer-state-reasons`; `QueueHealth` turns them into a cause and the one fix; the Sharing page and
   Overview show an offline shared queue in plain words with a `Release it` / `Keep it ready` action.
   `app/test-queue-health.sh` proves the mapping (19 checks) and that the screens carry it.
   Measured on the LAN against the owner's shared queue on the office Mac, same LAN:
   - discovery PASS — the bridge record resolves to `…local.:631`, `rp=printers/HPLaser107a`;
   - announce PASS — port 631 answers a plain remote IPP client from this Mac;
   - ACL PASS — `printer-is-shared=true`, no `requesting-user-name-allowed`, remote PDF `Validate-Job`
     `successful-ok`;
   - print FAIL — a PDF `Print-Job` sent as an iPhone sends it was accepted (job 10) and stuck at
     `processing` with `printer-state-message = "The printer is offline."`, reasons
     `offline-report,connecting-to-device`; `retry-job` keeps it waiting instead of failing it. Job 10 was
     cancelled afterwards.
3. **Guided first use.** Overview opens with `Start here`: plug in → set it up → share it with the phone
   → print a test page, each line green from live state with the one button that does the step. Settings
   points to it; the setup page's steps use plainer words.
4. **The asset carries its sha12 prefix.** Published through `packaging/github-asset.sh`, so the GitHub
   asset is `3399ddb26e7c-Printer.Studio.KH-1.0.49.dmg` and the appcast enclosure names it.
5. **Offscreen renders keep their fixtures again** (`MainWindow`'s `onAppear` re-read is skipped under
   the render harness), so `docs/screenshots/overview-light.png` and `settings-light.png` were rendered
   from this build.

## Closeout

retired: `Printer Studio KH-1.0.47.dmg` (4,598,200 B) via `app/finalize-dist.sh`; `dist/` now holds
  `1.0.49` + `1.0.48`. No worktree was created for this release (the branch was built in the canonical
  checkout); release branch `release/1.0.49` is pushed and kept.

## Evidence

- gate log: `$HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/gate-20261127-125749-57684/summary.txt`
- readback command and output: `curl -fsSL https://theng12.github.io/printer-studio-kh/appcast.xml` + `appcast-verify.sh /tmp/ps-1.0.49-asset.dmg <SUPublicEDKey> <edSignature>` → `PASS signature verifies against this artifact`; `appcast-serves-version.sh theng12/printer-studio-kh 1.0.49 --bundle "dist/Printer Studio KH.app" --app printer-studio` → `PASS … serves 1.0.49 (6 item, enclosure github.com 4696382 bytes)`
- install-media readback: S001 refreshed NOVA, ORICO and UGREEN to 1.0.49 at snapshot
  `516bf3ba83fe · 14 rows · 2026-11-27T06:12:30.795Z`, each drive retiring 1.0.48 to its own trash with a
  manifest. S001's drive pass ends with a false `update-from-ssd.sh still needs Python` line on every drive
  (its comment matched by the kit check, filed as issue `20261127-18`); nothing on the drives needs changing.
- install acceptance: gate step `install-launch` mounted the DMG, copied the app out and launched that copy hidden → `PASS: Printer Studio KH.app 1.0.49 launched hidden and is alive after 10s (pid 61081; com.theng12.printerstudio)`; gate step `hold-live` ran the same app under launchd with the hold contract. **On a Mac: not installed and not verified** — this Mac carries no installed copy, so an automatic install is `UNMEASURED`.
- estate feed: `feed-verify.sh printer-studio --expect-version 1.0.49 --expect-sha 3399ddb2… --public-key app/Resources/PublisherKey.txt` → `PASS signature — Ed25519 verified` (24,949 feed bytes), row `1.0.49` / `3399ddb2…` / 4,696,382 B
- AirPrint measurement: this Mac, remote IPP client to the owner's shared queue, 2026-11-27 12:15–12:18 local. Details in the notes folder.