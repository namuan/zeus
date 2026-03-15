#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

cd "$REPO_ROOT"

echo "Running SwiftLint..."
"$REPO_ROOT/scripts/lint.sh"

echo "Running tests..."
swift test

echo ""
echo "Reminder: add a Git note to your commit before pushing."
echo "  git notes add -m 'Your summary here'"
echo "  git notes-push"
