# Changelog

## 1.0.16 — 2026-11-12
- Background helpers now run as Printer Studio KH Helper instead of invisible shell scripts.
- Keeps the AirPrint helper running after an upgrade instead of stopping it.

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
