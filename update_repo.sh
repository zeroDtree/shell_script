#!/usr/bin/env bash

# @help-begin
# Clone a git repository or update an existing checkout.
#
# Usage:
#   ./update_repo.sh REPO_URL TARGET_DIR [BRANCH]
#   ./update_repo.sh [options] REPO_URL TARGET_DIR [BRANCH]
#
# If TARGET_DIR does not exist, the repository is cloned. If it exists, origin
# is aligned to REPO_URL and the selected branch is fast-forwarded.
#
# If no branch is given, the current branch is updated. Local uncommitted
# changes are stashed around the update and restored afterward.
#
# This file can also be sourced to get:
#   update_repo REPO_URL TARGET_DIR [BRANCH]
# @help-end

# @help-options-begin
#   -b, --branch BRANCH     branch to clone or check out
#   --no-stash              abort if the working tree is dirty
#   -f, --force             discard local commits; reset --hard to origin/BRANCH
#   -h, --help              show help
# @help-options-end

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; return 1 2>/dev/null || exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

# Strip a trailing slash and optional .git suffix for origin URL compares.
normalize_git_url() {
  local url="$1"
  url="${url%/}"
  url="${url%.git}"
  url="${url%/}"
  printf '%s\n' "$url"
}

# Restore a stash (if any) then die. Args: TARGET_DIR STASHED MESSAGE...
_update_repo_fail() {
  local dir="$1"
  local stashed="$2"
  shift 2
  if [ "$stashed" -eq 1 ]; then
    git -C "$dir" stash pop || warn "could not restore stashed changes in $dir"
  fi
  die "$@"
}

# Clone or update a git repository.
#   update_repo REPO_URL TARGET_DIR [BRANCH] [NO_STASH] [FORCE]
# NO_STASH and FORCE are 0/1 (default 0). Used by the CLI; sourcers can omit them.
update_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local branch="${3:-}"
  local no_stash="${4:-0}"
  local force="${5:-0}"
  local stashed=0
  local current_branch=""
  local current_remote=""
  local head_ref=""

  if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
    die "REPO_URL and TARGET_DIR are required"
  fi
  have_cmd git || die "need git"

  target_dir="$(expand_path "$target_dir")"

  if [ ! -d "$target_dir" ]; then
    info "Cloning repository from $repo_url to $target_dir..."
    if [ -n "$branch" ]; then
      git clone -b "$branch" "$repo_url" "$target_dir" || die "clone failed: $repo_url"
    else
      git clone "$repo_url" "$target_dir" || die "clone failed: $repo_url"
    fi
  else
    if ! git -C "$target_dir" rev-parse --git-dir >/dev/null 2>&1; then
      _update_repo_fail "$target_dir" "$stashed" "$target_dir exists but is not a git repository"
    fi
    info "Repository $target_dir already exists, skipping clone."
  fi

  if current_remote="$(git -C "$target_dir" remote get-url origin 2>/dev/null)"; then
    if [ "$(normalize_git_url "$current_remote")" != "$(normalize_git_url "$repo_url")" ]; then
      info "Updating origin URL from $current_remote to $repo_url..."
      git -C "$target_dir" remote set-url origin "$repo_url" || die "failed to set origin URL"
    fi
  else
    info "Adding origin remote with URL $repo_url..."
    git -C "$target_dir" remote add origin "$repo_url" || die "failed to add origin remote"
  fi

  if [ -n "$(git -C "$target_dir" status --porcelain)" ]; then
    if [ "$no_stash" -eq 1 ]; then
      _update_repo_fail "$target_dir" "$stashed" "working tree is dirty in $target_dir"
    fi
    info "Stashing local changes in $target_dir..."
    git -C "$target_dir" stash push -u -m "update_repo.sh auto-stash" || die "failed to stash local changes in $target_dir"
    stashed=1
  fi

  info "Fetching from origin..."
  git -C "$target_dir" fetch origin || _update_repo_fail "$target_dir" "$stashed" "fetch failed in $target_dir"

  if [ -n "$branch" ]; then
    if git -C "$target_dir" show-ref --verify --quiet "refs/heads/$branch"; then
      head_ref="$(git -C "$target_dir" symbolic-ref --short HEAD 2>/dev/null || true)"
      if [ "$head_ref" != "$branch" ]; then
        info "Switching from ${head_ref:-detached HEAD} to $branch..."
        git -C "$target_dir" switch "$branch" || _update_repo_fail "$target_dir" "$stashed" "failed to switch to $branch"
      fi
    elif git -C "$target_dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      info "Creating local branch $branch tracking origin/$branch..."
      git -C "$target_dir" switch -c "$branch" --track "origin/$branch" || _update_repo_fail "$target_dir" "$stashed" "failed to create tracking branch $branch"
    else
      _update_repo_fail "$target_dir" "$stashed" "branch $branch not found in $target_dir (local or origin)"
    fi
  elif current_branch="$(git -C "$target_dir" symbolic-ref --short HEAD 2>/dev/null)"; then
    branch="$current_branch"
  else
    warn "detached HEAD in $target_dir; pulling without branch switch"
  fi

  if [ "$force" -eq 1 ]; then
    if [ -z "$branch" ]; then
      _update_repo_fail "$target_dir" "$stashed" "cannot --force without a branch (detached HEAD and no branch given)"
    fi
    info "Resetting $target_dir hard to origin/$branch..."
    git -C "$target_dir" reset --hard "origin/$branch" || _update_repo_fail "$target_dir" "$stashed" "failed to reset $target_dir to origin/$branch"
  elif [ -n "$branch" ]; then
    info "Pulling latest changes from branch $branch..."
    git -C "$target_dir" -c pull.rebase=false pull --ff-only origin "$branch" || _update_repo_fail "$target_dir" "$stashed" "fast-forward pull failed for $branch in $target_dir"
  else
    git -C "$target_dir" -c pull.rebase=false pull --ff-only || _update_repo_fail "$target_dir" "$stashed" "fast-forward pull failed in $target_dir"
  fi

  if [ "$stashed" -eq 1 ]; then
    git -C "$target_dir" stash pop || warn "could not restore stashed changes in $target_dir"
    stashed=0
  fi
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0
fi

set -euo pipefail

repo_url=""
target_dir=""
branch=""
no_stash=0
force=0

[ "$#" -ge 1 ] || usage

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -b|--branch)
      require_value "$@"
      branch="$2"
      shift 2
      ;;
    --no-stash)
      no_stash=1
      shift
      ;;
    -f|--force)
      force=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unrecognized option: $1 (try --help)"
      ;;
    *)
      break
      ;;
  esac
done

if [ -n "${1:-}" ]; then
  repo_url="$1"
  shift
fi
if [ -n "${1:-}" ]; then
  target_dir="$1"
  shift
fi
if [ -n "${1:-}" ]; then
  if [ -n "$branch" ]; then
    die "branch specified both as option and positional argument"
  fi
  branch="$1"
  shift
fi
if [ "$#" -gt 0 ]; then
  die "unexpected arguments: $*"
fi

if [ -z "$repo_url" ] || [ -z "$target_dir" ]; then
  die "REPO_URL and TARGET_DIR are required (try --help)"
fi

update_repo "$repo_url" "$target_dir" "$branch" "$no_stash" "$force"
