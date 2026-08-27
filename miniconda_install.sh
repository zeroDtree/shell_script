#!/usr/bin/env bash

# @help-begin
# Download the Miniconda3 Linux installer, install into a prefix, optionally
# init shells, and disable auto-activation of the base environment.
#
# Usage:
#   ./miniconda_install.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./miniconda_install.sh --prefix ~/miniconda3
#
# Linux only. After install, restart your shell (or source its rc file).
# @help-end

# @help-options-begin
#   -p, --prefix PATH       install prefix (default: ~/miniconda3)
#   -s, --shells LIST       comma-separated shells to init (default: auto-detect
#                           bash,zsh,fish via command -v)
#       --no-init           skip conda init
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

mc_root="${HOME}/miniconda3"
shells_arg=""
do_init=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -p|--prefix)
      require_value "$@"
      mc_root="$2"
      shift 2
      ;;
    -s|--shells)
      require_value "$@"
      shells_arg="$2"
      shift 2
      ;;
    --no-init)
      do_init=0
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unrecognized option: $1"
      ;;
    *)
      die "Unexpected arguments: $*"
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  die "Unexpected arguments: $*"
fi

if [ "$(uname -s)" != "Linux" ]; then
  die "this installer only supports Linux (OS: $(uname -s))"
fi

mc_root="$(expand_path "${mc_root}")"

case "$(uname -m)" in
  x86_64|amd64)
    mc_arch="x86_64"
    ;;
  aarch64|arm64)
    mc_arch="aarch64"
    ;;
  *)
    die "unsupported architecture: $(uname -m)"
    ;;
esac

mc_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${mc_arch}.sh"
installer="${mc_root}/miniconda.sh"

mkdir -p "${mc_root}"
echo "Downloading Miniconda3 (${mc_arch}) from:"
echo "  ${mc_url}"
download_file "${mc_url}" "${installer}"

bash "${installer}" -b -u -p "${mc_root}"
rm -f "${installer}"

conda_bin="${mc_root}/bin/conda"
[ -x "${conda_bin}" ] || die "conda not found after install: ${conda_bin}"

"${conda_bin}" config --set auto_activate_base false

target_shells=()
if [ -n "${shells_arg}" ]; then
  _shells_csv="${shells_arg},"
  while [ -n "${_shells_csv}" ]; do
    shell="${_shells_csv%%,*}"
    _shells_csv="${_shells_csv#*,}"
    shell="$(printf '%s' "${shell}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "${shell}" ]; then
      target_shells+=("${shell}")
    fi
  done
  unset _shells_csv
else
  for candidate in bash zsh fish; do
    if have_cmd "${candidate}"; then
      target_shells+=("${candidate}")
    fi
  done
fi

if [ "${do_init}" -eq 1 ]; then
  if [ "${#target_shells[@]}" -eq 0 ]; then
    warn "no shells found to initialize (bash/zsh/fish missing from PATH)"
  else
    echo "Initializing shells: ${target_shells[*]}"
    "${conda_bin}" init "${target_shells[@]}"
  fi
else
  echo "Skipping conda init (--no-init)."
fi

echo "Installed conda: ${conda_bin}"
"${conda_bin}" --version
