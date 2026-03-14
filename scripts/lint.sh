#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: SwiftLint is not installed. Install it with 'brew install swiftlint'." >&2
    exit 1
fi

cd "$REPO_ROOT"
exec swiftlint lint --strict --config "$REPO_ROOT/.swiftlint.yml" Sources Tests
