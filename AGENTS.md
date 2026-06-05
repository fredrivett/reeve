# reeve — agent guidelines

Always lowercase "reeve" — in UI text, bundle names, documentation, and code comments.

## Commands

```bash
swift build          # compile
swift test           # run tests
./run.sh             # build + launch as .app (required for UI testing — see /run skill)
./release.sh         # tag and push a new release (see /release skill)
```

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

### macOS 26 MenuBarExtra: GeometryReader doesn't re-fire on view removal

On macOS 26, a `GeometryReader` in the `.background` of a `VStack` inside a `MenuBarExtra` `.window` only re-evaluates when its *proposed size changes* — not when sibling content is removed. Collapsing a `DisclosureGroup` does not trigger a fresh height measurement.

**Fix:** tie the `GeometryReader`'s `.id()` to the state controlling the toggle. SwiftUI recreates it on change, forcing a fresh measurement.

### macOS 26 MenuBarExtra: ScrollView reports zero ideal height

`ScrollView` inside a `MenuBarExtra` `.window` collapses to zero height on macOS 26. Fix:

1. Use `VStack` (not `LazyVStack`) inside the ScrollView
2. Add `.fixedSize(horizontal: false, vertical: true)` to the inner VStack
3. Measure height via `GeometryReader` + `PreferenceKey` and apply as explicit `.frame(height:)` — `frame(maxHeight:)` alone resolves to zero
