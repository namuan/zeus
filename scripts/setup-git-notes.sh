#!/bin/sh

# Setup Git notes sharing for this clone.
# Run once per clone: ./scripts/setup-git-notes.sh

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

echo "Configuring Git notes sharing..."

# Fetch notes from origin alongside regular refs
git config --add remote.origin.fetch '+refs/notes/*:refs/notes/*'

# Show notes in git log by default
git config notes.displayRef refs/notes/commits

# Preserve notes across amend and rebase
git config notes.rewriteRef refs/notes/commits
git config notes.rewriteMode concatenate

# Aliases for pushing and fetching notes
git config alias.notes-push '!git push origin refs/notes/commits'
git config alias.notes-fetch '!git fetch origin refs/notes/*:refs/notes/*'

echo ""
echo "Done. Git notes are now configured for this clone."
echo ""
echo "Usage:"
echo "  git notes add -m 'Your summary here'   # add a note to HEAD"
echo "  git notes-push                          # push notes to origin"
echo "  git notes-fetch                         # fetch notes from origin"
