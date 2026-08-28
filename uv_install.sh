#!/usr/bin/env bash

# @help-begin
# Download the official uv standalone installer and install uv into a directory.
#
# Usage:
#   ./uv_install.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./uv_install.sh --dir ~/.local/bin --url https://astral.sh/uv/install.sh
# @help-end

# @help-options-begin
#   -d, --dir PATH          install directory (default: ~/.local/bin)
#   -u, --url URL           installer script URL (default: astral.sh uv install.sh)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

install_dir="${HOME}/.local/bin"
url="https://astral.sh/uv/install.sh"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -d|--dir)
      require_value "$@"
      install_dir="$2"
      shift 2
      ;;
    -u|--url)
      require_value "$@"
      url="$2"
      shift 2
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

install_dir="$(expand_path "${install_dir}")"
mkdir -p "${install_dir}"

run_installer() {
  env UV_INSTALL_DIR="${install_dir}" UV_NO_MODIFY_PATH=1 sh
}

download_stdout "${url}" | run_installer

if [ ! -x "${install_dir}/uv" ]; then
  die "uv binary not found after install: ${install_dir}/uv"
fi

echo "Installed uv: ${install_dir}/uv"
