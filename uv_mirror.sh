#!/usr/bin/env bash

# @help-begin
# Write uv's default PyPI index to ~/.config/uv/uv.toml.
# Backs up an existing file and replaces it only when the content changes.
#
# Usage:
#   ./uv_mirror.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./uv_mirror.sh --url https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple/
# @help-end

# @help-options-begin
#   -u, --url URL           PyPI simple index URL (default: Tsinghua mirror)
#   -o, --output PATH       uv.toml path (default: ~/.config/uv/uv.toml)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

DEFAULT_MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple/"
mirror_url="${DEFAULT_MIRROR_URL}"
output_path="${HOME}/.config/uv/uv.toml"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -u|--url)
      require_value "$@"
      mirror_url="$2"
      shift 2
      ;;
    -o|--output)
      require_value "$@"
      output_path="$2"
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

if [ -z "${mirror_url}" ]; then
  die "--url requires a non-empty URL"
fi

output_path="$(expand_path "${output_path}")"
mkdir -p "$(dirname "${output_path}")"

tmp="$(mktemp)"
cleanup() {
  rm -f "${tmp}"
}
trap cleanup EXIT

cat >"${tmp}" <<EOF
[[index]]
url = "${mirror_url}"
default = true
EOF

if [ -f "${output_path}" ] && cmp -s "${tmp}" "${output_path}"; then
  echo "Config unchanged, skipping: ${output_path}"
else
  if [ -f "${output_path}" ]; then
    cp -a "${output_path}" "${output_path}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  cp -a "${tmp}" "${output_path}"
  echo "Updated: ${output_path}"
fi

echo "uv default index: ${mirror_url}"
