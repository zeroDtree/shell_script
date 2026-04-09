#!/bin/bash

install_dir="${HOME}/software/clash"
url="https://pub-eac3eb5670f44f09984dee5c57939316.r2.dev/clash-linux-amd64-v1.18.0.gz"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Download Clash .gz into a directory, gunzip, and chmod.

Options:
  -d, --dir PATH     Install directory (default: ~/software/clash)
  -u, --url URL      Download URL (default: clash-linux-amd64 v1.18.0)
  -h, --help         Show this help
EOF
}

ARGS=$(getopt --options="d:u:h" --longoptions="dir:,url:,help" -- "$@")
if [ $? -ne 0 ]; then
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
            exit 0
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
