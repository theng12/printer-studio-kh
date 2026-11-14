---
name: Printer Studio KH
description: Native macOS app that shares a USB-only printer and keeps shared queues alive.
colors:
  accent: "#007aff"
  page: "#ececec"
  surface: "#ffffff"
  border: "#d4d4d4"
  body: "#242424"
  muted: "#686868"
  success: "#34c759"
  warning: "#ff8d28"
  danger: "#ff383c"
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
    backgroundColor: "{colors.surface}"
    textColor: "{colors.body}"
    rounded: "{rounded.pill}"
    height: "26px"
    padding: "0 7px"
  footer-icon-button:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.button}"
    size: "26px"
  settings-group:
    backgroundColor: "{colors.surface}"
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

One neutral ramp, defined once in `app/Sources/PrinterStudio/DesignTokens.swift`
and resolved through SwiftUI semantic colours so Light and Dark follow macOS:
**page** (the window background with 9% body ink) behind every page, **surface**
(`controlBackground`) for cards and groups, **border** (`separator`) for
hairlines and quiet card outlines, **muted** (body ink at 66%) for captions and
supporting text, and **body** (`label`) for body text. The page sits 1.19:1
(Light) and 1.25:1 (Dark) from the surface, so cards read as a layer; body
measures 13.08:1 and 10.04:1, and muted 4.71:1 and 5.32:1 on the page — all at
or above the 4.5:1 floor. One **accent** is used for links, icons, primary
actions and selection. The system green/orange/red are too light for small
light-mode text (measured 2.0–3.5:1), so `DesignTokens.swift` defines explicit
light/dark pairs: **success**, **warning** and **danger** for state text on a
15% tint or on the page, **accent** for accent text, and **accentFill** for
filled primary buttons. The acceptance probe measures every pair and fails below
4.5:1 in either appearance; state never appears without a text label.

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

Flat. Grouped cards use the same `surface` fill and `border` outline as the
standalone cards; the only custom fills are `surface` cards at radius 10 and
`accentColor.opacity(0.16)` for the update-available button. No shadows, no
glass, no blur.

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

## Lists and rows (Fleet standard, 1.0.20)

- **View switch** — a list that has two useful shapes carries a Cards | Table
  segmented control in its header and remembers the choice
  (`printersListMode`); Cards is where every install starts.
- **Cards** — an adaptive grid (minimum 340 pt) with one measured minimum
  height per row, a quiet border, a state badge, and a metric grid with a fixed
  label column so values line up across cards.
- **Table** — one compact line per row: Printer (name, then location and model
  as 10–11 pt captions), State, Shared, Actions. The State column shows the badge
  once, never a badge plus plain text. Below its minimum width the rows become a
  compact list (name, state/shared, location, actions) so the primary action
  stays visible instead of scrolling off the edge.
- **One primary action per row** — Print test page on a printer, Open to
  everyone on a blocked queue. Share/Stop sharing, Pause/Resume, Rename…, Paper
  size and Clear jobs live in a labelled ⋯ menu on that row. Rename is an in-app
  sheet, never a native prompt; cards keep their inline name field.
- **Action rows** — buttons sit in one row with a uniform 10 pt gap; when the row
  does not fit it becomes a stacked column (`ActionRow`), so the height reserved
  is the height drawn and the next card never covers a control.
- **Action results** — the last action's success or failure appears as a banner
  at the top of the page where it happened, with its message and a dismiss
  control; the Activity page keeps the history.
- **Warnings** — grouped under "Needs attention (n)" and "Suggestions (n)";
  identical lines collapse into one row with ×n.
- **Deduped rows** — consecutive identical Activity entries and identical USB
  devices collapse into one row with ×n.
- **Job rows** — "N jobs on <printer> — users · size" with one Clear jobs action;
  the raw lpstat line stays in the log, not in the UI.
- **Metric lines** — label in muted, value in body, one value per line; the
  label column never reflows per row.
- **Failures** — a page that cannot read its source shows a named error and a
  Retry, never an empty state that reads as "nothing here".

## Do's and Don'ts

- Do keep one accent, one type family, and semantic system colors.
- Do give every icon a text label and an accessible name.
- Do state the real reason in a failure and offer the recovery.
- Don't add a gradient, glass, or decorative motion.
- Don't swap the component framework or introduce a third-party UI library.
- Don't put counts, build hashes or machine names in the footer.
- Don't show "up to date" when nothing was checked.
