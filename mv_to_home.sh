#!/usr/bin/env bash

# @help-begin
# Move a file or directory under a user's home directory, then chown -R it.
#
# Usage:
#   ./mv_to_home.sh [options] SOURCE
#
# Home is read from getent passwd. If getent is not available, /home/USER
# is used instead. The destination is HOME/PATH. PATH defaults to
# basename(SOURCE). An absolute PATH is accepted only when it stays under
# HOME. The destination's parent directory must already exist.
#
# Ownership of the moved path is USER:GROUP. GROUP defaults to the target
# user. sudo is omitted when the script is already running as root.
# The move is refused when SOURCE is missing, the user is unknown, the
# destination already exists, a parent directory is missing, or the
# destination is outside HOME.
#
# Example:
#   ./mv_to_home.sh --user USER ~/Desktop/domainbed-main
#   ./mv_to_home.sh --user USER --dest projects/domainbed ~/Desktop/domainbed-main
# @help-end

# @help-options-begin
#   -u, --user USER      user who will own the moved path
#   -d, --dest PATH      path under HOME (default: basename of SOURCE)
#   -g, --group GROUP    group for chown (default: USER)
#   -n, --dry-run        print mv and chown without running them
#   -h, --help           show help
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
DEST_PATH=""
DEST_SET=0
GROUP=""
DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -u|--user|-d|--dest|-g|--group)
      require_value "$@"
      case "$2" in
        -*) die "$1 requires a value" ;;
      esac
      case "$1" in
        -u|--user) TARGET_USER="$2" ;;
        -d|--dest)
          DEST_PATH="$2"
          DEST_SET=1
          ;;
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

# Drop empty and "." components. Refuse ".." so the path cannot climb out of HOME.
normalize_rel_components() {
  local raw="$1"
  local label="$2"
  local rest="$raw"
  local part=""
  local cleaned=""

  while [ -n "$rest" ]; do
    case "$rest" in
      */*)
        part="${rest%%/*}"
        rest="${rest#*/}"
        ;;
      *)
        part="$rest"
        rest=""
        ;;
    esac
    case "$part" in
      ""|.)
        ;;
      ..)
        die "refusing destination path: ${label}"
        ;;
      *)
        if [ -n "$cleaned" ]; then
          cleaned="${cleaned}/${part}"
        else
          cleaned="$part"
        fi
        ;;
    esac
  done
  if [ -z "$cleaned" ]; then
    die "refusing destination path: ${label}"
  fi
  printf '%s\n' "$cleaned"
}

# Absolute destination under HOME. A relative path is joined onto HOME.
resolve_dest() {
  local raw="$1"
  local home="$2"
  local expanded=""
  local rel=""

  expanded="$(expand_path "$raw")"
  expanded="$(strip_trailing_slashes "$expanded")"
  case "$expanded" in
    ""|/|.|..)
      die "refusing destination path: ${raw}"
      ;;
  esac

  case "$expanded" in
    /*)
      if [ "$home" = / ]; then
        rel="${expanded#/}"
      else
        case "$expanded" in
          "$home")
            die "refusing to replace home directory: ${home}"
            ;;
          "$home"/*)
            rel="${expanded#"$home"/}"
            ;;
          *)
            die "destination is not under home: ${expanded}"
            ;;
        esac
      fi
      ;;
    *)
      rel="$expanded"
      ;;
  esac

  rel="$(normalize_rel_components "$rel" "$raw")"
  if [ "$home" = / ]; then
    printf '/%s\n' "$rel"
  else
    printf '%s/%s\n' "$home" "$rel"
  fi
}

# Return 0 when PATH is ROOT or a descendant of ROOT.
path_is_under() {
  local root="$1"
  local path="$2"
  if [ "$path" = "$root" ] || [ "$root" = / ]; then
    return 0
  fi
  case "$path" in
    "$root"/*) return 0 ;;
  esac
  return 1
}

physical_path() {
  local path="$1"
  local resolved=""
  resolved="$(CDPATH= cd -P -- "$path" && pwd)" || die "cannot resolve directory: ${path}"
  printf '%s\n' "$resolved"
}

# Refuse unless every ancestor of PARENT exists, is a directory, and stays under HOME.
require_dest_parent() {
  local home="$1"
  local parent="$2"
  local home_real=""
  local current=""
  local rel=""
  local rest=""
  local part=""
  local dir_real=""

  if [ "$parent" = "$home" ]; then
    return 0
  fi

  case "$home" in
    /)
      rel="${parent#/}"
      ;;
    *)
      case "$parent" in
        "$home"/*) rel="${parent#"$home"/}" ;;
        *) die "destination is not under home: ${parent}" ;;
      esac
      ;;
  esac

  home_real="$(physical_path "$home")"
  current="$home"
  rest="$rel"
  while [ -n "$rest" ]; do
    case "$rest" in
      */*)
        part="${rest%%/*}"
        rest="${rest#*/}"
        ;;
      *)
        part="$rest"
        rest=""
        ;;
    esac
    if [ "$current" = / ]; then
      current="/${part}"
    else
      current="${current}/${part}"
    fi
    if [ ! -L "$current" ] && [ ! -e "$current" ]; then
      die "destination parent does not exist: ${current}"
    fi
    if [ ! -d "$current" ]; then
      die "destination parent is not a directory: ${current}"
    fi
    dir_real="$(physical_path "$current")"
    if ! path_is_under "$home_real" "$dir_real"; then
      die "destination escapes home via symlink: ${current} -> ${dir_real}"
    fi
  done
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
if [ "$DEST_SET" -eq 0 ]; then
  DEST_PATH="$(basename -- "$SOURCE")"
fi
DEST="$(resolve_dest "$DEST_PATH" "$HOME_DIR")"
DEST_PARENT="$(dirname -- "$DEST")"

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

require_dest_parent "$HOME_DIR" "$DEST_PARENT"
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
run_privileged ls -la -- "$DEST_PARENT" || warn "moved and chowned, but listing ${DEST_PARENT} failed"
