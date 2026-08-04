#!/bin/bash
# Usage: ./git_re_init.sh [-a|--all]
# Re-init current directory as a fresh git repo:
#   1) .gitignore only  -> "init"
#   2) everything else  -> "reinit"  (optional, with -a/--all)
# Remote URL is taken from the existing origin before deleting .git.

set -euo pipefail

COMMIT_ALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all)
      COMMIT_ALL=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-a|--all]"
      echo "  -a, --all  also commit all remaining files as \"reinit\""
      exit 0
      ;;
    *)
      echo "Unrecognized option: $1"
      echo "Usage: $0 [-a|--all]"
      exit 1
      ;;
  esac
done

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
git init -b main

echo "Adding remote origin ..."
git remote add origin "$REMOTE_URL"

if [[ -f .gitignore ]]; then
  echo 'Commit 1: .gitignore -> "init"'
  git add .gitignore
  git commit -m "init"
else
  echo "Warning: .gitignore not found, skip first commit"
fi

if [[ "$COMMIT_ALL" -eq 1 ]]; then
  echo 'Commit 2: all files -> "reinit"'
  git add .
  if ! git diff --cached --quiet; then
    git commit -m "reinit"
  else
    echo "Nothing left to commit for reinit"
  fi
fi

echo "Done."
git remote -v
git log --oneline
