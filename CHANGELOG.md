# Changelog

## 1.0.40 — 2026-11-22
- No change in how printing works. This release carries the app's card metadata: the Launcher now shows Printer Studio KH with its own description and Utility label instead of an unlabelled generic card.

## 1.0.39 — 2026-11-22
- "Open Printer Studio KH at login" now tells you the truth. When macOS is waiting for you to allow it in Login Items, the app says so and offers a button that opens that setting, instead of claiming it will open at login.
- The login item is registered again once after an update, so it carries the app's current signing certificate. A registration made by an older copy is never left in place. If you turned it off, it stays off — an update never switches it back on.

## 1.0.38 — 2026-11-22
- The update check now says how long ago it ran — "Checked 2 days ago" rather than "Checked just now" for ever. Before, a result from days ago still read as if it had just happened, on the screen where you decide whether to trust the version you run. The age keeps moving while the window is open.

## 1.0.37 — 2026-11-20
- A device on your Tailscale network can print a test page, or one of your saved sticker sizes, on this Mac's printer — and nothing else. Off by default: turn it on in Settings, and nothing is reachable while it is off. This is not a document catalogue; it prints only those items. Printing on your local network is unchanged.
- Each device gets its own token, shown once when you add it and never kept in readable form. A request with no token, a wrong one, or a revoked one is refused, and the refusal says which. Revoke one device, or all of them at once, and the next request is refused — no restart.
- A remote request can only name an item this app generated, by id: the test page or one of your saved label sizes. A path, link, uploaded file or document is refused by name and never printed.
- Every request is recorded in Settings — which device, what it asked for, when, and how it ended.

## 1.0.36 — 2026-11-20
- The status you see is read again when you bring the app forward. Before, printer and queue state was read once at launch and then held: a queue that stopped, or a job that arrived from a phone, stayed invisible until Refresh was pressed.

## 1.0.35 — 2026-11-19
- Printer Studio KH is now signed with the studio's new certificate. Nothing about how it works changes. The old certificate carried a personal email address inside every copy of the app, and the new one does not.

## 1.0.34 — 2026-11-18
- Printer Studio KH now trusts only the update key built into the app itself. Before, it read the key from a file in your home folder that anything running as you could rewrite, so a rewritten file plus its own update could have been accepted. If that file names a different key, the app ignores it and uses its own.
- An update signed by any other key is refused, and the message says it was not signed by Printer Studio KH's key. If the built-in key is ever missing, update checking stops and says so rather than reading one from the file.

## 1.0.33 — 2026-11-17
- Upgrading from an older install no longer turns Printer Sharing on. Before, the first launch after an upgrade could ask for an admin password and switch sharing on with no action by you.
- Escape now stops the action that is running. Before, a command could only finish or reach its own time limit.
- Every command the background helper runs has its own time limit too, so a stuck printer service can no longer leave it waiting for ever.
- The route the updater uses to pause the app before replacing it now requires the updater's own credential. A request without it is refused, so nothing else on this Mac can pause the app.

## 1.0.32 — 2026-11-17
- Reopening Printer Studio KH from its icon in Finder or Spotlight now brings the window back. Before, an app already running with its window closed answered that with nothing.
- An action cannot hang the app any more. Every command Printer Studio KH runs now has its own time limit, so a stuck printer service ends with a plain message instead of leaving every button disabled for good.
- When an action fails because the disk is full, the message now says how much room is left.

## 1.0.31 — 2026-11-15
- Printer Studio KH can now be updated while it is open without cutting off what it is doing. Before an update starts, it stops taking new actions, gives the action already running up to 20 seconds to finish, and tells the installer whether replacing it right now is safe. Nothing is cancelled.
- If an update is started and then abandoned, Printer Studio KH carries on by itself after two minutes. Quitting and reopening it always starts it working normally; there is no switch to turn back on.
- While it is paused for an update the menu bar says so, and an action you click is refused in plain words instead of doing nothing.

## 1.0.30 — 2026-11-15
- A shared USB printer is now announced to iPhone and iPad using the sharing state read from CUPS, including the Brother queue that was being skipped.
- New, off by default: Tell me when a job arrives. A chime acknowledges a new job as it reaches the Mac; it does not mean the printer has started putting ink on paper.
- The announcement can use the plain chime, built-in English, Khmer or Chinese, or your own recording of five seconds or less. Picking a voice takes effect immediately; a recording that is too long is refused on Settings with the reason.
- If the chosen recording cannot play, Activity names it and says that the plain chime was used instead.
- Settings fits narrow windows: the voice choice is a menu, and the recording buttons stack when needed so their full labels remain readable. The voice menu says why it is disabled until job alerts are on, and Remove my recording appears only when a recording exists.
- Appearance changes repaint the whole window, pages use the available width, Settings cards have headings, and What's New uses plain text without stray asterisks.

## 1.0.29 — 2026-11-15
- Settings fits in a narrow window again. The voice picker is a menu now, so the page no longer needs more width than it has.
- If a chosen announcement cannot be played, the Activity log says which one and that the plain chime was used instead, rather than going quiet while the card still says the voice is on.
- The voice picker is greyed out until job alerts are on, and the card now says that instead of leaving you to work it out.

## 1.0.28 — 2026-11-15
- Picking a language for the job announcement now actually changes what you hear. Before this, the choice was remembered but only took effect after restarting the app.
- A recording that is too long is refused on the Settings page itself, not only in the Activity log.
- The remove button for your own recording appears only when there is a recording to remove.

## 1.0.27 — 2026-11-15
- Every card on the Settings page now carries a heading, so Job alerts no longer sits untitled beside Appearance and About.
- Release notes no longer show raw asterisks where emphasis was meant. The notes are plain text, so they are written plainly.

## 1.0.26 — 2026-11-15
- The job announcement can now speak instead of chime. Settings → Announcement offers English, Khmer, Chinese, or your own recording. The three voices are built in and made with the studio's own local voice model, so an install never needs a network to hear them.
- Your own recording has to be 5 seconds or less. A longer one is refused with the reason, never silently trimmed.
- Everything about this stays off until you turn on "Tell me when a job arrives", and the plain chime remains the starting choice.

## 1.0.25 — 2026-11-15
- New, off by default: Tell me when a job arrives. Switch it on in Settings and Printer Studio KH chimes and says so the moment a job reaches the Mac — about a second after you press Print on a phone or another Mac. The printer's own warm-up still takes several seconds, so this is the acknowledgement, not the page.
- The chime only runs while the switch is on, never repeats for a job it has already announced, and stays quiet for jobs that were already queued when it started.

## 1.0.24 — 2026-11-15
- A USB printer that macOS shares as an IPP queue is now announced to iPhone and iPad instead of being skipped: sharing is read from CUPS itself, not from a queue option that does not carry it.
- Choosing Light or Dark now repaints the whole window — the page, the cards and the sidebar together — instead of leaving white cards on a dark page or dark cards on a light page.
- System still follows macOS, including when macOS changes while the app is open.
- Every page now uses the whole window: cards, the printer grid, the shared-queues table, the watcher log and the size table reach the right edge instead of stopping at a fixed column, while paragraphs keep a comfortable reading width.

## 1.0.23 — 2026-11-15
- Choosing Light or Dark now repaints the whole window — the page, the cards and the sidebar together — instead of leaving white cards on a dark page or dark cards on a light page.
- System still follows macOS, including when macOS changes while the app is open.
- Every page now uses the whole window: cards, the printer grid, the shared-queues table, the watcher log and the size table reach the right edge instead of stopping at a fixed column, while paragraphs keep a comfortable reading width.

## 1.0.22 — 2026-11-15
- Background work now runs as one helper instead of two, so Login Items shows Printer Studio KH and one Printer Studio KH Helper.
- Installing the background watcher no longer turns Printer Sharing on for you.
- Printers can be shown as cards or a table, and the app remembers which you chose.
- Each printer has one main button — Print test page — and share, pause, resume, clear jobs and access changes live in the ••• menu on that row.
- Warnings are grouped under “Needs attention” or “Suggestions” with a count, and identical log lines are shown once with ×N.
- Cards line up at the same height with labelled values, columns stay aligned, and the light and dark contrast is measured rather than guessed.
- A USB printer that macOS marks as AirPrint — such as the Brother HL-L2370DN — is now announced to iPhone and iPad instead of being skipped.
- In a large window the page title sits fully below the title bar instead of fading into it, and every page shares one column and leading edge.
- Activity now says when a refresh has finished instead of leaving “Refreshing…” behind.
- Messages use each printer's name as you see it, not its internal queue id.

## 1.0.21 — 2026-11-15
- Background work now runs as one helper instead of two, so Login Items shows Printer Studio KH and one Printer Studio KH Helper.
- Installing the background watcher no longer turns Printer Sharing on for you.
- Printers can be shown as cards or a table, and the app remembers which you chose.
- Each printer has one main button — Print test page — and share, pause, resume, clear jobs and access changes live in the ••• menu on that row.
- Warnings are grouped under “Needs attention” or “Suggestions” with a count, and identical log lines are shown once with ×N.
- Cards line up at the same height with labelled values, columns stay aligned, and the light and dark contrast is measured rather than guessed.
- A USB printer that macOS marks as AirPrint — such as the Brother HL-L2370DN — is now announced to iPhone and iPad instead of being skipped.
- In a large window the page title now sits fully below the title bar instead of fading into it, and What's New is one centred column instead of a narrow strip on the left.

## 1.0.20 — 2026-11-14
- Background work now runs as one helper instead of two, so Login Items shows Printer Studio KH and one Printer Studio KH Helper.
- Installing the background watcher no longer turns Printer Sharing on for you.
- Printers can be shown as cards or a table, and the app remembers which you chose.
- Each printer has one main button — Print test page — and share, pause, resume, clear jobs and access changes live in the ••• menu on that row.
- Warnings are grouped under “Needs attention” or “Suggestions” with a count, and identical log lines are shown once with ×N.
- Cards line up at the same height with labelled values, columns stay aligned, and the light and dark contrast is measured rather than guessed.
- A USB printer that macOS marks as AirPrint — such as the Brother HL-L2370DN — is now announced to iPhone and iPad instead of being skipped.

## 1.0.19 — 2026-11-13
- Opening the app now shows its window straight away; the menu-bar icon is still there for quick actions.
- The window can be reopened from the application menu with Command-O or from the menu-bar menu after it is closed.


## 1.0.18 — 2026-11-12
- If the app is dragged to the Trash, its background helper now notices and removes its own background job instead of leaving one pointing at a missing app.


## 1.0.17 — 2026-11-12
- The background helper now runs from inside the app, so deleting the app deletes the helper with it.
- Installing replaces any older helper copy left on the Mac instead of leaving a second one behind.
- Settings gains Remove Printer Studio KH: it stops the background jobs, removes the login item, moves the app to the Trash and keeps your settings.
- A second copy of the app now says so and steps aside instead of both running.

## 1.0.16 — 2026-11-12
- Background helpers now run as Printer Studio KH Helper instead of invisible shell scripts.
- Keeps the AirPrint helper running after an upgrade instead of stopping it.
- The bottom of the sidebar is one group now: Support this app, a version pill that opens What's New, Check for Updates, and one status line.
- Check for Updates asks the Studio KH update feed and says plainly what it found; it opens Studio Launcher to install, never installing by itself.
- Settings gains Appearance — System, Light or Dark — starting on System.
- Support this app opens a page with an optional one-time donation; nothing is required.
- The menu bar menu and the application menu both quit the app, so Activity Monitor is never needed.
- The sidebar reads as one surface from top to bottom in both light and dark.
- Same version, rebuilt with the appearance change: this installer replaces the earlier 1.0.16 build, which never shipped. Compare installers by checksum, not by version number.

## 1.0.14 — 2026-11-08
- Avoids adding a second AirPrint entry when this Mac already advertises the same queue as AirPrint.

## 1.0.13 — 2026-11-08
- Keeps a stable local signing identity across updates.

## 1.0.12 — 2026-11-08
- Gives AirPrint announcements the shared queue’s stable identity and withdraws old announcements before replacing them.

## 1.0.11 — 2026-11-06
- What's New now opens in its own window.

## 1.0.10 — 2026-11-06
- Adds a one-time setup for iPhone raster printing on the TSC TTP-244 Pro and Xprinter XP-D463B
- Passes the requested label size to the driver before rendering PDF and iPhone raster jobs
- Makes clear that iPhone output still needs a real label test

## 1.0.9 — 2026-11-06
- Restores the 1.0.4 AirPrint names and announcements for every shared printer
- Stops hiding shared printers when another Bonjour record is found
- Keeps iPhone discovery marked as not checked until tested on the phone

## 1.0.8 — 2026-11-06
- Restores the printer announcement used in 1.0.4 for iPhone printing
- Uses each printer’s own paper and two-sided printing options in its announcement

## 1.0.7 — 2026-11-06
- Shows the app version in the menu bar, just above Quit

## 1.0.6 — 2026-11-05
- Turns on Printer Sharing when you enable AirPrint, so shared printers can accept jobs from your network
- Shows when Printer Sharing is off instead of saying AirPrint is ready
- Explains a failed or cancelled sharing setup before starting AirPrint

## 1.0.5 — 2026-11-04
- Lets you save printer names for the app and AirPrint
- Shows each printer’s paper size and saves the selected size for Mac and iPhone printing
- Prints one short test page sized to the paper or label you selected
- Avoids adding another AirPrint entry when a printer is already available
- Updates AirPrint names and sizes automatically, and stops offering unsupported image formats
- Applies paper sizes without interrupting every printer on the Mac

## 1.0.4 — 2026-11-03
- Shows the version and a What’s new link at the bottom of the sidebar

## 1.0.3 — 2026-11-02
- Shows size dimensions in both millimetres and inches in the app and generated printer labels
- Adds 30 x 40, 50 x 70, 70 x 100 mm, A5 and A4 to the editable paper-size list
- Checks label sizes against each printer’s driver limits before applying them

## 1.0.2 — 2026-11-02
- Copy an error report from Settings to get help with printing, without using Terminal

## 1.0.1 — 2026-11-02
- Starts Printer Studio KH at login
- Keeps HP Laser 107a ready after restart or replug after one-time administrator approval
- No password saved
