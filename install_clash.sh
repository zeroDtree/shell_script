#!/usr/bin/env bash

# @help-begin
# Download Clash .gz into a directory, gunzip, and chmod.
#
# Usage:
#   ./install_clash.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./install_clash.sh --dir ~/software/clash
# @help-end

# @help-options-begin
#   -d, --dir PATH          install directory (default: ~/software/clash)
#   -u, --url URL           download URL (default: clash-linux-amd64 v1.18.0)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

install_dir="${HOME}/software/clash"
url="https://pub-eac3eb5670f44f09984dee5c57939316.r2.dev/clash-linux-amd64-v1.18.0.gz"

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

gz_name="$(basename "${url%%\?*}")"
gz_path="${install_dir}/${gz_name}"
download_file "${url}" "${gz_path}"

gunzip -f "${gz_path}"
binary_name="${gz_name%.gz}"
binary_path="${install_dir}/${binary_name}"
[ -f "${binary_path}" ] || die "binary not found after gunzip: ${binary_path}"
chmod 755 "${binary_path}"

echo "Installed clash: ${binary_path}"
