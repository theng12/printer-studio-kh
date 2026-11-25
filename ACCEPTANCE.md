# Printer Studio KH acceptance

## Release scope: 1.0.46

The packaging path finds its tools in any shell. No screen, no behaviour and no bundled file
changed.

| User task | Check and evidence | State |
| --- | --- | --- |
| The build finds the tools it needs when no Terminal logged in | `app/Tools/test-toolchain.sh` sources `app/toolchain.sh` under a non-login PATH (`/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`) and requires a `python3` that is not the 3.9 stub plus a resolvable `pkg-config`; a second source adds no PATH entry | Required on 1.0.46 |
| A missing tool reads as itself, not as a traceback | Same suite — `toolchain_require_python 99.0` exits non-zero and its message names the version it needs and the PATH it searched, with no `Traceback` in the output | Required on 1.0.46 |
| No packaging script silently resolves an unpinned `python3` | Same suite scans `app/build.sh`, `app/render-pages.sh`, `app/finalize-dist.sh`, `app/retain-dmgs.sh`, `app/release-notes.sh`, `app/signing.sh`: every one that calls a bare `python3` also sources the pin | Required on 1.0.46 |
| The build says what it ran with | `app/build.sh` prints `==> Toolchain: Python 3.x.y …; pkg-config …; swiftc …` before compiling | Required on 1.0.46 |

## Release scope: 1.0.45

One destructive path is closed, the shipped installer is now checked before a release is called
green, and the app's idle behaviour is measured rather than assumed. No screen layout changed.

| User task | Check and evidence | State |
| --- | --- | --- |
| Taking the app off this Mac cannot happen without the confirmation | `app/test-removal-guard.sh` runs the decision (no confirmation, stale, and future-dated are all refused; a fresh one inside the window permits) and reads the wiring (the command path asks `RemovalGuard.permits`, the refusal reaches the person, the token is consumed by the attempt, and the Settings dialog is the only issuer). A second entry point into `removeEverything()` fails the source half | Required on 1.0.45; the guard is proven by the harness, the click behind it is not photographed |
| The app the installer ships actually starts | The pinned `install-launch-check-847e77db5c99d5d6.sh` mounts `dist/Printer Studio KH-1.0.45.dmg`, copies the `.app` out of the image, launches it hidden with its own data dir, and requires a live pid, the version read back from the installed copy, and no new crash report. It is a blocking gate step and consumes the released image, never the build tree | Required on 1.0.45 |
| The app is quiet when nobody is using it | The shipped 1.0.45 app, launched hidden through its own launchd job on the signing-smoke entry (no window, no login item, no printer service, its own data dir), idles ten minutes: `check-idle-footprint.sh <pid> 500 600` for the footprint, and ports, open files and threads sampled at both ends to prove they are flat. SIGTERM then ends it in 169 ms, with no crash report | Required on 1.0.45; a hidden run starts no job watcher, so this is the app's floor, not a full session — numbers in the receipt, measurement in `lead/1.0.45-20261123/` |
| The store page shows what the app looks like | `check-app-screenshots.sh` — four images in `docs/screenshots/`, each ≤400 KB, named `<screen>-<light\|dark>.png`, referenced from `README.md`, and clean in their own metadata and visible text. Rendered offscreen from the shipping build with invented printers | Required on 1.0.45 |
| The updater library is the current pinned build | `vendor/khsparkle/libkhsparkle.a` is `2bce760e…`, the first entry in `_orchestra/tools/pinned/REQUIRED-SHIM.txt`; its headers and exported symbols are unchanged from the previous library, so this is the same source rebuilt reproducibly | Required on 1.0.45 |
| A physical print, a login after a restart | **NOT CHECKED** — no paper was printed by this release and no restart was made on an installed copy. Neither is in this release's scope | Not checked |

## Release scope: 1.0.44

The pressable update check reports the feed the updater actually uses.

| User task | Check and evidence | State |
| --- | --- | --- |
| A failed check never reads as "up to date" | `app/test-update-checker.sh` — an appcast with no version, and garbage, both produce a failure with a reason; `appcastState` has no path that reports up to date without a parsed version | Required on 1.0.44 |
| The version named is one the app will install, and the sentence says so | The appcast item produces `.offered`, worded "X is offered; it installs the next time the app starts" — never "X is available", because Sparkle may still decline on system version; an older item never offers a downgrade | Required on 1.0.44; the rendered sentence is asserted from source, not photographed |
| The press is visible and ends | `check()` sets `.checking`, uses a 15 s request / 20 s resource bound, and every exit sets a terminal state; the button is disabled while checking; the footer shows the state and its age | Required on 1.0.44 |
| The app's own feed is what is asked | `SUFeedURL` from the bundle is read first (`UpdateChecker.check`); the signed KH feed is only a fallback when no appcast address exists | Required on 1.0.44 |

## Release scope: 1.0.43

Fixes the vendored updater so the update path can actually run.

| User task | Check and evidence | State |
| --- | --- | --- |
| The app finds its own key file when the path starts with `~` | Vendored shim is `818826a7…` (System's fixed build, `khsparkle.m:182` `expand_tilde()` via `getpwuid`); the shim's own harness case `token-home` runs with `HOME=$RUN/home` and passes only if the user record, not `$HOME`, resolved the path | Required on 1.0.43; the harness result is quoted in the receipt |
| 1.0.42 keeps working and installing | Nothing about printing, the hold route or the bundle layout changed; version and build only | Required on 1.0.43 |
| A version actually replacing itself | **NOT CHECKED** — the loop needs an install of 1.0.43 and a later published version; 1.0.42 cannot update itself and will not be patched retroactively | Not checked |

## Release scope: 1.0.42

Printer Studio KH can update itself, through Sparkle behind the studio's shim. No screen changes.

| User task | Check and evidence | State |
| --- | --- | --- |
| An update never interrupts work: the app is asked to pause before anything is fetched | The shim's own harness proves hold-before-fetch order and refuses on any status other than `200 {"safe":true}` (401, 405, 500, timeout); Printer's `app/test-maintenance-hold.sh` proves the route answers that shape and reports `in_flight` | Shim harness (17 assertions, exit 0) + hold suite; not re-run inside Printer's gate |
| An update never puts anything on screen | The shim answers every Sparkle prompt with a custom `SPUUserDriver` that draws nothing; a path that cannot run silently is dismissed | Shim harness |
| A refused or failed update says why, once, in the log, and work carries on | `SparkleUpdate.start` logs the rc and `kh_sparkle_last_error()` and leaves the app running; states 0 idle / 1 updating / 2 relaunching are logged | Required on 1.0.42; the log line is asserted from source, not photographed |
| The app still starts with Sparkle embedded | `app/test-signing.sh` builds from the committed tree and launches it hidden through its own launchd job; a missing entitlement fails in dyld *before* `main`, so a live process is the proof | Required on 1.0.42 |
| The seal holds with hardened runtime and the framework inside | `app/build.sh` signs Sparkle inside-out, then the app with `--options runtime --entitlements`; `codesign --verify --deep --strict` prints its exit and stops the build on failure | Required on 1.0.42 |
| The bundle carries its own feed address, public key and hold route | Four keys in `app/Resources/Info.plist`; the private key stays at `~/.kh-sparkle/com.theng12.printerstudio/private.key` (0600) and is never in the tree | Required on 1.0.42 |
| A new version actually replacing this one by itself | **NOT CHECKED** — the appcast is not published yet and no 1.0.43 exists to install. This is the release that makes self-update possible, not the proof that it ran | Not checked |

## Release scope: 1.0.41

The update-hold key is the app's own, moved once, and an unsafe one is refused by name.

| User task | Check and evidence | State |
| --- | --- | --- |
| The hold reads the app's own key, and an existing one moves across once | `app/test-maintenance-hold.sh` — the copy keeps the bytes, lands at 0600, writes the `.hold-token-migrated` marker, a later legacy write cannot overwrite the app's own file, and no legacy file means no copy and no marker; the migration logs one line naming both paths | Required on 1.0.41 |
| An unsafe key file is refused, and the refusal says which fault it is | Same suite — missing file named as "the token file is missing", mode 0644 names the mode it found and "it must be 600", 63 and 65 characters, non-hex, a symlink, a directory, over 512 bytes and an empty file each refused with their own words | Required on 1.0.41 |
| The right key still works on POST and DELETE, a wrong one does not | Same suite — no token, a wrong token and a refused DELETE answer 401 and pause or release nothing; the right token answers 200 on POST and on DELETE; `app/test-maintenance-hold-live.sh` repeats it with a 64-hex key against the signed package, including a restart | Required on 1.0.41 |
| `PRINTER_STUDIO_HOLD_TOKEN_FILE` still overrides the path | The live suite points the packaged app at its own temp key through that variable and both requests succeed | Required on 1.0.41 |
| A physical print, the login after a restart, and a ten-minute idle footprint | **NOT CHECKED** — no printer paper was printed by a test, no restart was made on an installed copy, and the footprint was not measured over ten idle minutes | Not checked |

## Release scope: 1.0.40

Card metadata only; printing code is unchanged from 1.0.39.

| User task | Check and evidence | State |
| --- | --- | --- |
| The Launcher card names the app's description and Utility type | Feed readback after publish: `type` `utility` and the owner-approved description present on the `printer-studio` 1.0.40 row; both carried by hand with `--type`/`--description` because 0.1.80's guard is new | Required on 1.0.40 |
| The shared page-sync refuses a missing current publisher | `app/packaging/page-sync.sh` — the mirror step exits 3 naming the missing `base/current` instead of falling back to `bin/khu`; committed with this release | Shipped in 1.0.40; the script was retired 2026-11-23 with §0 superseded (kh-releases is feed-only, §2b) |

## Release scope: 1.0.39

The login item tells the truth about its state and is re-registered under the current identity.

| User task | Check and evidence | State |
| --- | --- | --- |
| See why "Open at login" is not working, and the one action that fixes it | `app/test-login-item.sh` — every registration state has its own sentence; the waiting-for-approval state never reads as success, names System Settings > Login Items, and Settings shows an **Open Login Items** button when it applies | Required on 1.0.39 |
| An updated app is registered under its current signing certificate, once | `app/test-login-item.sh` — `registrationAction` across four launches: first enable marks the build, the next launch is `.none`, a version change is one `.reRegister` and the marker moves, then `.none` again; the marker is written only when the item lands enabled | Required on 1.0.39 |
| Turning it off stays off, even across an update | Same suite — a stored `off` yields `.none` with no call for every marker and state; an old `configured`-but-off install migrates to `off`; an untended first run stays `unset` | Required on 1.0.39 |
| The real login after a restart | **NOT CHECKED** — needs one restart on a Mac where the app is installed and set to open at login; owner only, per `lead/1.0.39-20261122/LOGIN-ITEM-PROCEDURE.md` step 6 | Not checked |

## Release scope: 1.0.38

The update check shows the age of its last result instead of "just now" for ever.

| User task | Check and evidence | State |
| --- | --- | --- |
| See how old the last update check is, moving while the window is open | `app/test-update-checker.sh` — `checkedAge` returns "just now" at 0 s, "1 hr 30 min ago" at 90 min and "1 day ago" at 1 day; the footer re-renders every minute (`TimelineView` in `Views.swift`) | Required on 1.0.38; the rendered footer is not photographed |

## Release scope: 1.0.37

Printing from another device over Tailscale, behind four controls. Off by default.

| User task | Check and evidence | State |
| --- | --- | --- |
| Nothing is reachable while the feature is off | `app/test-remote-print.sh` — `feature_off` 403 before any token is looked at; nothing answers on this Mac's tailnet address (`nc`); the server still binds 127.0.0.1 only; local printing untouched | Required on 1.0.37 |
| A missing, wrong or revoked token is refused, and the answer says which | Same suite — `missing_token` 401, `wrong_token` 401, `revoked_token` 401 | Required on 1.0.37 |
| A request for a path, URL, uploaded file or document is refused by name and never printed | Same suite — `content_not_allowed` 403 for `path`, `url`, `file`, `document`; an unknown id is `unknown_content` 404 | Required on 1.0.37 |
| The kill switch stops the very next request | Same suite — `revokeAll` then the next request is `revoked_token`, and minting afterwards still works | Required on 1.0.37 |
| Turning the switch off also removes the tailnet mapping | Same suite — after the switch goes off, `tailscale serve status` no longer names port 8642, read back from Tailscale itself rather than the app's own line; if Tailscale cannot apply serve on this machine the suite prints SKIP with its reason | Required on 1.0.37 |
| A token is stored only as a hash, in a 0600 file | Same suite — the raw token is absent from the store; the file mode is checked | Required on 1.0.37 |
| A valid token prints an item the app generated | **NOT CHECKED as a print** — a physical print on the owner's printer is not run as a test. The composed page, the id list (test page + saved sizes) and the fail-closed `no_printer` path are what the suite proves; the `sent` branch and the printer receiving paper are unproven | Not checked |
| Idle with the feature on stays flat | No timer is added; the socket is passive and the serve mapping is static. **A ten-minute footprint measurement was not run** | Partly checked |

## Release scope: 1.0.36

The status shown is read again when the app is brought forward, instead of being held from launch.

| User task | Check and evidence | State |
| --- | --- | --- |
| See a queue that stopped, or a job that arrived, without pressing Refresh | `app/test-live-status.sh` — the shipped activation hook fires when the app becomes active and on nothing else; the app, the window and the menu bar are wired to it; an offscreen render keeps its fixtures; no timer drives it, so nothing polls while the app is idle | Required on 1.0.36; the click itself is not shown on a desktop |

## Release scope: 1.0.34

The update key can no longer be replaced by anything running as the logged-in user.

| User task | Check and evidence | State |
| --- | --- | --- |
| An update signed by anyone else is refused | `app/test-update-checker.sh` — a feed signed by a different key is refused with "not signed by this app's key" even when `publisher.json` names that key and its URL; a feed signed by the pinned key is accepted; the shipped `PublisherKey.txt` equals the fleet key; the built app carries it unchanged | Required on 1.0.34 |
| Checking still works when the app is connected normally | Same suite — the file still supplies the feed address, and a pinned-key-signed feed is offered | Required on 1.0.34; no live feed was checked against the real Update Studio |

## Release scope: 1.0.33

Every remaining issue from the 1.0.32 sweep. No screen layout changed; one control was added.

| User task | Check and evidence | State |
| --- | --- | --- |
| Stop an action that is running | `app/test-shell-ceiling.sh` — Escape cancels through the action's own scope, the inner command ends with its own status and says it was cancelled, never "took too long"; a cancel with nothing running is refused in plain words; the button's shortcut and busy-only visibility are asserted from source | Required on 1.0.33; the key press is asserted from source, not pressed |
| Upgrade without Printer Sharing switching itself on | `app/test-airprint-installer.sh` — the migration body is driven with an injected sharing step and proves it is never the `cupsctl` default; a source check fails if `ShareFix.swift` references that default again | Required on 1.0.33 |
| Nothing the helper runs can wait for ever | `app/test-helper-ceiling.sh` — a stuck command ends at its own ceiling with a plain reason, and a large stderr cannot deadlock it | Required on 1.0.33 |
| Only the updater can pause the app | `app/test-maintenance-hold.sh` (no token → 401, wrong token → 401, right token → 200, missing file → 401) and `app/test-maintenance-hold-live.sh` against the signed package | Required on 1.0.33 |

## Release scope: 1.0.32

A stability pass on the paths that can leave the app unusable. No screen or feature changed.

| User task | Check and evidence | State |
| --- | --- | --- |
| An action always ends, and says why | `app/test-shell-ceiling.sh` — a stuck command ends with a named reason inside its ceiling, both output pipes are read without deadlock, a missing tool is named | Required on 1.0.32 |
| Reopening from the app icon shows the window | `app/test-reopen.sh` — a probe app built from the real delegate, launched hidden, records the reopen Apple Event arriving, and the wiring that then opens the main window is asserted from source | Required on 1.0.32; mechanism measured, window not shown and no real Finder click (no-desktop rule) |
| A full disk fails with the number | `app/test-disk-space.sh` — a real nearly-full volume refuses a write and the message names the free space | Required on 1.0.32 |
| The 1.0.31 update hold still behaves | `app/test-maintenance-hold.sh`, unchanged | Required on 1.0.32 |

## Release scope: 1.0.31

The release makes Printer Studio KH update-safe: an update can replace it while it is open without
cutting off work. It also carries the 1.0.24–1.0.30 AirPrint, job-alert and Settings changes
unchanged. Optional job alerts start off; the plain chime is the initial sound. Saved choices
remain saved.

| User task | Check and evidence | State |
| --- | --- | --- |
| Update the app while it is open without losing what it was doing | `app/test-maintenance-hold.sh` — the pause refuses new actions, the real in-flight count is reported, and the settle is bounded at the contract's 20 s / 30 s | Required on 1.0.31 |
| See why a clicked action did nothing while the app is paused | `app/test-maintenance-hold.sh` exercises the same gate `AppState.perform` calls, and the runner fails if an action path loses it | Required on 1.0.31; the click itself is not shown on a desktop |
| Stop saying "paused" when an abandoned hold expires | The hold reports itself when the pause ends, clearing the menu-bar notice and logging that it is working again | Required on 1.0.31; the menu bar is not photographed |
| Resume at once when the installer says so | `app/test-maintenance-hold.sh` — DELETE clears the pause and work starts again | Required on 1.0.31 |
| Carry on by itself when an update is abandoned | The same suite — a pause with no DELETE expires after `pause_s` | Required on 1.0.31 |
| Quit and reopen: the app works normally with no switch to turn back on | The same suite — a fresh instance is open, and the pause is never written to disk | Required on 1.0.31 |
| The packaged app really serves the hold | `app/test-maintenance-hold-live.sh` — real POST/DELETE over loopback against the signed app, only this Mac can reach it, and a restart serves it again | Required on 1.0.31 package |
| Read every custom-recording action at 375, 420, 768 and 1440 pt | `PRINTER_STUDIO_RENDER_CUSTOM_VOICE=1 bash app/render-pages.sh settings <out> <sizes>`; inspect both themes and the three reported action frames | Prior 1.0.30 evidence; Settings source unchanged |
| Choose a custom recording before one exists | Same command with `PRINTER_STUDIO_RENDER_CUSTOM_VOICE=missing`; Choose and English actions visible, Remove absent | Prior 1.0.30 evidence; Settings source unchanged |
| Select a voice immediately | `SettingsView` writes the shared `announcementVoice`; `test-voice-clip.sh` covers supported choices, fallback and validation; actual menu interaction is not proven by screenshots | Logic covered previously; native menu interaction not checked |
| Reject recordings longer than five seconds with a reason | `test-voice-clip.sh`; `SettingsView.fileImporter` displays the returned failure | Prior 1.0.30 evidence; Settings source unchanged |
| Hear a chime or built-in voice for a newly received print job | `test-job-watch.sh`, `test-voice-clip.sh`; three bundled WAV files; owner's earlier clip listening acceptance | Reuse unchanged prior checks; no new physical print requested |
| Print to the USB Brother over AirPrint | Existing 1.0.24 evidence: `_orchestra/printer-lead/evidence-1.0.24/FINAL-1.0.24.md`; owner confirmed an iPhone print | Prior live proof; unchanged helper source |
| Launch the signed package without touching printer services | `app/Tools/TestSigning.py` uses the signing-smoke entry, isolated launchd job and readiness receipt | Required on 1.0.31 package |
| Read What's New for the installed version | `app/Tools/test-release-notes.sh`; compare packaged notes with `app/release-notes.sh 1.0.31 CHANGELOG.md` | Required on 1.0.31 package |

The full historical task/control inventory, capability comparison and missing native/hardware checks are retained in `_orchestra/printer-lead/release-120-20261114/COMPLETENESS.md`. They are not promoted to passing by this document. Per-job cancellation, optional removal of printer queues/drivers, real login/reopen/keyboard checks and HP restart/replug proof remain in their existing work records, outside this Settings patch's verification.

## Capability cross-check

The authoritative choices are the shipped `VoiceClip.allCases`: Sound only, English, Khmer, Chinese and My own recording. Every choice is in the Settings menu. Choosing custom exposes Choose a recording and Use the English clip instead; Remove my recording appears only when a saved recording exists. This is a local capability set; no provider catalog or network generation is needed. The limit is `VoiceClip.maxCustomSeconds` and is displayed beside the recording actions.

Settings keeps System/Light/Dark appearance, job-alert enablement, the voice menu and the app's existing maintenance controls. The built-in recordings are resources, and the owner's recording is durable Application Support data. Rendering uses only temporary source copies and a separate temporary recording path.

## Standard-practice comparison

macOS sound preferences and file import panels establish the relevant conventions: an explicit off/on choice, a named sound choice, a native recording picker, a readable validation reason, and actions whose complete labels remain visible. Printer keeps its native SwiftUI controls and existing `ActionRow`, which falls back to a column when the horizontal row cannot fit. Voice recording/editing and remote voice generation are deliberately absent; the app imports a short recording and plays it.

## Evidence boundaries

Offscreen native renders prove layout and reported state, not successful opening of native menus or file panels. Signing smoke proves package startup and stable signing requirements, not physical paper output. The update hold is proven by the focused suite and by real HTTP against the signed package; a person clicking an action while it is paused is shown as a plain message in code and text, not photographed on a desktop. The release receipt must name actual rendered states, reused source-bound checks, package identity and the served artifact hash. Publication is not an installed-version claim; installation belongs to the Launcher.
