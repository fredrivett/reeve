---
name: release
description: Tag and publish a new version of reeve. Use when shipping a release — handles version bumping, tagging, and triggering the GitHub Actions build and Homebrew tap update.
---

# Release reeve

Releases are tag-driven. Pushing a `v*` tag triggers GitHub Actions, which builds a signed DMG, creates a GitHub Release with auto-generated notes, and updates the Homebrew tap.

## Steps

1. Ensure all changes are committed and pushed to `main`
2. Run `./release.sh` — auto-increments the patch version and prompts for confirmation
3. Or specify a version explicitly: `./release.sh v0.2.0` (the `v` prefix is optional)

That's it. GitHub Actions handles the build (~5 min).

## What happens after the tag is pushed

1. `scripts/build-release.sh` compiles a release DMG
2. A GitHub Release is created with the DMG attached and auto-generated notes
3. `fredrivett/homebrew-tap` Casks/reeve.rb is updated with the new version and SHA256

## Versioning

Follows semver. To check the current latest: `git tag --sort=-v:refname | head -1`.
