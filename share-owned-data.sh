#!/usr/bin/env bash

# @help-begin
# Publish a tree you own into SHARED_GROUP so other members of that group can
# use it. Run as the owning user (not root). You must already belong to
# SHARED_GROUP, and every inode under each PATH must be owned by you.
#
# Usage:
#   ./share-owned-data.sh [options] PATH [PATH ...]
#
# Default (without --normalize-perms): chgrp -R and chmod g+s on directories only;
# regular file modes are unchanged.
#
# Each PATH must lie under SHARED_DATA_PATH (absolute or relative).
# chgrp runs before chmod so the setgid bit is kept (you are in SHARED_GROUP).
# Symlinks are not followed.
#
# Defaults match a stock isolation host and can be overridden by the environment:
#   DATA_ROOT=/data
#   SHARED_DATA_PATH=${DATA_ROOT}/shared_data
#   SHARED_GROUP=shared_data
# DRY_RUN=1 is the same as --dry-run.
#
# Root-owned or mixed-owner trees: use the isolation repo's
# fix-migrated-shared-data.sh as root.
# @help-end

# @help-options-begin
#   --normalize-perms   chmod directories to 2755; files without any execute bit
#                       to 644, with any execute bit to 755
#   -n, --dry-run       print chgrp and chmod without running them
#   -h, --help          show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

# Print a single -perm MODE string for "any u/g/o execute bit" (e.g. /111 or +111).
# GNU findutils: -perm /111. Newer GNU removed +MODE; BSD find rejects /111 but accepts +111.
detect_find_perm_any_exec() {
  local d f
  d="$(mktemp -d)" || return 1
  f="${d}/t"
  touch "$f" || {
    rm -rf "$d"
    return 1
  }
  chmod 700 "$f" || {
    rm -rf "$d"
    return 1
  }
  if [[ -n "$(find "$f" -maxdepth 0 -type f -perm /111 -print 2>/dev/null)" ]]; then
    printf '/111\n'
  elif [[ -n "$(find "$f" -maxdepth 0 -type f -perm +111 -print 2>/dev/null)" ]]; then
    printf '+111\n'
  else
    rm -rf "$d"
    return 1
  fi
  rm -rf "$d"
}

caller_in_group() {
  local want="$1"
  local g
  while IFS= read -r g; do
    [[ "$g" == "$want" ]] && return 0
  done < <(id -nG | tr ' ' '\n')
  return 1
}

under_root() {
  local c="$1"
  local root="$2"
  [[ "$c" == "$root" || "$c" == "$root"/* ]]
}

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    print_cmd "$@"
  else
    "$@"
  fi
}

chmod_dirs() {
  local tree="$1"
  local mode="$2"
  local d
  if [ "$DRY_RUN" -eq 1 ]; then
    while IFS= read -r -d '' d; do
      print_cmd chmod "$mode" "$d"
    done < <(find "$tree" -type d -print0 2>/dev/null)
  else
    find "$tree" -type d -exec chmod "$mode" {} +
  fi
}

chmod_files() {
  local tree="$1"
  local pe="$2"
  local f
  if [ "$DRY_RUN" -eq 1 ]; then
    while IFS= read -r -d '' f; do
      print_cmd chmod 644 "$f"
    done < <(find "$tree" -type f ! -perm "${pe}" -print0 2>/dev/null)
    while IFS= read -r -d '' f; do
      print_cmd chmod 755 "$f"
    done < <(find "$tree" -type f -perm "${pe}" -print0 2>/dev/null)
  else
    find "$tree" -type f ! -perm "${pe}" -exec chmod 644 {} +
    find "$tree" -type f -perm "${pe}" -exec chmod 755 {} +
  fi
}

: "${DATA_ROOT:=/data}"
: "${SHARED_DATA_PATH:=${DATA_ROOT}/shared_data}"
: "${SHARED_GROUP:=shared_data}"

NORMALIZE_PERMS=0
if [ "${DRY_RUN:-0}" = 1 ]; then
  DRY_RUN=1
else
  DRY_RUN=0
fi
PATHS=()

if [ "$#" -eq 0 ]; then
  usage
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --normalize-perms)
      NORMALIZE_PERMS=1
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      die "unrecognized option: $1 (try --help)"
      ;;
    *)
      PATHS+=("$1")
      shift
      ;;
  esac
done

[ "${#PATHS[@]}" -gt 0 ] || usage

[ "$(id -u)" -ne 0 ] || die "run as the owning user, not root (root-owned or mixed trees: fix-migrated-shared-data.sh)"

[ -n "${SHARED_DATA_PATH}" ] || die "SHARED_DATA_PATH is not set"
[ -n "${SHARED_GROUP}" ] || die "SHARED_GROUP is not set"
[ -d "${SHARED_DATA_PATH}" ] || die "SHARED_DATA_PATH is not a directory: ${SHARED_DATA_PATH} (run isolation/init-host.sh first)"

CALLER="$(id -un)"
caller_in_group "${SHARED_GROUP}" || die "user ${CALLER} is not in group ${SHARED_GROUP} (log in again if you were just added)"

ROOT_CANON="$(readlink -f "${SHARED_DATA_PATH}")"
CANON=()
for arg in "${PATHS[@]}"; do
  [ -e "$arg" ] || die "path does not exist: ${arg}"
  c="$(readlink -f "$arg")"
  under_root "$c" "${ROOT_CANON}" || die "path must be under SHARED_DATA_PATH=${SHARED_DATA_PATH} (resolved: ${c})"
  CANON+=("$c")
done

for p in "${CANON[@]}"; do
  foreign="$(find "$p" ! -user "${CALLER}" -print -quit)" || die "cannot list ${p}"
  [ -z "${foreign}" ] || die "not owner of ${foreign} (this script only updates trees you own)"
done

SHARE_OWNED_FIND_PERM_ANY=""
if [ "${NORMALIZE_PERMS}" -eq 1 ]; then
  SHARE_OWNED_FIND_PERM_ANY="$(detect_find_perm_any_exec)" ||
    die "find(1) does not support -perm /111 or +111 (any execute bit); cannot use --normalize-perms"
fi

for p in "${CANON[@]}"; do
  info "sharing: ${p}"
  run_cmd chgrp -R "${SHARED_GROUP}" "$p"
  if [ "${NORMALIZE_PERMS}" -eq 1 ]; then
    chmod_dirs "$p" 2755
    chmod_files "$p" "${SHARE_OWNED_FIND_PERM_ANY}"
  else
    chmod_dirs "$p" g+s
  fi
done

if [ "${NORMALIZE_PERMS}" -eq 1 ]; then
  info "ok: chgrp ${SHARED_GROUP}, normalized dirs 2755 + files 644/755 (${#CANON[@]} path(s))"
else
  info "ok: group ${SHARED_GROUP} and setgid on directories under ${#CANON[@]} path(s)"
fi
