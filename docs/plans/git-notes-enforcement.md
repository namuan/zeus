# Git Notes Sharing And Enforcement

This plan adds shared Git notes across the team and enforces that every pushed commit has a note. It is based on the provided document (setup script + pre-push enforcement + optional reminder in check script).

## Problem Statement

- Git notes are not shared by default, so team members do not see each other's notes.
- There is no enforcement that a commit has an explanatory note before it is pushed.

## Goals

- Ensure all clones fetch Git notes automatically.
- Make Git logs display notes by default.
- Preserve notes across amend/rebase.
- Enforce that every pushed commit has a note (reject push if missing).
- Keep the workflow compatible with the existing `scripts/check.sh`.

## Non-Goals

- Enforcing notes at commit time (pre-commit). This is not possible because the commit SHA does not exist yet.
- Changing CI or adding server-side hooks.

## Proposed Solution

1. Add a repo script `scripts/setup-git-notes.sh` to configure notes sharing for each clone.
2. Add a `pre-push` hook that blocks pushes containing commits without notes, with a clear error message and example command.
3. Optionally add a friendly reminder to `scripts/check.sh` to prompt adding notes after commit.

## Implementation Plan

### Phase 1: Add Setup Script

**File:** `scripts/setup-git-notes.sh`

- Configure `remote.origin.fetch` to include `refs/notes/*`.
- Configure notes display to `refs/notes/commits`.
- Configure rewrite rules to preserve notes through amend/rebase.
- Add helper aliases: `notes-push` and `notes-fetch`.
- Print usage instructions to run once per clone.

### Phase 2: Add Pre-Push Hook

**File:** `.git/hooks/pre-push`

- Parse pushed ranges from stdin.
- For each commit in the range, require a non-empty note.
- Print the exact error message with example `git notes add -m ...` and exit 1 on missing notes.

Notes:
- This is a local hook; recommend a lightweight wrapper if the project later standardizes hooks in `scripts/`.

### Phase 3: Optional Reminder In Checks

**File:** `scripts/check.sh`

- Append a reminder message:
  - `echo "Reminder: add a Git note after this commit"`
  - `echo "git notes add -m 'Your summary here'"`

## Rollout

1. Add `scripts/setup-git-notes.sh` to the repo and document usage in README or onboarding docs.
2. Each developer runs the setup script once per clone.
3. Each developer installs the pre-push hook (or a repo-managed wrapper if adopted later).

## Testing / Verification

- Run the setup script, then verify:
  - `git config --local --get-all remote.origin.fetch` includes `refs/notes/*`.
  - `git config --local --get notes.displayRef` is `refs/notes/commits`.
- Create a test commit without a note and confirm `git push` is rejected.
- Add a note with `git notes add -m "test" <sha>` and confirm push succeeds.

## Risks And Mitigations

- **Risk:** Developers forget to install the hook.
  - **Mitigation:** Add onboarding documentation and optionally a wrapper in `scripts/`.
- **Risk:** Notes are not pushed automatically.
  - **Mitigation:** The setup script adds `notes-push` alias and fetch config.

