#!/bin/bash
# Tag a new release and push to trigger the GitHub Actions release workflow
set -e

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
