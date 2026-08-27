#!/usr/bin/env bash

# @help-begin
# Canonical portable-parser demo template for CLI shell scripts.
#
# Usage:
#   ./template.sh [options] [positional...]
#
# Demonstrates short/long flags, required values, and optional values.
# Does not require GNU getopt (works with macOS /bin/bash 3.2).
# @help-end

# @help-options-begin
#   -a, --aa                demo flag (no value)
#   -b, --bb VALUE          demo option with required value
#   -c, --cc [VALUE]        demo option with optional value
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

case "${1:-}" in
  -h|--help) usage ;;
esac

echo "origin_parameters=<$*>"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -a|--aa)
      echo "option: $1"
      shift
      ;;
    -b|--bb)
      require_value "$@"
      echo "option $1=$2"
      shift 2
      ;;
    -c|--cc)
      if [ "$#" -ge 2 ] && [ "${2#-}" = "$2" ]; then
        echo "option $1=$2"
        shift 2
      else
        echo "option $1="
        shift
      fi
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unrecognized option: $1"
      ;;
    *)
      break
      ;;
  esac
done
echo "positional parameters=<$*>"

echo "$0 start======================================="

echo "$0 end========================================="
