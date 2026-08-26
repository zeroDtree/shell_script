#!/usr/bin/env bash

# @help-begin
# Download an NVIDIA CUDA Toolkit Linux x86_64 runfile and silently install
# the toolkit only (no driver) into a user-writable prefix.
#
# Usage:
#   ./cuda_install.sh --version 11.7.0
#   ./cuda_install.sh -v 12.4
#   ./cuda_install.sh --list
#   ./cuda_install.sh -v 11.7.0 --prefix /datapool/home/ph_teacher2/software/cuda
#
# A major.minor version (for example 12.4) resolves to the latest known patch.
# Runfile URLs follow the NVIDIA CUDA Toolkit Archive:
#   https://developer.download.nvidia.com/compute/cuda/<VERSION>/local_installers/cuda_<VERSION>_<DRIVER>_linux.run
#
# Default prefix:
#   $HOME/shared_software/cuda  if that parent directory exists
#   $HOME/software/cuda         otherwise
#
# Layout:
#   <prefix>/cuda_<VERSION>_<DRIVER>_linux.run
#   <prefix>/cuda-<major>.<minor>/
# @help-end

# @help-options-begin
#   -v, --version VERSION   CUDA version (required unless --list / --help)
#   -p, --prefix PATH       install root (default: ~/shared_software/cuda or ~/software/cuda)
#       --list              print known CUDA versions and exit
#       --url URL           explicit runfile URL (for versions not in the table)
#       --force             reinstall even if nvcc already exists
#       --tmpdir PATH       installer temp directory (default: <prefix>/.cuda-tmp)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

# Linux x86_64 runfile driver versions (newest patch first per major.minor).
# Sourced from Spack's cuda package plus CUDA 13.3.1.
cuda_version_table() {
  cat <<'EOF'
13.3.1 610.43.02
13.3.0 610.43.02
13.2.1 595.58.03
13.2.0 595.45.04
13.1.2 590.48.01
13.1.1 590.48.01
13.1.0 590.44.01
13.0.2 580.95.05
13.0.1 580.82.07
13.0.0 580.65.06
12.9.1 575.57.08
12.9.0 575.51.03
12.8.1 570.124.06
12.8.0 570.86.10
12.6.3 560.35.05
12.6.2 560.35.03
12.6.1 560.35.03
12.6.0 560.28.03
12.5.1 555.42.06
12.5.0 555.42.02
12.4.1 550.54.15
12.4.0 550.54.14
12.3.2 545.23.08
12.3.1 545.23.08
12.3.0 545.23.06
12.2.2 535.104.05
12.2.1 535.86.10
12.2.0 535.54.03
12.1.1 530.30.02
12.1.0 530.30.02
12.0.1 525.85.12
12.0.0 525.60.13
11.8.0 520.61.05
11.7.1 515.65.01
11.7.0 515.43.04
11.6.2 510.47.03
11.6.1 510.47.03
11.6.0 510.39.01
11.5.2 495.29.05
11.5.1 495.29.05
11.5.0 495.29.05
11.4.4 470.82.01
11.4.3 470.82.01
11.4.2 470.57.02
11.4.1 470.57.02
11.4.0 470.42.01
11.3.1 465.19.01
11.3.0 465.19.01
11.2.2 460.32.03
11.2.1 460.32.03
11.2.0 460.27.04
11.1.1 455.32.00
11.1.0 455.23.05
11.0.3 450.51.06
11.0.2 450.51.05
EOF
}

lookup_driver() {
  awk -v v="$1" '$1 == v { print $2; exit }' <<EOF
$(cuda_version_table)
EOF
}

list_versions() {
  printf '%s\n' 'Known CUDA Toolkit versions (Linux x86_64 runfiles):'
  awk '{ printf "  %-8s  cuda_%s_%s_linux.run\n", $1, $1, $2 }' <<EOF
$(cuda_version_table)
EOF
}

version_in_table() {
  awk -v v="$1" '$1 == v { found = 1 } END { exit !found }' <<EOF
$(cuda_version_table)
EOF
}

# Resolve a table version: exact match, or latest patch for major.minor.
resolve_cuda_version() {
  local requested="$1"
  local resolved

  if version_in_table "${requested}"; then
    printf '%s\n' "${requested}"
    return 0
  fi

  case "${requested}" in
    *.*)
      resolved="$(awk -v majmin="${requested}" '
        {
          n = split($1, a, ".")
          if (n >= 3 && (a[1] "." a[2]) == majmin) { print $1; exit }
        }
      ' <<EOF
$(cuda_version_table)
EOF
)"
      if [ -n "${resolved}" ]; then
        printf '%s\n' "${resolved}"
        return 0
      fi
      ;;
  esac
  return 1
}

major_minor_of() {
  awk -F. '{ print $1 "." $2 }' <<EOF
$1
EOF
}

expand_path() {
  case "$1" in
    "~"|"~/"*) printf '%s\n' "${HOME}${1#\~}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

default_prefix() {
  if [ -d "${HOME}/shared_software" ]; then
    printf '%s\n' "${HOME}/shared_software/cuda"
  else
    printf '%s\n' "${HOME}/software/cuda"
  fi
}

print_env_hints() {
  local toolkit_path="$1"
  printf '%s\n' \
    '' \
    'Add the toolkit to your environment (this script does not edit shell rc files):' \
    "  export PATH=\"${toolkit_path}/bin\${PATH:+:\$PATH}\"" \
    "  export LD_LIBRARY_PATH=\"${toolkit_path}/lib64\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
}

download_runfile() {
  local url="$1"
  local dest="$2"

  echo "Downloading:"
  echo "  ${url}"
  echo "  -> ${dest}"

  if command -v wget >/dev/null 2>&1; then
    wget -c "${url}" -O "${dest}"
  elif command -v curl >/dev/null 2>&1; then
    curl -fL -C - -o "${dest}" "${url}"
  else
    echo "error: need wget or curl to download the CUDA runfile" >&2
    exit 1
  fi

  if [ ! -s "${dest}" ]; then
    echo "error: download produced an empty file: ${dest}" >&2
    exit 1
  fi
}

version=""
prefix=""
list_only=0
runfile_url=""
force=0
tmpdir=""

require_value() {
  if [ "$#" -lt 2 ]; then
    echo "error: $1 requires a value" >&2
    exit 1
  fi
}

# Portable flag parser (no GNU getopt dependency; works with macOS /bin/bash 3.2).
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -v|--version)
      require_value "$@"
      version="$2"
      shift 2
      ;;
    -p|--prefix)
      require_value "$@"
      prefix="$2"
      shift 2
      ;;
    --list)
      list_only=1
      shift
      ;;
    --url)
      require_value "$@"
      runfile_url="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --tmpdir)
      require_value "$@"
      tmpdir="$2"
      shift 2
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

if [ "${list_only}" -eq 1 ]; then
  list_versions
  exit 0
fi

if [ -z "${version}" ]; then
  echo "error: --version is required (see --help or --list)" >&2
  exit 1
fi

if ! printf '%s' "${version}" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  echo "error: invalid CUDA version: ${version}" >&2
  echo "expected major.minor or major.minor.patch, for example 11.7 or 11.7.0" >&2
  exit 1
fi

if [ -z "${prefix}" ]; then
  prefix="$(default_prefix)"
fi
prefix="$(expand_path "${prefix}")"

if [ -z "${tmpdir}" ]; then
  tmpdir="${prefix}/.cuda-tmp"
fi
tmpdir="$(expand_path "${tmpdir}")"

resolved_version="${version}"
driver=""

if [ -n "${runfile_url}" ]; then
  # --url bypasses the version table; --version is only used for the toolkit path.
  resolved_version="${version}"
else
  if ! resolved_version="$(resolve_cuda_version "${version}")"; then
    echo "error: unknown CUDA version: ${version}" >&2
    echo "use --list to see known versions, or pass --url for an explicit runfile" >&2
    exit 1
  fi
  if [ "${resolved_version}" != "${version}" ]; then
    echo "Resolved CUDA ${version} -> ${resolved_version}"
  fi
  driver="$(lookup_driver "${resolved_version}")"
  if [ -z "${driver}" ]; then
    echo "error: no runfile mapping for CUDA ${resolved_version}" >&2
    exit 1
  fi
  runfile_url="https://developer.download.nvidia.com/compute/cuda/${resolved_version}/local_installers/cuda_${resolved_version}_${driver}_linux.run"
fi

runfile_name="$(basename "${runfile_url%%\?*}")"
case "${runfile_name}" in
  *.run) ;;
  *)
    echo "error: URL does not look like a CUDA runfile: ${runfile_url}" >&2
    exit 1
    ;;
esac

major_minor="$(major_minor_of "${resolved_version}")"
toolkit_path="${prefix}/cuda-${major_minor}"
runfile_path="${prefix}/${runfile_name}"

if [ "$(uname -s)" != "Linux" ]; then
  echo "error: this installer only supports Linux x86_64 runfiles (OS: $(uname -s))" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "error: this installer only supports Linux x86_64 (arch: $(uname -m))" >&2
    exit 1
    ;;
esac

echo "CUDA Toolkit install"
echo "  version:  ${resolved_version}"
echo "  prefix:   ${prefix}"
echo "  toolkit:  ${toolkit_path}"
echo "  runfile:  ${runfile_path}"
echo "  tmpdir:   ${tmpdir}"

if [ -x "${toolkit_path}/bin/nvcc" ] && [ "${force}" -eq 0 ]; then
  echo "CUDA toolkit already installed at ${toolkit_path} (pass --force to reinstall)"
  "${toolkit_path}/bin/nvcc" --version || true
  print_env_hints "${toolkit_path}"
  exit 0
fi

mkdir -p "${prefix}" "${tmpdir}"

if [ -s "${runfile_path}" ]; then
  echo "Runfile already present; resuming or verifying with wget/curl -c"
fi
download_runfile "${runfile_url}" "${runfile_path}"

echo "Installing toolkit (silent, no driver, --override)..."
bash "${runfile_path}" \
  --silent \
  --toolkit \
  --toolkitpath="${toolkit_path}" \
  --override \
  --tmpdir="${tmpdir}"

if [ ! -x "${toolkit_path}/bin/nvcc" ]; then
  echo "error: install finished but nvcc was not found at ${toolkit_path}/bin/nvcc" >&2
  echo "see /tmp/cuda-installer.log if it exists" >&2
  exit 1
fi

echo "Installed: ${toolkit_path}/bin/nvcc"
"${toolkit_path}/bin/nvcc" --version || true
print_env_hints "${toolkit_path}"
