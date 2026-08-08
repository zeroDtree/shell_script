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

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

install_dir="${HOME}/software/clash"
url="https://pub-eac3eb5670f44f09984dee5c57939316.r2.dev/clash-linux-amd64-v1.18.0.gz"

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
cd "$install_dir" || exit 1

gz_name=$(basename "${url%%\?*}")
wget -O "$gz_name" "$url" || exit 1
gunzip -f "$gz_name" || exit 1
binary_name="${gz_name%.gz}"
chmod 777 "$binary_name"
