#!/usr/bin/env bash

# @help-begin
# Canonical getopt demo template for CLI shell scripts.
#
# Usage:
#   ./template.sh [options] [positional...]
#
# Demonstrates short/long flags, required values, and optional values.
# @help-end

# @help-options-begin
#   -a, --aa                demo flag (no value)
#   -b, --bb VALUE          demo option with required value
#   -c, --cc [VALUE]        demo option with optional value
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

case "${1:-}" in
  -h|--help) usage ;;
esac

echo "origin_paramters=<$@>"
if ! ARGS=$(getopt --options="ab:c::h" --longoptions="aa,bb:,cc::,help" -- "$@"); then
  echo "Failed to parse arguments." >&2
  exit 1
fi
echo "after_getopt_parameters=<$ARGS>"
eval set -- "${ARGS}"
while true
do
        case "$1" in
                -a|--aa)
                        echo "option: $1"
                        shift
                        ;;
                -b|--bb)
                        echo "option $1=$2"
                        shift 2
                        ;;
                -c|--cc)
                        echo "option $1=$2"
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
                        echo "unrecognized option: $1"
                        break
                        ;;
        esac
done
echo "positional parameters=<$@>"

echo "$0 start======================================="

echo "$0 end========================================="
