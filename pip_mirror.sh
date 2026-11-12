#!/usr/bin/env bash

# @help-begin
# Write pip's default PyPI index to ~/.config/pip/pip.conf.
# Backs up an existing file and replaces it only when the content changes.
#
# Usage:
#   ./pip_mirror.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./pip_mirror.sh --url https://pypi.tuna.tsinghua.edu.cn/simple
# @help-end

# @help-options-begin
#   -u, --url URL           PyPI simple index URL (default: Tsinghua mirror)
#   -o, --output PATH       pip.conf path (default: ~/.config/pip/pip.conf)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

DEFAULT_MIRROR_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
mirror_url="${DEFAULT_MIRROR_URL}"
output_path="${HOME}/.config/pip/pip.conf"

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
[global]
index-url = ${mirror_url}
EOF

deploy_file_if_changed "${tmp}" "${output_path}" || true
echo "pip default index: ${mirror_url}"
