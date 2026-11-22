# Printer Studio KH acceptance

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
