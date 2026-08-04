#!/bin/bash
# Usage: ./git_re_init.sh
# Re-init current directory as a fresh git repo with two commits:
#   1) .gitignore only  -> "init"
#   2) everything else  -> "reinit"
# Remote URL is taken from the existing origin before deleting .git.

set -euo pipefail

if [[ ! -d .git ]]; then
  echo "Error: no .git directory found in $(pwd)"
  exit 1
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$REMOTE_URL" ]]; then
  echo "Error: no remote 'origin' found, cannot recover remote URL"
  exit 1
fi

echo "Parsed origin: $REMOTE_URL"

read -r -p "This will delete .git and re-init repo with origin=$REMOTE_URL. Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "Removing .git ..."
rm -rf .git

echo "git init ..."
git init

echo "Adding remote origin ..."
git remote add origin "$REMOTE_URL"

if [[ -f .gitignore ]]; then
  echo 'Commit 1: .gitignore -> "init"'
  git add .gitignore
  git commit -m "init"
else
  echo "Warning: .gitignore not found, skip first commit"
fi

echo 'Commit 2: all files -> "reinit"'
git add .
# only commit if there is something staged
if ! git diff --cached --quiet; then
  git commit -m "reinit"
else
  echo "Nothing left to commit for reinit"
fi

echo "Done."
git remote -v
git log --oneline
