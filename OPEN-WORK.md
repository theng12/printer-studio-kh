# Open work — printer-studio-kh

What this app still owes, newest first. Open items only: shipped work lives in `CHANGELOG.md` and
`docs/receipts/<version>/RECEIPT.md`. The app's own longer list stays in `../BACKLOG.md`.

- [ ] **The release asset keeps its sha12 prefix** — `gh release create` has been called directly, so GitHub stores `Printer.Studio.KH-<version>.dmg` instead of the `<sha12>-` prefixed name `packaging/github-asset.sh` produces; `release-asset-name-check.sh` inside `release-preflight.sh` flagged it for both 1.0.47 and 1.0.48. **Next:** publish 1.0.49 through `packaging/github-asset.sh`. Never rename an asset already published — the served bytes are the artifact.
- [ ] **A real self-update, seen happening** — `UNMEASURED`, not proven: the four installer drives were refreshed and read back, but no machine has been observed installing a new version by itself, and the update agent has logged `updates=0` on every run since the publish. **Next:** let one version install itself on a machine that is left alone and record the before/after version readback.
- [ ] **A physical print** — not exercised: no paper has been printed from a released build by anyone on this line. **Next:** print one page through the app to a real USB printer and record what came out.
- [ ] **Login after a restart** — not exercised: the login item registers and clears, but nobody has restarted a Mac and watched the app come back by itself. **Next:** restart a Mac with the app's launch-at-login on, and record whether the menu-bar icon returns.
- [ ] **The idle footprint number** — `idle-footprint: UNMEASURED — no IDLE_PID in the gate config`, so the release has no measured idle memory figure. **Next:** set `IDLE_PID` in the next gate config and quote the measured number on that receipt.
