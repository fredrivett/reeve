#!/bin/bash
# Tag a new release and push to trigger the GitHub Actions release workflow
set -e

# Releases are always cut from an up-to-date main. Guard against tagging the
# wrong commit: require a clean tree, then fast-forward main to origin. Fail
# loudly rather than switching over uncommitted work or force-updating over
# unexpected state.
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean — commit or stash first."; exit 1; }
git fetch origin --tags
git checkout main
git merge --ff-only origin/main || { echo "Local main can't fast-forward to origin/main — reconcile first."; exit 1; }

CURRENT=$(git tag --sort=-v:refname | grep '^v' | head -1)
echo "Current version: ${CURRENT:-none}"

if [ -z "$1" ]; then
    # Auto-increment patch version
    if [ -z "$CURRENT" ]; then
        NEXT="v0.1.0"
    else
        BASE="${CURRENT#v}"
        MAJOR=$(echo "$BASE" | cut -d. -f1)
        MINOR=$(echo "$BASE" | cut -d. -f2)
        PATCH=$(echo "$BASE" | cut -d. -f3)
        NEXT="v${MAJOR}.${MINOR}.$((PATCH + 1))"
    fi
else
    NEXT="$1"
    # Ensure v prefix
    [[ "$NEXT" != v* ]] && NEXT="v${NEXT}"
fi

echo "Tagging: $NEXT"
read -r -p "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

git tag "$NEXT"
git push origin "$NEXT"
echo "Released $NEXT — GitHub Actions will build the DMG and update the Homebrew tap."
