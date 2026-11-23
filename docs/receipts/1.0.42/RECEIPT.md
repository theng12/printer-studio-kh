# Release receipt — Printer Studio KH 1.0.42

app: printer-studio
version: 1.0.42
commit: 0c3d5b11eec84e30c9391eeff8863f2f24c524fc
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.42.dmg
sha256: 61e2ea3bf6058d45f715b2c70d94a273b859643c6db3546f57f6a90069397a7e
bytes: 4585019
scan: sha256=e159b0526e811c5211f7cf446106ff3268613b124a1cef9358c0f2340bc8979c clean (dmg-scan step, 110 files)
gate config: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/1.0.42-20261123/gate.cfg
gate exit: 0 — GATE PASS printer-studio 0c3d5b11eec84e30c9391eeff8863f2f24c524fc 2026-11-23T14:07:22Z
  (evidence lead/gate-20261123-205059-23056); 15 steps ok, idle-footprint UNMEASURED
deep verify: `codesign --verify --deep --strict` exit 0, printed by the build step
retired: Printer Studio KH-1.0.40.dmg and the two superseded pre-gate 1.0.42 builds, each with a manifest
  in ~/Desktop/_trash/printer-studio-kh/
dist: 1.0.42 + 1.0.41 (1.0.40 moved to the Desktop trash with a manifest)
github release: CREATED — https://github.com/theng12/printer-studio-kh/releases/tag/1.0.42, tag at 0c3d5b1,
  published non-draft, stored asset 61e2ea3bf605-Printer.Studio.KH-1.0.42.dmg, GitHub digest
  sha256:61e2ea3b…97a7e, 4,585,019 B
readback: anonymous download of the release asset hashed to 61e2ea3bf6058d45f715b2c70d94a273b859643c6db3546f57f6a90069397a7e
  at 4,585,019 bytes — the same bytes the gate scanned; READBACK OK
feed readback: SERVED — decoded the signed feed myself (feed is base64 in
  https://theng12.github.io/kh-releases/release.json): printer-studio 1.0.42, sha256 61e2ea3b…97a7e,
  4,585,019 B, type utility, tagline present, url the 1.0.42 GitHub asset, holdURL 127.0.0.1:8642,
  holdSince 1.0.31, file 61e2ea3bf605-Printer.Studio.KH-1.0.42.dmg. The card's words came from this tag's
  `app-meta.json` — the first row to use that path. For 1.0.43, add `localFile` there so the row keeps the
  packaging's spaced name instead of GitHub's dotted one.
feed/appcast agreement: printer-studio-kh  appcast 200 → 1.0.42   feed row 1.0.42   ✓ agree — measured by this
  session 2026-11-23T15:20:47Z (feed `published_at` 15:07:48Z per U001); for most of tonight they did not,
  and that is exactly the mismatch a user cannot diagnose, so the measurement time is part of the claim.
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
self-update: **feed live and verified; the update path is BLOCKED by the vendored shim** — not self-updating.
  The served item and its signature are real (URL `https://theng12.github.io/printer-studio-kh/appcast.xml`,
  GET 200, 1,229 B, served sha 3a8ab10b…, one item 1.0.42, enclosure 200 at 4,585,019 B sha 61e2ea3b…,
  `SIGNATURE OK` against the shipped public key), but the shim this build vendored is
  `62ca9510…` and it does not expand `~`: `KHHoldTokenFile` is `~/Library/Application Support/PrinterStudio/hold-token`,
  so the first real update opens a literal `~` path, fails with "hold token file missing or unreadable", and
  refuses before Sparkle is ever asked. Checked here, not taken on report: the vendored archive has no
  `expand_tilde`/`getpwuid`, while the shim source at `khsparkle.m:182-194` on the fixed build does, and that
  fixed archive's sha is 818826a7… . An absolute path in the plist is not the fix — it puts the owner's home in
  a public artifact and the public scan refuses owner paths. **The next release vendors the fixed shim and
  re-runs the three hold configurations before claiming the loop works.**
  The shim also checks once per launch (`khsparkle.m:345`), so the update will land on a start, not while the
  app runs.
not proven: a version changing by itself on the Mac; physical print; the login after a restart; ten-minute
  idle footprint

## Evidence

- `app/test-signing.sh` builds this commit in a temp tree and launches the packaged app hidden through its
  own launchd job: PASS, so the embedded Sparkle loads under hardened runtime (a missing entitlement fails
  in dyld before `main`).
- `codesign --verify --deep --strict` exit 0 after the app seal, with Sparkle signed inside-out first.
- The shim's own harness (17 assertions, exit 0) covers hold-before-fetch, no UI, states and abort.
- Scanner, quoted from the gate's own output: `tool studio-gate.sh
  727408ba92f532581ac21938b1f8a88fa1a4992d6a8e100d1583e7a767e91028 at
  $HOME/Developer/_orchestra/tools/studio-gate.sh`, then `scan clean export of
  0c3d5b11eec84e30c9391eeff8863f2f24c524fc` — it judged a clean export of the gated HEAD, not the working
  tree. That sha **is** the frozen pin `_orchestra/tools/pinned/studio-gate-727408ba92f53258.sh` (byte-identical,
  `cmp` clean), so this verdict is about the pinned tool even though the step named the canonical path; the gate
  config now names the pin for any later run. The check 5 fix is present in it, because the step passes.
- Appcast: item signed from the published DMG with Printer's private key and verified against the plist's
  public key (`SIGNATURE OK`, exit 0). Publication was refused in this session (a live update feed needs the
  owner's own words, which landed in another session); U001 published it from there as `appcast.xml` at the
  repo root, commit `dafe2b0`.
- **Blockers found while publishing — three, and none of them a path:**
  1. the repo had **no Pages site at all** — committing into `docs/` would have produced nothing to serve;
  2. once enabled, the **legacy branch builder produced zero builds** (`pages/builds` stayed empty, nothing
     served at the root or the appcast path) — a publisher fault, not a path fault;
  3. **GitHub Actions was disabled on the repo** (`actions/permissions` → `enabled: false`), so a workflow
     could not run either.
  Fix in place: `.github/workflows/pages.yml` (`c24e55a`) deploys **only `appcast.xml`** through the Pages
  artifact API, Actions enabled, `build_type` `workflow`, source `main:/`. The URL is unchanged —
  `https://theng12.github.io/printer-studio-kh/appcast.xml`, which is what the shipped bundle bakes in — and
  the repository's tree is **not** published as a website, which a root branch build would have done.
  These are settings changes on a public repo, made to serve the feed the owner asked to publish; the
  alternative was re-building an already-released app. **If the workflow ever fails, the run log is the
  evidence — do not "fix" it by reverting to a branch build that produced nothing for an hour.**
- **`main:/docs` would also have served a path the shipped bundle never reads.** A shipped feed URL is the
  constraint: a later session that "normalises" this repo to `docs/` breaks a released app.
- State until the served item is fetched and verified: **not yet self-updating**. A feed nobody fetched is a
  file, not a feed.
- `app-meta.json` at the repo root of this commit carries the five card fields in the owner-approved words
  (same text as 1.0.40), so this release states its own card instead of inheriting it.
- `app-meta.json` (corrected by U001 after Bug Fix read `words()` in FeedGenerator.swift): **no tag file is
  required** — each field falls back tag → registry → the words the served feed already carries, and the
  refusal fires only when no source supplies it. A tag file is how the words are *changed*, and it counts
  only inside the commit the tag names; if one is added, its registry entry is deleted in the same commit.
  Printer's file at `0c3d5b1` stays on purpose: it pins this card to this release rather than inheriting.
- The generator reads `releases/latest` and takes the DMG by `.dmg` suffix: a draft contributes no row, and the
  release must be the newest in the repo. The pass refuses, naming repo and field, only when no source at all
  supplies a card word.
- Release body left as the 1.0.42 changelog text, **deliberately**: the body feeds the card's `notes`, so gate
  and scanner evidence stays in this receipt rather than on the owner's Launcher card. Printer's gate runs no
  `install-launch-check`; its launch proof is `app/test-signing.sh`, quoted above.
- Private EdDSA key at `~/.kh-sparkle/com.theng12.printerstudio/private.key` (0600), never in the tree;
  only the public half is in `Info.plist`.
