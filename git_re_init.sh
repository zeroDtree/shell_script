#!/usr/bin/env bash

# @help-begin
# Re-init the current directory as a fresh git repo.
# Remote URL is taken from the existing origin before deleting .git.
#
# Submodules: before wiping .git, top-level gitlinks are snapshotted and
# .git/modules is copied to a temp dir. After git init, modules are restored
# and gitlinks are re-registered (nested modules travel with .git/modules).
# Optionally run git submodule init (-i or interactive prompt) so status
# no longer shows the uninitialized "-" prefix.
#
# Usage:
#   ./git_re_init.sh [options]
#
# Commits:
#   1) .gitignore only  -> "init"
#   2) everything else  -> "reinit"  (only with -a/--all)
#
# If no options are passed, only the .gitignore "init" commit is created.
# Gitlinks are left staged (not part of "init") for a later commit.
# @help-end

# @help-options-begin
#   -a, --all               also commit all remaining files as "reinit"
#   -i, --init-submodules   run git submodule init after restore (no prompt)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

COMMIT_ALL=0
INIT_SUBMODULES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all)
      COMMIT_ALL=1
      shift
      ;;
    -i|--init-submodules)
      INIT_SUBMODULES=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unrecognized option: $1 (try --help)" >&2
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

HAS_MODULES=0
GITLINK_COUNT="$(git ls-files -s | awk '$1 == "160000"' | wc -l | tr -d ' ')"
if [[ -d .git/modules ]]; then
  HAS_MODULES=1
fi

CONFIRM_MSG="This will delete .git and re-init repo with origin=$REMOTE_URL."
if [[ "$GITLINK_COUNT" -gt 0 || "$HAS_MODULES" -eq 1 ]]; then
  CONFIRM_MSG+=" Submodules will be preserved via external .git/modules backup."
fi
read -r -p "${CONFIRM_MSG} Continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Without -i, ask when submodules are present (skip prompt if -i already set).
if [[ "$INIT_SUBMODULES" -eq 0 && ( "$GITLINK_COUNT" -gt 0 || "$HAS_MODULES" -eq 1 ) ]]; then
  read -r -p "Run git submodule init after restore? [y/N] " init_confirm
  if [[ "$init_confirm" =~ ^[Yy]$ ]]; then
    INIT_SUBMODULES=1
  fi
fi

BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git_reinit.XXXXXX")"
trap 'rm -rf "$BACKUP_DIR"' EXIT

# Format: <sha><TAB><path>  (path may contain spaces)
git ls-files -s | awk -F '\t' '
  $1 ~ /^160000 / {
    split($1, a, / /)
    print a[2] "\t" $2
  }
' > "${BACKUP_DIR}/gitlinks.txt"
GITLINK_COUNT="$(wc -l < "${BACKUP_DIR}/gitlinks.txt" | tr -d ' ')"

if [[ -d .git/modules ]]; then
  echo "Backing up .git/modules to ${BACKUP_DIR}/modules (${GITLINK_COUNT} top-level gitlink(s))"
  cp -a .git/modules "${BACKUP_DIR}/modules"
elif [[ "$GITLINK_COUNT" -gt 0 ]]; then
  echo "Snapshot: ${GITLINK_COUNT} top-level gitlink(s) (no .git/modules directory)"
fi

echo "Removing .git ..."
rm -rf .git

echo "git init ..."
git init
# -b/--initial-branch needs git>=2.28; set HEAD directly for older git
git symbolic-ref HEAD refs/heads/main

echo "Adding remote origin ..."
git remote add origin "$REMOTE_URL"

if [[ -d "${BACKUP_DIR}/modules" ]]; then
  echo "Restoring .git/modules ..."
  cp -a "${BACKUP_DIR}/modules" .git/
fi

if [[ -f .gitignore ]]; then
  echo 'Commit 1: .gitignore -> "init"'
  git add .gitignore
  git commit -m "init"
else
  echo "Warning: .gitignore not found, skip first commit"
fi

if [[ "$GITLINK_COUNT" -gt 0 ]]; then
  echo "Re-registering ${GITLINK_COUNT} top-level gitlink(s) ..."
  while IFS=$'\t' read -r sha path || [[ -n "${sha:-}" ]]; do
    [[ -n "${sha:-}" && -n "${path:-}" ]] || continue
    git update-index --add --cacheinfo "160000,${sha},${path}"
  done < "${BACKUP_DIR}/gitlinks.txt" || true

  if [[ -f .gitmodules ]]; then
    if [[ "$INIT_SUBMODULES" -eq 1 ]]; then
      echo "Running git submodule init ..."
      git submodule init
    fi
    git submodule sync --recursive || true
  fi
  git submodule absorbgitdirs 2>/dev/null || true
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
