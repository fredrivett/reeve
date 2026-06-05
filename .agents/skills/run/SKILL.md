---
name: run
description: Build and launch reeve as a proper .app bundle for manual UI testing. Use when verifying UI changes, testing menu bar behaviour, or confirming a fix works in the running app.
compatibility: Requires macOS with Swift toolchain installed
---

# Run reeve

Always use `./run.sh` — not `swift run`. `swift run` produces a bare binary with no `.app` bundle, so macOS won't register the status item and the menu bar icon won't appear.

## Steps

1. Run `./run.sh` from the repo root
2. Click the reeve icon in the menu bar to open the panel
3. Exercise the change — expand/collapse sections, filter, check heights
4. Quit via ··· → Quit (or kill the process)

## What to look for

- Panel opens and renders PM2 processes correctly
- Panel height adjusts when expanding or collapsing environment sections and the inactive group
- No visual regressions in other sections while testing the changed area
- Filter (⌘K) still works
