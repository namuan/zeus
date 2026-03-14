#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

cd "$REPO_ROOT"

echo "Running SwiftLint..."
"$REPO_ROOT/scripts/lint.sh"

echo "Running tests..."
swift test
