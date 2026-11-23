# Release receipt — Printer Studio KH 1.0.44

app: printer-studio
version: 1.0.44
commit: 33b9d04a6db90153a2efc744e74357b126fc20d7
artifact: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/app/dist/Printer Studio KH-1.0.44.dmg
sha256: bcf5c0afbd059e913cb647fb5f20f4f71be3bb31c65bdb87f9c4c285de794106
bytes: 4589034
scan: sha256=bcf5c0afbd059e913cb647fb5f20f4f71be3bb31c65bdb87f9c4c285de794106 clean (dmg-scan step)
scanner: `_orchestra/tools/pinned/studio-gate-76dbf7aa09f5109b.sh`, sha256
  76dbf7aa09f5109bee4bb97705a0af3d1737e0b87230270c2f1bd3c779235ae9 (the first pin carrying the shim check);
  identity and tree-state lines quoted below once the run exists
shim: `vendor/khsparkle/libkhsparkle.a` asserted in its **own** step against
  `_orchestra/tools/pinned/REQUIRED-SHIM.txt` — a pinned scanner does not carry that check. Cross-checked by hand
  as well; the receipt names which line came from which.
gate config: $HOME/Developer/_orchestra/developer-utilities/printer-studio-kh/lead/1.0.44-20261123/gate.cfg
gate exit: 0 — GATE PASS printer-studio 33b9d04a6db90153a2efc744e74357b126fc20d7 2026-11-23T16:20:34Z,
  evidence lead/gate-20261123-230549-20435, 17 steps ok, idle-footprint UNMEASURED
  scanner, quoted: `tool studio-gate.sh 76dbf7aa09f5109bee4bb97705a0af3d1737e0b87230270c2f1bd3c779235ae9 at
  _orchestra/tools/pinned/<the 76dbf7aa pin>` then `scan clean export of 33b9d04a6db90153a2efc744e74357b126fc20d7`
  shim line from the pin's own check: `SHIM OK vendor/khsparkle/libkhsparkle.a matches REQUIRED-SHIM.txt`
deep verify: `codesign --verify --deep --strict` exit 0, printed by the build step
retired: Printer Studio KH-1.0.42.dmg, with a manifest in $HOME/Desktop/_trash/printer-studio-kh/
dist: 1.0.44 + 1.0.43 (1.0.42 moved to the Desktop trash with a manifest)
github release: CREATED — https://github.com/theng12/printer-studio-kh/releases/tag/1.0.44, tag **1.0.44 on the
  gated commit itself** (`33b9d04`, checked before the release existed: `git rev-parse 1.0.44^{commit}` equals the
  gated sha, and `git show 1.0.44:app-meta.json` names 1.0.44), non-draft, stored asset
  `bcf5c0afbd05-Printer.Studio.KH-1.0.44.dmg`, GitHub digest sha256:bcf5c0af…4106, 4,589,034 B
readback: anonymous download of the release asset hashed to bcf5c0afbd059e913cb647fb5f20f4f71be3bb31c65bdb87f9c4c285de794106
  at 4,589,034 bytes — the bytes the gate scanned; READBACK OK
appcast served: https://theng12.github.io/printer-studio-kh/appcast.xml — fetched from the internet in this
  session: 200, one item, `sparkle:shortVersionString` 1.0.44, served sha256
  7d32393bf3dc6ba43b554960eff1c8f2e7ce9a32bf8804c5ab41be7ce0600b2b; the served `edSignature` verified against
  the published DMG (4,589,034 B, sha bcf5c0af…) → **SIGNATURE OK**
feed readback: PENDING the next feed pass — the release is the newest published in the repo, which is what the
generator reads
page state: not written — page-sync is retired (kh-releases is feed-only, RELEASE-POLICY §2b)
dirty: false
commits: this is a single-commit release — the tag names the gated commit itself, no docs commit in front of it
tag, peeled: `refs/tags/1.0.44` is an **annotated tag object** `0fdb756d61d7` that peels to
  `refs/tags/1.0.44^{}` = `33b9d04a6db90153a2efc744e74357b126fc20d7`. Quote the peeled line, not the tag object —
  `ls-remote` prints the object, which reads exactly like a tag on a docs commit (that is what 1.0.43 did). Row
  `20261123-186`.
tag rule: before the GitHub release exists, `git/ref/tags/1.0.44` must equal the gated sha and
  `git show 1.0.44:app-meta.json` must name 1.0.44 — 1.0.43 was tagged at a later receipts commit, which is the
  mistake this rule prevents
not proven: a version changing by itself (no Printer install on this Mac, and the observation needs one);
  physical print; the login after a restart; ten-minute idle footprint

## Evidence

- `app/test-update-checker.sh`: 42 assertions pass, including the appcast cases — an appcast offering the
  installed version is up to date, an older item never offers a downgrade, the newest wins regardless of order,
  and an appcast with no version or garbage **fails** rather than reading as up to date.
- The pressable check reads `SUFeedURL` from the bundle first; the signed KH feed remains the fallback when a
  bundle carries no appcast address, with its pinned-key verification unchanged.
- **The pinned install-and-launch check did not run in this gate, by decision, not by omission:** printer's gate
  carries no such step, and the fix pin `ba11fcf8` is still in its ten runs, so it is not cleared yet. The launch proof for this
  release is `app/test-signing.sh` — it builds this commit in a temp tree and launches the packaged app hidden.
  It proves the app it builds stays alive; it does **not** mount the shipped DMG. From the first release after
  the launch-check pin is cleared, that step is added as blocking, because File 0.6.4 shipped a green gate whose
  packaged artifact died in a second.
- Shim assertion (own step): `SHIM OK vendor/khsparkle/libkhsparkle.a matches REQUIRED-SHIM.txt`.
