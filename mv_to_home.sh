#!/usr/bin/env bash

# @help-begin
# Move a file or directory into a user's home directory, then chown -R it.
#
# Usage:
#   ./mv_to_home.sh [options] SOURCE
#
# Home is read from getent passwd. If getent is not available, /home/USER
# is used instead. The destination is HOME/basename(SOURCE). An optional
# destination name replaces only that final path component and must stay
# under HOME.
#
# Ownership is set to USER:GROUP. GROUP defaults to the target user.
# sudo is omitted when the script is already running as root.
# The move is refused when SOURCE is missing, the user is unknown, or the
# destination already exists.
#
# Example:
#   ./mv_to_home.sh --user zhougl ~/Desktop/domainbed-main
# @help-end

# @help-options-begin
#   -u, --user USER         user who will own the moved path
#   -d, --dest-name NAME    final path component under HOME (default: basename of SOURCE)
#   -g, --group GROUP       group for chown (default: USER)
#   -n, --dry-run           print mv and chown without running them
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

if [ "$#" -eq 0 ]; then
  usage
fi

TARGET_USER=""
DEST_NAME=""
GROUP=""
DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -u|--user|-d|--dest-name|-g|--group)
      require_value "$@"
      case "$2" in
        -*) die "$1 requires a value" ;;
      esac
      case "$1" in
        -u|--user) TARGET_USER="$2" ;;
        -d|--dest-name) DEST_NAME="$2" ;;
        -g|--group) GROUP="$2" ;;
      esac
      shift 2
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
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

if [ "$#" -lt 1 ] || [ -z "$TARGET_USER" ]; then
  usage
fi
if [ "$#" -gt 1 ]; then
  die "too many arguments (try --help)"
fi

SOURCE="$(expand_path "$1")"

validate_account() {
  local kind="$1"
  local name="$2"
  case "$name" in
    ""|-*)
      die "invalid ${kind}: ${name}"
      ;;
    *[!A-Za-z0-9._-]*)
      die "invalid ${kind}: ${name}"
      ;;
  esac
}

strip_trailing_slashes() {
  local path="$1"
  while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

# Absolute path of SOURCE itself. Do not resolve symlinks; mv moves the link.
to_absolute() {
  local path="$1"
  local dir base
  case "$path" in
    /*) ;;
    *) path="$(pwd)/$path" ;;
  esac
  if [ -d "$path" ] && [ ! -L "$path" ]; then
    (CDPATH= cd -- "$path" && pwd)
    return
  fi
  dir="$(dirname -- "$path")"
  base="$(basename -- "$path")"
  if [ -d "$dir" ]; then
    printf '%s/%s\n' "$(CDPATH= cd -- "$dir" && pwd)" "$base"
  else
    printf '%s\n' "$path"
  fi
}

validate_dest_name() {
  local name="$1"
  case "$name" in
    ""|/|.|..)
      die "refusing destination name: ${name}"
      ;;
    */*)
      die "--dest-name must be a single path component: ${name}"
      ;;
  esac
}

resolve_user_home() {
  local user="$1"
  local entry=""
  local home=""
  local assumed=0

  if have_cmd getent; then
    entry="$(getent passwd "$user" || true)"
    if [ -z "$entry" ]; then
      die "unknown user: ${user}"
    fi
    home="$(printf '%s\n' "$entry" | awk -F: 'NR==1 { print $6 }')"
    if [ -z "$home" ]; then
      home="/home/${user}"
      assumed=1
    fi
  else
    home="/home/${user}"
    assumed=1
    if ! id "$user" >/dev/null 2>&1 && [ ! -d "$home" ]; then
      die "unknown user: ${user}"
    fi
  fi

  home="$(strip_trailing_slashes "$home")"
  case "$home" in
    /*) ;;
    *) die "user home is not an absolute path: ${home}" ;;
  esac
  if [ ! -d "$home" ]; then
    if [ "$assumed" -eq 1 ]; then
      die "home directory does not exist: ${home} (assumed /home/${user})"
    fi
    die "home directory does not exist: ${home}"
  fi
  printf '%s\n' "$home"
}

print_cmd() {
  local arg
  printf '+'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      print_cmd "$@"
    else
      "$@"
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      print_cmd sudo "$@"
    else
      sudo "$@"
    fi
  fi
}

validate_account "user" "$TARGET_USER"
if [ -n "$GROUP" ]; then
  validate_account "group" "$GROUP"
else
  GROUP="$TARGET_USER"
fi

SOURCE="$(strip_trailing_slashes "$SOURCE")"
if [ ! -e "$SOURCE" ] && [ ! -L "$SOURCE" ]; then
  die "source does not exist: ${SOURCE}"
fi
SOURCE="$(to_absolute "$SOURCE")"

HOME_DIR="$(resolve_user_home "$TARGET_USER")"
if [ -z "$DEST_NAME" ]; then
  DEST_NAME="$(basename -- "$SOURCE")"
fi
validate_dest_name "$DEST_NAME"
DEST="${HOME_DIR}/${DEST_NAME}"

if [ "$SOURCE" = "$DEST" ]; then
  die "source and destination are the same: ${SOURCE}"
fi
case "$DEST" in
  "$SOURCE"|"$SOURCE"/*)
    die "refusing to move a path into itself: ${SOURCE}"
    ;;
esac
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  die "destination already exists: ${DEST}"
fi

if have_cmd getent; then
  case "$GROUP" in
    *[!0-9]*)
      getent group "$GROUP" >/dev/null || die "unknown group: ${GROUP}"
      ;;
  esac
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run:"
  run_privileged mv -- "$SOURCE" "$DEST"
  run_privileged chown -R -- "${TARGET_USER}:${GROUP}" "$DEST"
  exit 0
fi

info "Moving:"
info "  ${SOURCE}"
info "  -> ${DEST}"
run_privileged mv -- "$SOURCE" "$DEST"
info "Setting ownership ${TARGET_USER}:${GROUP}"
run_privileged chown -R -- "${TARGET_USER}:${GROUP}" "$DEST"
run_privileged ls -la -- "$HOME_DIR" || warn "moved and chowned, but listing ${HOME_DIR} failed"
