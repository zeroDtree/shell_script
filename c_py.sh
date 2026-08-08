#!/usr/bin/env bash

# @help-begin
# Build and install a local Python source tree into /usr/local/software.
#
# Usage:
#   ./c_py.sh <version>
#
# Expects a directory named Python-<version> in the current working directory.
# Installs to /usr/local/software/python-<version>.
#
# Example:
#   ./c_py.sh 3.12.0
# @help-end

# @help-options-begin
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

[[ $# -ge 1 ]] || usage
case "${1:-}" in
  -h|--help) usage ;;
esac

version=$1
cd Python-$version
sudo rm -rf /usr/local/software/python-$version
./configure --prefix=/usr/local/software/python-$version
sudo make
sudo make install
