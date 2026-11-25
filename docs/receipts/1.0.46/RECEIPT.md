# Release receipt — Printer Studio KH 1.0.46

app: printer-studio
version: 1.0.46 (build 47)
commit: 6a5e76bc2677dee804b186835edc28b71a0b8b18
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.46.dmg
sha256: 364149355c853be29f9d21f83e2c18e3ca44ba7bae7a554d27b44d80bc88117c
bytes: 4598040

## What this release is

The packaging path pins its toolchain and names what it used (issue row `20261122-318`). No app
source, no bundled file and no screen changed: the only behaviour that differs is which `python3`
and `pkg-config` a build resolves, and what it prints when one is missing.

`app/toolchain.sh` puts Homebrew's bin and its newest `python@3` ahead of the 3.9 system stub;
`app/build.sh` and `app/render-pages.sh` source it, and the build prints the versions it ran with.
A tool that is still missing stops with the version it needs and the PATH it searched instead of a
traceback from inside a later script. `app/Tools/test-toolchain.sh` proves all four: idempotent
sourcing, resolution away from the stub under a non-login PATH, the message's content, and that no
packaging-path script calls a bare `python3` without the pin.

Measured before the change: under `PATH=/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.` this Mac gives
`python3 -> /usr/bin/python3 (3.9.6)` and `pkg-config -> MISSING`, while Homebrew has python 3.13.18
and `/opt/homebrew/bin/pkg-config`. Every embedded Python block on the packaging path compiles on
3.9, so nothing was broken by it — this closes the class, it does not repair an outage.

gate config: `_orchestra/tools/gate-configs/printer-1.0.46.sh`
runner: `runner: gate-run.sh 528de9fe53d0 at $HOME/Developer/_orchestra/tools/gate-run.sh`, quoted
  from the run's own summary; `shasum -a 256` of that file before and after the run:
  528de9fe53d0c0de552d30dca1b21092b073a24fac76daf53e21da738b3b6f46 — and the same sha as
  `_orchestra/tools/pinned/gate-run-528de9fe53d0c0de.sh`, the copy Plugin froze.
gate exit: 0 — `GATE PASS printer-studio 6a5e76bc2677dee804b186835edc28b71a0b8b18 2026-11-25T14:52:28Z`,
  evidence `lead/gate-20261125-214632-29461`, 20 steps ok.
scan: sha256=364149355c853be29f9d21f83e2c18e3ca44ba7bae7a554d27b44d80bc88117c clean (dmg-scan step:
  110 files, excused [], scanner scan-dmg/2026-11-20, exit 0). The scan receipt in the same summary
  names that sha, so the scanned artifact and the published artifact are one file.
shim: `vendor/khsparkle/libkhsparkle.a` = `2bce760e7749a0f21dfa378c53c391d039401355012e774a81b691043a3cb17f`,
  the **first (current)** entry in `_orchestra/tools/pinned/REQUIRED-SHIM.txt`. Checked, not edited:
  `app/Tools/test-toolchain.sh` is unrelated to it and the file is unchanged from 1.0.45. The gate's
  own shim step printed `SHIM OK … (2bce760e…, 2026-11-24)`, and the pinned scanner printed
  `SHIM PASS libkhsparkle.a matches the required sha` and `-- 1.0.46: 0 failing check(s)`.
build: `==> Toolchain: Python 3.13.18; pkg-config /opt/homebrew/bin/pkg-config; swiftc /usr/bin/swiftc`,
  then `codesign --verify --deep --strict: exit 0` from the build step.
install-launch (blocking, the released image): `tool: install-launch-check.sh 847e77db5c99 at
  _orchestra/tools/pinned/install-launch-check-847e77db5c99d5d6.sh`, `PASS: Printer Studio KH.app
  1.0.46 launched hidden and is alive after 10s (pid 51599; com.theng12.printerstudio)`. It mounts the
  DMG, copies the app out of the image and launches that copy — never a window on the owner's screen.

## Publish

publish rule: the owner's standing publish-on-green rule (2026-11-24), relayed to this session by
  Developer - Utilities in the brief that started it: a green gate plus the Developer's check
  authorises publication, without asking per release.
release: https://github.com/theng12/printer-studio-kh/releases/tag/1.0.46 — non-draft, not a
  prerelease; asset `Printer.Studio.KH-1.0.46.dmg`, GitHub digest
  sha256:364149355c853be29f9d21f83e2c18e3ca44ba7bae7a554d27b44d80bc88117c, 4,598,040 B.
tag: `1.0.46` — annotated (object c236c3253a38d5d9d5fcd2c68ce184404f636148), peels to
  6a5e76bc2677dee804b186835edc28b71a0b8b18; `git show 1.0.46:app-meta.json` names 1.0.46 and
  `localFile: Printer Studio KH-1.0.46.dmg`. Pushed before the release existed.
readback: anonymous download (curl, no token) of the release asset —
  HTTP 200, 4,598,040 B, sha256 364149355c853be29f9d21f83e2c18e3ca44ba7bae7a554d27b44d80bc88117c —
  the bytes the gate scanned; READBACK OK. `gh release view` reports draft false, prerelease false
  and the same digest.
appcast: item added on main (`003d71c`), signed over the **anonymous download above**, not the
  build-tree file, with `~/.kh-sparkle/com.theng12/printerstudio/private.key`. Verified twice, the
  producer not grading its own work:
  1. `_orchestra/tools/appcast-verify.sh` → `PASS signature verifies against this artifact`, rc=0;
  2. after Pages redeployed (`pages` run for `003d71c`: completed/success), the **served** appcast at
     https://theng12.github.io/printer-studio-kh/appcast.xml — HTTP 200, application/xml, 2,847 B,
     `<title>1.0.46</title>` present, enclosure
     `…/releases/download/1.0.46/Printer.Studio.KH-1.0.46.dmg`, length 4598040, `sparkle:version` 47 —
     and the signature in that served file verified against the downloaded artifact:
     `PASS signature verifies against this artifact`, rc=0.
feed readback: **NOT MOVED BY THIS SESSION.** At the time of writing the Pages feed
  (https://theng12.github.io/kh-releases/release.json, decoded from the signed envelope) still serves
  `printer-studio` 1.0.45 / sha `c989484b…` / 4,597,721 B, feed `published_at` 2026-11-25T14:04:33Z.
  The row is System's (S001, sole owner of the feed and the `khu` generator). The exact sha, bytes,
  tag, asset name and URL were handed to that session at 15:0xZ; it verified all of them
  independently (tag peels correctly, release non-draft, GitHub digest and anonymous curl both
  `36414935…`) and queued the row in its batch pass. This release is **published** — a GitHub
  release that anyone can download and a signed appcast that points at it — but its feed row is
  pending S001's pass, and until that pass runs the estate feed still offers 1.0.45.

## Measurement

idle footprint: ten minutes, hidden instance of this build, own data dir, one real cycle first.
  `idle footprint: pid 12508 = 71 MB after 600s, -10 MB while idle (ceiling 500 MB)` then `OK`;
  ports 1 → 1, open files 37 → 36, threads 8 → 4, RSS 81 MB at the start of the window → 71 MB at the
  end. Pass is "flat" (nothing grew) and the number is the settled one, 71 MB. SIGTERM then ended it
  in 313 ms with no crash report added. Log: `lead/1.0.46-20261125/printer-idle-1046.log`.
not exercised — recorded once, not as passed, and not a standing gap list:
  - **a physical print** — no paper was printed by this release. Nothing in the printer path changed.
  - **the login-after-restart half** — the app coming back by itself after a restart was not
    exercised; it needs a restart of this Mac on an installed copy.
  - **a real self-update** — Printer has never changed version by itself on this Mac; the update
    path is covered by `app/test-update-checker.sh` and `app/test-maintenance-hold*.sh`, not by an
    observed unattended update. 1.0.45 → 1.0.46 is the first pair where it could happen.

## Housekeeping

dist: 1.0.46 + 1.0.45 (current + previous).
retired: `Printer Studio KH-1.0.44.dmg` (sha256 bcf5c0afbd059e913cb647fb5f20f4f71be3bb31c65bdb87f9c4c285de794106,
  4,585,008 B) moved to
  `$HOME/Desktop/_trash/printer-studio-kh/2026-11-25 1.0.44 retired at 1.0.46/` with a `MANIFEST.md`,
  after checks found no mounted image, no open handle, no process using it, and no local pointer:
  the appcast's 1.0.44 item names the GitHub release, not this folder.
dirty: false — the released tree at `6a5e76bc2677dee804b186835edc28b71a0b8b18` is clean; the appcast
  item and this receipt are the two docs-only commits after it.
worktree: `_orchestra/developer-utilities/printer-studio-kh/worktrees/1.0.46`, branch
  `release/1.0.46`, pushed, fast-forwarded into `main`. Kept until this release settles.
