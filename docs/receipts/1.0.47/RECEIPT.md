# Release receipt — printer-studio 1.0.47

app: printer-studio
version: 1.0.47 (build 48)
commit: 4c6f9a328fc4b28ab20086800e7f1342e4ea867d (the gated artifact commit); tooling follow-up
  654e00a, merged as 2d2e2026c54b5ec84d1b0a0f49de35083ac46924, gates separately and changes no shipped source
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.47.dmg
sha256: 3dfe041fd8111e54b576dda57526b49da3cc82c39b4922b7a02820fafd99fbc7
bytes: 4598200
scan: sha256=3dfe041fd8111e54b576dda57526b49da3cc82c39b4922b7a02820fafd99fbc7 clean — scan-dmg/2026-11-20, exit 0, 110 files, 0 excused
gate config: $HOME/Developer/_orchestra/tools/gate-configs/printer-1.0.47.sh
gate exit: 0 — `GATE PASS printer-studio 4c6f9a328fc4b28ab20086800e7f1342e4ea867d 2026-11-26T11:05:47Z`,
  runner `gate-run.sh 8df512ad14da` at `~/Developer/_orchestra/tools/gate-run.sh`,
  evidence `~/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/gate-20261126-180146-72674`,
  22 steps ok. Second gate for the tooling follow-up — see below.
feed readback: **SERVED 1.0.47.** `feed-verify.sh printer-studio --expect-version 1.0.47
  --expect-sha 3dfe041f…` → `PASS signature — Ed25519 verified`, then version `1.0.47`, sha256
  `3dfe041fd8111e54b576dda57526b49da3cc82c39b4922b7a02820fafd99fbc7`, 4,598,200 B, file
  `Printer Studio KH-1.0.47.dmg`, tagline "Print from any device to a USB-only printer",
  published `2026-11-26T11:24:07.762Z`, rc=0. Same sha and bytes as this receipt's artifact.
  The row is System's (S001, sole owner of the feed and the `khu` generator): this session did not
  write it. At 11:20Z Pages still served 1.0.46, so the exact sha, bytes, tag, asset name and URL were
  handed over; S001 ran its pass and the row moved.
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
retired: `Printer Studio KH-1.0.45.dmg` (sha256 c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124,
  4,597,721 B) moved to
  `$HOME/Desktop/_trash/printer-studio-kh/2026-11-26 installers retired at 1.0.47/` with a `MANIFEST.md`.
not proven: three items are **not exercised** by this release — recorded once, never as passed:
  - **a physical print** — no paper was printed; nothing in the printer path changed.
  - **the login-after-restart half** — not exercised; it needs a restart of this Mac on an installed copy.
  - **a real self-update** — no unattended version change was observed on this Mac. Covered by
    `app/test-update-checker.sh` and `app/test-maintenance-hold*.sh`, not by an observed update.

## What changed

No app source changed. Two release-tooling divergences from the owner's rules, both recorded in
`developer-utilities/OPEN-WORK.md` and confirmed independently by Release Tooling:

1. **Retention depth 3 → 2 in one place.** `app/finalize-dist.sh` encoded the depth twice in literals
   that did not derive from each other — `others[:2]` at `:62` (the pins loop) and `index < 3` at
   `:124` (the sweep). One named `KEEP=2` now feeds both. `:62`'s loop is an **evidence validator**,
   not a counter, so the test proves both halves: the third installer leaves `dist/` for the one
   trash, and the installer retained as the previous one is still refused when its ledger evidence is
   withdrawn. `app/Tools/test-finalize-dist.sh` asserts the kept set is
   `1.0.14 + 1.0.13 + manifest-protected 1.0.10` and that `1.0.12` is in the trash and not in `dist/`.
2. **No checkout `_trash`.** Five named scripts plus the other test scripts that still wrote
   `$ROOT/../_trash` now take their scratch from `$TMPDIR` (`mktemp -d "${TMPDIR:-/tmp}/…"`), the
   shape `app/build.sh:74` already used. `finalize-dist.sh`'s pins document is `mktemp -d` under
   `TMPDIR` and removed by a trap on every exit path. `render-pages.sh` retired stale PNGs into a
   `_trash` beside its evidence folder, which may sit inside the checkout; that goes to `TMPDIR` too.
   Proof: `lead/1.0.47-20261126/no-checkout-trash.sh` (gate step `no-checkout-trash`) — no source path
   builds one, no directory exists in or beside the checkout, and all five named scripts name `TMPDIR`.

Two defects were found and fixed while proving the above — neither was in the brief:

3. **The pins document named the trash ROOT, so the two retirements split across two layouts.**
   `retain-dmgs.sh` retires into `<retirement_trash>/dist/` while the sweep retires into
   `<retirement_trash>/`; pinning `~/Desktop/_trash` put them side by side in one trash. This was not
   theoretical: running the fixed script for real on 1.0.47 put 1.0.45 in
   `_trash/2026-11-26 printer-studio-kh-retired-installers/`, beside every other app's folders. Both
   now name one folder, `~/Desktop/_trash/printer-studio-kh/<date> installers retired at <version>/`,
   built once from the receipt's version, and the test asserts the shape and that both kinds of
   retirement share it. Fixed in `654e00a`.
4. **`test-dmg-retention.sh` had been red since 1.0.46.** No gate step ran it. `build.sh` gained the
   vendored-shim check and the toolchain source in 1.0.46, and the fixture copied neither, so it died
   before the assertion it exists for. It copies both now and passes.

## Gate — the artifact, and the follow-up

- **1.0.47 artifact:** `GATE PASS printer-studio 4c6f9a328… 2026-11-26T11:05:47Z`, runner
  `gate-run.sh 8df512ad14da`, 22 steps ok, evidence `lead/gate-20261126-180146-72674`. The 1.0.46
  runner pin (`528de9fe53d0`) no longer names the canonical bytes; `8df512ad14da721f` does, and no
  pin exists in `_orchestra/tools/pinned/` for it — the gate summary names it, so the run is
  attributable even though `pinned/` does not carry it.
- **Tooling follow-up (654e00a → 2d2e202):** `GATE PASS printer-studio 2d2e2026c5… 2026-11-26T11:24:14Z`,
  same runner, config `gate-configs/printer-1.0.47-main.sh`. Its first two steps are the reason it is
  not a rebuild: `tooling-only` proves no file under `app/Sources`, `app/Resources`, `app/Helper`,
  `app/Filters` or `vendor` changed since the gated commit, and `published-artifact-unchanged` proves
  `dist/`'s DMG still hashes to the published sha. A rebuild cannot happen here by design — one
  published version is one artifact, forever.

## Publish

publish rule: the owner's standing publish-on-green rule (2026-11-24), relayed by Developer - Utilities
  in this session's brief: a green gate plus the Developer's check authorises publication.
release: https://github.com/theng12/printer-studio-kh/releases/tag/1.0.47 — non-draft, not a
  prerelease; asset `Printer.Studio.KH-1.0.47.dmg`, GitHub digest
  sha256:3dfe041fd8111e54b576dda57526b49da3cc82c39b4922b7a02820fafd99fbc7, 4,598,200 B.
tag: `1.0.47` — annotated, peels to `4c6f9a328fc4b28ab20086800e7f1342e4ea867d`;
  `git show 1.0.47:app-meta.json` names 1.0.47 and `localFile: Printer Studio KH-1.0.47.dmg`.
  Pushed before the release existed. `--verify-tag` was passed to `gh release create`.
readback: anonymous download (curl, no token) of the release asset — HTTP 200, 4,598,200 B,
  sha256 3dfe041fd8111e54b576dda57526b49da3cc82c39b4922b7a02820fafd99fbc7 — the bytes the gate
  scanned. `gh release view` reports draft false, prerelease false, the same digest.
appcast: item added on main (`f3265ff`), signed over the **anonymous download above**, not the
  build-tree file, with `~/.kh-sparkle/com.theng12/printerstudio/private.key`. Verified twice, the
  producer not grading its own work:
  1. `_orchestra/tools/appcast-verify.sh` against the downloaded artifact → `PASS signature verifies
     against this artifact`, rc=0;
  2. after Pages redeployed, the **served** appcast at
     https://theng12.github.io/printer-studio-kh/appcast.xml — HTTP 200, 3,680 B, `<title>1.0.47</title>`
     present, `length="4598200"` — and the signature in that served file verified against the
     downloaded artifact: `PASS signature verifies against this artifact`, rc=0.

## Measurement

idle footprint: ten minutes, hidden instance of this build, own data dir, one real cycle first.
  `idle footprint: pid 78519 = 78 MB after 600s, -3 MB while idle (ceiling 500 MB)` then `OK`;
  ports 1 → 1, open files 35 → 34, threads 8 → 4, RSS 81 MB at the start of the window → 78 MB at the
  end. Pass is "flat" (nothing grew); the number is the settled one, 78 MB. SIGTERM ended it in
  151 ms with no crash report added. Log: `lead/1.0.47-20261126/printer-idle-1047.log`.
  A hidden run starts no job watcher, so this is the app's floor, not a full session.
  Covers one full cycle and a long idle window; a whole-fleet run and a long job run are not exercised
  by this release.

## Housekeeping — closeout

dist: 1.0.47 + 1.0.46 (current + previous), checked by `check-dist-retention.sh`-style inspection and
  by the gate's `published-artifact-unchanged` step. Retirement ran the **real fixed
  `app/finalize-dist.sh`**, not a hand move — its first real run: `Pinning 1.0.47, 1.0.46`, then
  `Retired Printer Studio KH-1.0.45.dmg` and `dist keeps: 1.0.47, 1.0.46`.
retired: `Printer Studio KH-1.0.45.dmg` (sha256 c989484b69f76dd0b37255c6b4c9add2559bbc3fea94375090ec3d011a696124,
  4,597,721 B, 4.4 MB) in `$HOME/Desktop/_trash/printer-studio-kh/2026-11-26 installers retired at 1.0.47/`
  with a `MANIFEST.md`. Checks before the move: no mounted image, no open handle, no process using it;
  the appcast's 1.0.45 item names the GitHub release, not this folder; `app-meta.json` names 1.0.47.
  The first real run used the pre-fix trash-root pin and landed it beside every other app's folders;
  it was moved to the app-and-date folder in the same turn, and the code was fixed so it cannot recur.
ledger: `dist/.release-dist.json` gained a truthful 1.0.46 entry (its own receipt as evidence) — it
  held only 1.0.39/1.0.40 before, which is why the pins stage would have refused. Still records
  1.0.39/1.0.40 entries whose files no longer exist; the shared helper drops a recorded file whose
  path is gone, and it did.
worktree: `_orchestra/developer-utilities/printer-studio-kh/worktrees/1.0.47`, branch `release/1.0.47`,
  merged into `main` (2d2e202) and pushed. Retired after this receipt is committed.
evidence produced: 2 gate evidence dirs (`gate-20261126-180146-72674` cited here; the tooling gate
  wrote its own), `no-checkout-trash.sh`, `no-checkout-trash` step, `dmg-check.sh`, `shim-check.sh`,
  `hold-live-receipt.json`, `installed-readback-1.0.47.json`, `printer-idle-1047.log`. No scratch logs
  are cited as evidence.

## Not this session's

The estate feed row (`kh-releases/release.json`) is System's (S001). This session did not write it;
it handed over the exact sha, bytes, tag, asset name and URL. S001 ran its pass: the row now serves
1.0.47 at `published_at 2026-11-26T11:24:07.762Z`, verified independently above.