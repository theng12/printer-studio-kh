---
name: Printer Studio KH
description: Native macOS app that shares a USB-only printer and keeps shared queues alive.
colors:
  accent: "#007aff"
  window: "#ececec"
  panel: "#e8e8e8"
  content: "#ffffff"
  text: "#000000"
  text-secondary: "#6e6e73"
  success: "#28a745"
  warning: "#f0a020"
  danger: "#d70015"
typography:
  footer-version:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "10px"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "11px"
    fontWeight: 400
  footer-label:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "11px"
    fontWeight: 500
  body-small:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "12px"
    fontWeight: 400
  body:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "13px"
    fontWeight: 400
  section-title:
    fontFamily: "SF Pro Display, -apple-system"
    fontSize: "14px"
    fontWeight: 600
  page-title:
    fontFamily: "SF Pro Display, -apple-system"
    fontSize: "17px"
    fontWeight: 600
rounded:
  control: "6px"
  button: "7px"
  card: "8px"
  group: "10px"
  window: "12px"
  pill: "999px"
spacing:
  tight: "4px"
  group: "6px"
  inline: "10px"
  section: "18px"
  footer-top: "9px"
  footer-bottom: "8px"
components:
  footer-pill:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text}"
    rounded: "{rounded.pill}"
    height: "26px"
    padding: "0 7px"
  footer-icon-button:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.button}"
    size: "26px"
  settings-group:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.group}"
---

# Printer Studio KH — design system

Recorded from the shipped code (SwiftUI, `app/Sources/PrinterStudio/Views.swift`)
and the portfolio shared-UI conventions. Values above in light mode; every color
except the accent is a semantic system color that follows the appearance setting.

## Overview

An Operate surface. Someone opens it to check that sharing is on, that the
printer is reachable, and to fix a queue that stopped. The window is a normal
macOS `NavigationSplitView`: a sidebar of destinations, one working area. Native
controls carry the interaction; the app's own voice is in precise, plain labels
and honest status wording.

## Colors

- **Accent** — the system accent (default blue), used only for the primary
  action, the selected sidebar row, and "good" states. Never for decoration.
- **Window / panel / content** — the system window background, the sidebar
  panel, and `controlBackgroundColor`/`textBackgroundColor` for cards and text
  fields. No custom background images or tints.
- **Text** — `.primary` and `.secondary` only; 40 uses of secondary against one
  white, so hierarchy is weight and color, not decoration.
- **State** — green for healthy, red for failure, orange for a stopped printer or
  a needs-attention state. Color never carries a state alone; each has text.

## Typography

One family: the system font (SF Pro). Scale is 10 / 11 / 12 / 13 / 14 / 17 with
weight, not size, carrying emphasis. Captions and the footer sit at 11 px; the
version inside the pill is 10 px; section titles 14 px semibold; a page title
17 px semibold (or `.title2`). No display faces, no monospace costume.

## Layout

- Sidebar 240–260 pt (ideal 248), one right border; the detail area takes the
  rest with 16–18 pt padding.
- Content groups stack with 18 pt between sections and 6–12 pt inside one.
- Footer is pinned flush to the bottom edge: heart row, then the pill and the two
  update controls on one line, then at most one 11 px status line, 9 pt above the
  rule and 8 pt below the last row. Navigation takes the remaining height.
- Settings is one scrolling column of grouped cards, this app and this Mac first,
  then Appearance, then About.

## Elevation & Depth

Flat. Grouped cards use the system `GroupBox` look; the only custom fills are
`controlBackgroundColor` cards at radius 10 and `accentColor.opacity(0.16)` for
the update-available button. No shadows, no glass, no blur.

## Shapes

Rounded rectangles: 6 for fields, 7 for the footer icon buttons, 8 for inline
cards, 10 for groups, 12 for sheets and windows, 999 for the version pill. Icons
are SF Symbols at 13–16 pt, stroke-consistent, always paired with a text label.

## Components

- **Sidebar row** — `Label` with a leading SF Symbol, 12.5–13 pt text, selected
  row tinted with the accent.
- **Footer pill** — text only, "Printer Studio KH <version>", 26 px high, opens
  What's New. No icon inside it.
- **Footer icon buttons** — 26×26, radius 7, 16 pt glyph, icon-only with a
  tooltip and an accessible name: Check for Updates, and the update button that
  appears only when a version is available.
- **Status line** — one 11 px secondary line; the app summary until a check runs,
  then the check's own answer.
- **Settings group** — rounded group with a 14 pt semibold heading and rows of
  label plus control; explanatory captions at 11 pt secondary.
- **Activity rows** — timestamped lines, secondary color, warnings and errors in
  orange and red with their reason stated.

## Do's and Don'ts

- Do keep one accent, one type family, and semantic system colors.
- Do give every icon a text label and an accessible name.
- Do state the real reason in a failure and offer the recovery.
- Don't add a gradient, glass, or decorative motion.
- Don't swap the component framework or introduce a third-party UI library.
- Don't put counts, build hashes or machine names in the footer.
- Don't show "up to date" when nothing was checked.
