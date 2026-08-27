#!/usr/bin/env bash

# @help-begin
# Install a personal Ubuntu package set (dev tools, HPC libs, utilities).
# Not a profile-based installer; edit the lists below to taste.
#
# Usage:
#   ./apt_install.sh
#
# Requires sudo. The fish PPA step needs add-apt-repository
# (package software-properties-common).
# @help-end

# @help-options-begin
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -*)
      die "unrecognized option: $1"
      ;;
    *)
      die "Unexpected arguments: $*"
      ;;
  esac
done

sudo apt update

# 1. Basic system tools (networking, editors, terminal multiplexers)
sudo apt install -y \
    wget curl git git-lfs vim ssh openssh-server \
    fish zsh tmux screen tree parallel \
    dos2unix enca patchelf

# 2. Build and development toolchain (C++, Rust, Python, Go tooling, etc.)
sudo apt install -y \
    build-essential cmake autoconf make \
    gcc g++ python3-dev cargo rustc \
    libboost-all-dev libarchive-dev libxml2-dev libgmp-dev zlib1g-dev

# 3. High-performance computing (HPC) and math libraries (research/simulation)
sudo apt install -y \
    libblas-dev liblapack-dev libfftw3-dev \
    libscalapack-mpi-dev mpi-default-dev libopenmpi-dev \
    libxc-dev libnetcdf-dev libmsgpack-dev libspatialindex-dev

# 4. Bioinformatics, chemistry, and 3D visualization
sudo apt install -y \
    ncbi-blast+ clustalo openbabel \
    pymol clinfo

# 5. System monitoring, stress testing, and GPU tools
sudo apt install -y \
    htop btop nvtop stress \
    graphviz dkms

# 6. Downloads, proxies, and remote connectivity
# Note: v2raya and gsutil usually need an extra PPA or repo; this section covers basic packages only
sudo apt install -y \
    aria2 axel proxychains4 openvpn \
    mutt msmtp

# 7. Compression, filesystem tools, and multimedia
sudo apt install -y \
    unrar p7zip-full rar zip \
    gparted xfsprogs uidmap extundelete \
    ffmpeg mplayer \
    libglm-dev libglew-dev libpng-dev libfreetype6-dev

# 8. Clipboard and selection tools
sudo apt install -y xclip xsel

have_cmd add-apt-repository || die "add-apt-repository not found; install software-properties-common"

sudo apt-get remove -y fish fish-common
sudo add-apt-repository ppa:fish-shell/release-4
sudo apt update
sudo apt install -y fish
