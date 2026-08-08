#!/usr/bin/env bash

# @help-begin
# Download the official uv standalone installer and install uv into a directory.
#
# Usage:
#   ./install_uv.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./install_uv.sh --dir ~/.local/bin --url https://astral.sh/uv/install.sh
# @help-end

# @help-options-begin
#   -d, --dir PATH          install directory (default: ~/.local/bin)
#   -u, --url URL           installer script URL (default: astral.sh uv install.sh)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

install_dir="${HOME}/.local/bin"
url="https://astral.sh/uv/install.sh"

case "${1:-}" in
  -h|--help) usage ;;
esac

if ! ARGS=$(getopt --options="d:u:h" --longoptions="dir:,url:,help" -- "$@"); then
    echo "Failed to parse arguments." >&2
    exit 1
fi

eval set -- "${ARGS}"
while true; do
    case "$1" in
        -d|--dir)
            install_dir="$2"
            shift 2
            ;;
        -u|--url)
            url="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unrecognized option: $1" >&2
            exit 1
            ;;
    esac
done

if [ "$#" -gt 0 ]; then
    echo "Unexpected arguments: $*" >&2
    exit 1
fi

mkdir -p "$install_dir" || exit 1

run_installer() {
    env UV_INSTALL_DIR="$install_dir" UV_NO_MODIFY_PATH=1 sh
}

if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" | run_installer || exit 1
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | run_installer || exit 1
else
    echo "Need wget or curl to download uv installer" >&2
    exit 1
fi

if [ ! -x "${install_dir}/uv" ]; then
    echo "uv binary not found after install: ${install_dir}/uv" >&2
    exit 1
fi

echo "Installed uv: ${install_dir}/uv"
