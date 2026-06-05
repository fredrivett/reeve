# reeve — agent guidelines

Always lowercase "reeve" — in UI text, bundle names, documentation, and code comments.

## Verifying UI changes

Use `./run.sh` to test UI changes — not `swift run`. `swift run` produces a bare binary without an `.app` bundle, so the menu bar icon won't appear. `./run.sh` wraps the binary in a minimal `.app` bundle that macOS needs to register the status item.

## Known platform quirks

### macOS 26 MenuBarExtra: GeometryReader doesn't re-fire on view removal

On macOS 26, a `GeometryReader` placed in the `.background` of a `VStack` inside a `MenuBarExtra` `.window` only re-evaluates when its *proposed size changes*, not when sibling content is removed from the VStack. This means removing a child view (e.g. collapsing a `DisclosureGroup`) does not trigger a fresh height measurement.

**Fix:** give the `GeometryReader` an `.id()` tied to the state that controls the content change. SwiftUI recreates the reader on each toggle, forcing a fresh measurement in the new layout context.

### macOS 26 MenuBarExtra: ScrollView reports zero ideal height

`ScrollView` inside a `MenuBarExtra` `.window` reports zero ideal height on macOS 26, causing the window to collapse to just the header. Fix:

1. Use `VStack` (not `LazyVStack`) inside the ScrollView
2. Add `.fixedSize(horizontal: false, vertical: true)` to the inner VStack
3. Measure height via `GeometryReader` + `PreferenceKey` and set an explicit `.frame(height:)` on the ScrollView — `frame(maxHeight:)` alone resolves to zero
