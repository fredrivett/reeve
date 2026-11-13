# reeve — agent guidelines

Always lowercase "reeve" — in UI text, bundle names, documentation, and code comments.

## Commands

```bash
swift build          # compile
swift test           # run tests
./run.sh             # build + launch as .app (required for UI testing — see /run skill)
./release.sh         # tag and push a new release (see /release skill)
```

## In Amp orbs

Orbs run Linux, so `.agents/setup` only installs SwiftLint: run `swiftlint --strict` in the orb. Build, test and run reeve on a Mac satellite (the project uses the `macos-26` image).

- **Tests:** the mirrored repo on the Mac has no `.git`, so the `GitInfo` test fails. Run `git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && swift test; rm -rf .git`.
- **Launching:** `mac_shell` runs outside the GUI session, so `./run.sh` builds the app but its `open` silently starts nothing. Build with `./run.sh`, then launch with `sudo -n launchctl asuser $(id -u) open .build/Reeve.app --args --demo`.
- **Data:** `--demo` drives the whole UI from synthetic environments, no PM2 needed.
- **Screenshots:** `screencapture` fails ("could not create image from display"). Use the Mac tab, or render the panel from inside the app with `NSView.cacheDisplay(in:to:)`.

## Project structure

```
Sources/
├── ReeveApp/      # app entry point, menu bar setup
└── Reeve/         # main library (imported as ReeveLib in tests)
    ├── Models/    # PM2Process, PM2Environment, AppConfig
    ├── Services/  # PM2Service, ConfigService, NotificationService
    └── Views/     # SwiftUI views
Tests/
└── reeveTests/    # unit tests (models, utilities — no UI tests)
```

## Git workflow

Branch from `main`. PRs target `main`. Commit messages are imperative, sentence-case.

## Boundaries

**Always:** run `swift build` after editing Swift files to catch compile errors early.  
**Ask first:** changes to `Package.swift` or `.github/workflows/`.  
**Never:** force-push `main`; use `swift run` to launch the app (use `./run.sh` instead).

## Known platform quirks

### macOS 26 MenuBarExtra: window doesn't shrink with its content

`MenuBarExtra` resizes its `.window` when SwiftUI reports a new root size, but sometimes misses a shrink. Its only fallback clamps the window between the content's min and max sizes on a later window layout pass, so the window keeps its old (too-tall) height with the content vertically centred inside it. It also grows the window up past the menu bar when content outgrows the screen.

**Fix:** `.fitWindowToContent()` (`WindowFitModifier.swift`) on the `MenuBarExtra` root sets the window frame itself: it measures the root with `onGeometryChange` and pins the top under the menu bar (`WindowFit.frame`). Nothing needs to list which state changes the height. Don't apply it to a window with a title bar: the bar's safe area makes the window taller than its root view, so the fit would fight SwiftUI.

### macOS 26 MenuBarExtra: ScrollView reports zero ideal height

`ScrollView` inside a `MenuBarExtra` `.window` collapses to zero height on macOS 26. Fix:

1. Use `VStack` (not `LazyVStack`) inside the ScrollView
2. Add `.fixedSize(horizontal: false, vertical: true)` to the inner VStack
3. Measure height with `onGeometryChange` and apply as explicit `.frame(height:)` — `frame(maxHeight:)` alone resolves to zero
