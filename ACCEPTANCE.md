# Printer Studio KH acceptance

## Release scope: 1.0.30

The release fixes Settings announcement actions at narrow widths. It also carries the unreleased 1.0.24–1.0.29 AirPrint, job-alert and voice changes. Optional job alerts start off; the plain chime is the initial sound. Saved choices remain saved.

| User task | Check and evidence | State |
| --- | --- | --- |
| Read every custom-recording action at 375, 420, 768 and 1440 pt | `PRINTER_STUDIO_RENDER_CUSTOM_VOICE=1 bash app/render-pages.sh settings <out> <sizes>`; inspect both themes and the three reported action frames | Pending 1.0.30 render |
| Choose a custom recording before one exists | Same command with `PRINTER_STUDIO_RENDER_CUSTOM_VOICE=missing`; Choose and English actions visible, Remove absent | Pending 1.0.30 render |
| Select a voice immediately | `SettingsView` writes the shared `announcementVoice`; `test-voice-clip.sh` covers supported choices, fallback and validation; actual menu interaction is not proven by screenshots | Logic covered previously; native menu interaction not checked |
| Reject recordings longer than five seconds with a reason | `test-voice-clip.sh`; `SettingsView.fileImporter` displays the returned failure | Focused test rerun in 1.0.30 render lane |
| Hear a chime or built-in voice for a newly received print job | `test-job-watch.sh`, `test-voice-clip.sh`; three bundled WAV files; owner's earlier clip listening acceptance | Reuse unchanged prior checks; no new physical print requested |
| Print to the USB Brother over AirPrint | Existing 1.0.24 evidence: `_orchestra/printer-lead/evidence-1.0.24/FINAL-1.0.24.md`; owner confirmed an iPhone print | Prior live proof; unchanged helper source |
| Launch the signed package without touching printer services | `app/Tools/TestSigning.py` uses the signing-smoke entry, isolated launchd job and readiness receipt | Required on 1.0.30 package |
| Read What's New for the installed version | `app/Tools/test-release-notes.sh`; compare packaged notes with `app/release-notes.sh 1.0.30 CHANGELOG.md` | Required on 1.0.30 package |

The full historical task/control inventory, capability comparison and missing native/hardware checks are retained in `_orchestra/printer-lead/release-120-20261114/COMPLETENESS.md`. They are not promoted to passing by this document. Per-job cancellation, optional removal of printer queues/drivers, real login/reopen/keyboard checks and HP restart/replug proof remain in their existing work records, outside this Settings patch's verification.

## Capability cross-check

The authoritative choices are the shipped `VoiceClip.allCases`: Sound only, English, Khmer, Chinese and My own recording. Every choice is in the Settings menu. Choosing custom exposes Choose a recording and Use the English clip instead; Remove my recording appears only when a saved recording exists. This is a local capability set; no provider catalog or network generation is needed. The limit is `VoiceClip.maxCustomSeconds` and is displayed beside the recording actions.

Settings keeps System/Light/Dark appearance, job-alert enablement, the voice menu and the app's existing maintenance controls. The built-in recordings are resources, and the owner's recording is durable Application Support data. Rendering uses only temporary source copies and a separate temporary recording path.

## Standard-practice comparison

macOS sound preferences and file import panels establish the relevant conventions: an explicit off/on choice, a named sound choice, a native recording picker, a readable validation reason, and actions whose complete labels remain visible. Printer keeps its native SwiftUI controls and existing `ActionRow`, which falls back to a column when the horizontal row cannot fit. Voice recording/editing and remote voice generation are deliberately absent; the app imports a short recording and plays it.

## Evidence boundaries

Offscreen native renders prove layout and reported state, not successful opening of native menus or file panels. Signing smoke proves package startup and stable signing requirements, not physical paper output. The release receipt must name actual rendered states, reused source-bound checks, package identity and the served artifact hash. Publication is not an installed-version claim; installation belongs to the Launcher.
