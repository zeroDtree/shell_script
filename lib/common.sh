#!/usr/bin/env bash
# Shared helpers for repo shell scripts. Source from the invoking script:
#   _LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
#   [ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
#   # shellcheck source=lib/common.sh
#   . "${_LIB}"

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "error: source this file; do not execute it" >&2
  exit 1
fi

if [ -n "${_SHELL_SCRIPT_COMMON_SH:-}" ]; then
  return 0
fi
_SHELL_SCRIPT_COMMON_SH=1

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

warn() {
  printf '%s\n' "warning: $*" >&2
}

info() {
  printf '%s\n' "$*"
}

# Print @help-begin / @help-options-begin from PATH (default: invoking script).
usage() {
  local src="${1:-$0}"
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "${src}"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "${src}"
  exit 0
}

# Expand a leading ~ or ~/ in PATH (CLI args may leave them literal).
expand_path() {
  case "$1" in
    "~"|"~/"*) printf '%s\n' "${HOME}${1#\~}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Call as: require_value "$@"
require_value() {
  if [ "$#" -lt 2 ]; then
    die "$1 requires a value"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

download_file() {
  local url="$1"
  local dest="$2"

  if have_cmd curl; then
    curl -fsSL "${url}" -o "${dest}"
  elif have_cmd wget; then
    wget -qO "${dest}" "${url}"
  else
    die "need curl or wget to download"
  fi

  if [ ! -s "${dest}" ]; then
    die "download produced an empty file: ${dest}"
  fi
}

download_file_resume() {
  local url="$1"
  local dest="$2"

  info "Downloading:"
  info "  ${url}"
  info "  -> ${dest}"

  if have_cmd wget; then
    wget -c "${url}" -O "${dest}"
  elif have_cmd curl; then
    curl -fL -C - -o "${dest}" "${url}"
  else
    die "need wget or curl to download"
  fi

  if [ ! -s "${dest}" ]; then
    die "download produced an empty file: ${dest}"
  fi
}

download_stdout() {
  local url="$1"

  if have_cmd wget; then
    wget -qO- "${url}"
  elif have_cmd curl; then
    curl -fsSL "${url}"
  else
    die "need wget or curl to download"
  fi
}
