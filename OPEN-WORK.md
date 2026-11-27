# Open work — printer-studio-kh

What this app still owes, newest first. Open items only: shipped work lives in `CHANGELOG.md` and
`docs/receipts/<version>/RECEIPT.md`. The app's own longer list stays in `../BACKLOG.md`.

**Shipped in 1.0.49 (2026-11-27)** — receipt `docs/receipts/1.0.49/RECEIPT.md`.
The sidebar no longer jumps: measured at 860x580 and 1024x720, the busy line now replaces the status
text in the footer's always-present row and a result banner floats over the page, with
`app/test-sidebar-stable.sh` failing on any movement across every measurable row, a busy action and a
banner. A phone print that fails is now named: the Sharing page and Overview carry the print service's
own reason and offer the matching fix, and measuring the path from this Mac showed discovery, advertise
and ACL passing while the print waited because the queue was offline. Overview opens with a guided
"Start here" path, Settings points to it, and the setup steps use plainer words. The release asset now
carries its sha12 prefix (`3399ddb26e7c-Printer.Studio.KH-1.0.49.dmg`).

- [ ] **A page printed from a real iPhone** — not exercised: the phone's path was measured up to the print, and the app now names the failing step (the queue was offline), but no page was seen coming out. **Next:** with the printer online, print one page from the phone and record it.
- [ ] **A real self-update, seen happening** — `UNMEASURED`, not proven: no machine has been observed installing a new version by itself, and the update agent has logged `updates=0` on every run since the last publish. **Next:** let one version install itself on a machine that is left alone and record the before/after version readback.
- [ ] **A physical print** — not exercised: no paper has been printed from a released build by anyone on this line. **Next:** print one page through the app to a real USB printer and record what came out.
- [ ] **Login after a restart** — not exercised: the login item registers and clears, but nobody has restarted a Mac and watched the app come back by itself. **Next:** restart a Mac with the app's launch-at-login on, and record whether the menu-bar icon returns.
- [ ] **The idle footprint in the gate** — the 1.0.49 gate recorded `UNMEASURED` (no `IDLE_PID`); the build was measured separately at 81 MB after 60 s, flat, ceiling 500 MB. **Next:** set `IDLE_PID` in the next gate config so the number is on the gate's own summary.