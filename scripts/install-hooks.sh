#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

cd "$REPO_ROOT"
git config core.hooksPath .githooks

echo "Git hooks installed. Commits will now run lint and tests via .githooks/pre-commit."
