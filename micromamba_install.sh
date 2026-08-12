#!/usr/bin/env bash

# @help-begin
# Download micromamba from GitHub releases, optionally init shells, and
# pin conda-forge as the default channel.
#
# Usage:
#   ./micromamba_install.sh [options]
#
# If no options are passed, the default behavior is equivalent to:
#   ./micromamba_install.sh --bin-dir ~/.local/bin --root-prefix ~/.local/share/mamba
#
# After install, restart your shell (or source its rc file), then e.g.:
#   micromamba create -n test python=3.12
#   micromamba activate test
# @help-end

# @help-options-begin
#   -b, --bin-dir PATH      micromamba binary directory (default: ~/.local/bin)
#   -r, --root-prefix PATH  MAMBA_ROOT_PREFIX (default: ~/.local/share/mamba)
#   -v, --version VERSION   release tag (default: latest)
#   -s, --shells LIST       comma-separated shells to init (default: auto-detect
#                           bash,zsh,fish via command -v)
#       --no-conda-forge    skip pinning conda-forge / nodefaults / strict
#       --no-init           skip micromamba shell init
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

bin_dir="${HOME}/.local/bin"
root_prefix="${HOME}/.local/share/mamba"
version=""
shells_arg=""
do_conda_forge=1
do_init=1

# Portable flag parser (no GNU getopt dependency; works with macOS /bin/bash 3.2).
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -b|--bin-dir)
      if [ "$#" -lt 2 ]; then
        echo "error: $1 requires a value" >&2
        exit 1
      fi
      bin_dir="$2"
      shift 2
      ;;
    -r|--root-prefix)
      if [ "$#" -lt 2 ]; then
        echo "error: $1 requires a value" >&2
        exit 1
      fi
      root_prefix="$2"
      shift 2
      ;;
    -v|--version)
      if [ "$#" -lt 2 ]; then
        echo "error: $1 requires a value" >&2
        exit 1
      fi
      version="$2"
      shift 2
      ;;
    -s|--shells)
      if [ "$#" -lt 2 ]; then
        echo "error: $1 requires a value" >&2
        exit 1
      fi
      shells_arg="$2"
      shift 2
      ;;
    --no-conda-forge)
      do_conda_forge=0
      shift
      ;;
    --no-init)
      do_init=0
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unrecognized option: $1" >&2
      exit 1
      ;;
    *)
      echo "Unexpected arguments: $*" >&2
      exit 1
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  echo "Unexpected arguments: $*" >&2
  exit 1
fi

# Expand leading ~ in paths (CLI args may leave them literal).
expand_path() {
  case "$1" in
    "~"|"~/"*) printf '%s\n' "${HOME}${1#\~}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

bin_dir="$(expand_path "${bin_dir}")"
root_prefix="$(expand_path "${root_prefix}")"

detect_platform_arch() {
  local platform arch
  case "$(uname)" in
    Linux) platform="linux" ;;
    Darwin) platform="osx" ;;
    *NT*) platform="win" ;;
    *)
      echo "error: unsupported OS: $(uname)" >&2
      exit 1
      ;;
  esac

  arch="$(uname -m)"
  case "${arch}" in
    aarch64|ppc64le|arm64) ;;
    *) arch="64" ;;
  esac

  # Windows uses win-arm64 (not win-aarch64)
  if [ "${platform}" = "win" ] && [ "${arch}" = "aarch64" ]; then
    arch="arm64"
  fi

  case "${platform}-${arch}" in
    linux-aarch64|linux-ppc64le|linux-64|osx-arm64|osx-64|win-64|win-arm64) ;;
    *)
      echo "error: unsupported platform/arch: ${platform}-${arch}" >&2
      exit 1
      ;;
  esac

  printf '%s %s\n' "${platform}" "${arch}"
}

platform_arch="$(detect_platform_arch)"
platform="${platform_arch%% *}"
arch="${platform_arch#* }"

if [ -n "${version}" ]; then
  release_url="https://github.com/mamba-org/micromamba-releases/releases/download/${version}/micromamba-${platform}-${arch}"
else
  release_url="https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-${platform}-${arch}"
fi

mkdir -p "${bin_dir}"
micromamba_bin="${bin_dir}/micromamba"

echo "Downloading micromamba (${platform}-${arch}) from:"
echo "  ${release_url}"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL --compressed "${release_url}" -o "${micromamba_bin}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${micromamba_bin}" "${release_url}"
else
  echo "error: need curl or wget to download micromamba" >&2
  exit 1
fi

chmod +x "${micromamba_bin}"

if [ ! -x "${micromamba_bin}" ]; then
  echo "error: micromamba binary not found after install: ${micromamba_bin}" >&2
  exit 1
fi

echo "Installed micromamba: ${micromamba_bin}"
echo "  version: $("${micromamba_bin}" --version)"

# Populate target_shells array (bash 3.2 compatible; no mapfile).
target_shells=()
if [ -n "${shells_arg}" ]; then
  _shells_csv="${shells_arg},"
  while [ -n "${_shells_csv}" ]; do
    shell="${_shells_csv%%,*}"
    _shells_csv="${_shells_csv#*,}"
    shell="$(printf '%s' "${shell}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "${shell}" ]; then
      target_shells+=("${shell}")
    fi
  done
  unset _shells_csv
else
  for candidate in bash zsh fish; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      target_shells+=("${candidate}")
    fi
  done
fi

shell_rc_hint() {
  case "$1" in
    bash) printf '%s\n' "source ~/.bashrc" ;;
    zsh) printf '%s\n' "source ~/.zshrc" ;;
    fish) printf '%s\n' "source ~/.config/fish/config.fish" ;;
    xonsh) printf '%s\n' "source ~/.xonshrc" ;;
    *) printf '%s\n' "restart your ${1} shell (or source its rc file)" ;;
  esac
}

initialized_shells=()

if [ "${do_init}" -eq 1 ]; then
  if [ "${#target_shells[@]}" -eq 0 ]; then
    echo "warning: no shells found to initialize (bash/zsh/fish missing from PATH)" >&2
  else
    for shell in "${target_shells[@]}"; do
      echo "Initializing shell: ${shell}"
      "${micromamba_bin}" shell init --shell "${shell}" --root-prefix "${root_prefix}"
      initialized_shells+=("${shell}")
    done
  fi
else
  echo "Skipping shell init (--no-init)."
fi

if [ "${do_conda_forge}" -eq 1 ]; then
  echo "Configuring conda-forge as the default channel..."
  # Write root-prefix .mambarc (not ~/.condarc) so we do not disturb miniconda/conda
  # user config. empty default_channels + nodefaults blocks Anaconda pkgs/main even
  # when ~/.condarc still lists "defaults".
  mkdir -p "${root_prefix}"
  cat > "${root_prefix}/.mambarc" <<'EOF'
channels:
  - conda-forge
  - nodefaults
channel_priority: strict
default_channels: []
EOF
  echo "  wrote ${root_prefix}/.mambarc"
else
  echo "Skipping conda-forge channel pin (--no-conda-forge)."
fi

echo
echo "========================================"
echo "micromamba install summary"
echo "========================================"
echo "  binary:      ${micromamba_bin}"
echo "  root-prefix: ${root_prefix}"
echo "  platform:    ${platform}-${arch}"
if [ "${do_conda_forge}" -eq 1 ]; then
  echo "  channels:    conda-forge (strict), nodefaults"
else
  echo "  channels:    (unchanged / defaults)"
fi

if [ "${do_init}" -eq 1 ]; then
  if [ "${#initialized_shells[@]}" -gt 0 ]; then
    echo "  shells:      ${initialized_shells[*]}"
    echo
    echo "Restart your shell, or run the matching command for your current shell:"
    for shell in "${initialized_shells[@]}"; do
      echo "  ${shell}: $(shell_rc_hint "${shell}")"
    done
  else
    echo "  shells:      (none initialized)"
    echo
    echo "You can initialize a shell later with:"
    echo "  ${micromamba_bin} shell init --shell bash --root-prefix ${root_prefix}"
  fi
else
  echo "  shells:      (skipped)"
  echo
  echo "You can initialize a shell later with:"
  echo "  ${micromamba_bin} shell init --shell bash --root-prefix ${root_prefix}"
fi

echo
echo "Example (after shell restart / source):"
echo "  micromamba create -n test python=3.12"
echo "  micromamba activate test"
echo "========================================"
