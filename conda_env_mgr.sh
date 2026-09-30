#!/usr/bin/env bash

# @help-begin
# Pack a conda environment with conda-pack, or unpack that archive on
# another machine and run conda-unpack.
#
# Usage:
#   ./conda_env_mgr.sh --pack [options]
#   ./conda_env_mgr.sh --unpack [options]
#
# Omit --name with --pack to pack the active environment.
# The archive is NAME.tar.gz, or conda-env.tar.gz when no name is given.
# conda-pack is a separate program. This script never runs "conda pack".
# Copy the archive to the target machine yourself, then unpack it there.
#
# Example:
#   ./conda_env_mgr.sh --pack --name NAME --output my_env.tar.gz
#   ./conda_env_mgr.sh --unpack --name NAME --archive my_env.tar.gz --prefix ~/miniconda3
# @help-end

# @help-options-begin
#   -n, --name NAME     environment to pack or unpack (default: active environment)
#   -o, --output FILE   pack archive path (default: NAME.tar.gz or conda-env.tar.gz)
#   -a, --archive FILE  archive to unpack
#       --pack          pack an environment into an archive
#       --unpack        unpack an archive into a conda environment
#   -p, --prefix PATH   conda installation prefix (default: conda info --base)
#       --force         overwrite an existing archive or environment directory
#       --dry-run       print commands without running them
#   -h, --help          show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

ENV_NAME=""
OUTPUT=""
ARCHIVE=""
PREFIX=""
DO_PACK=0
DO_UNPACK=0
FORCE=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--name|-o|--output|-a|--archive|-p|--prefix)
      require_value "$@"
      case "$2" in
        -*) die "$1 requires a value" ;;
      esac
      case "$1" in
        -n|--name) ENV_NAME="$2" ;;
        -o|--output) OUTPUT="$2" ;;
        -a|--archive) ARCHIVE="$2" ;;
        -p|--prefix) PREFIX="$2" ;;
      esac
      shift 2
      ;;
    --pack)
      DO_PACK=1
      shift
      ;;
    --unpack)
      DO_UNPACK=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unrecognized option: $1 (try --help)"
      ;;
    *)
      die "unexpected argument: $1 (try --help)"
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  die "unexpected argument: $1 (try --help)"
fi

missing_conda_pack() {
  printf '%s\n' "error: conda-pack is not installed" >&2
  printf '%s\n' "Install it with one of:" >&2
  printf '%s\n' "  pip install conda-pack" >&2
  printf '%s\n' "  conda install -c conda-forge conda-pack" >&2
  exit 1
}

validate_env_name() {
  local name="$1"
  case "$name" in
    ""|.|..|-*|*/|*/*)
      die "invalid environment name: ${name}"
      ;;
    *[!A-Za-z0-9._-]*)
      die "invalid environment name: ${name}"
      ;;
  esac
}

resolve_packer() {
  local py
  if have_cmd conda-pack; then
    PACK_CMD=(conda-pack)
    return 0
  fi
  for py in python python3; do
    if have_cmd "$py" && "$py" -c 'import conda_pack' >/dev/null 2>&1; then
      PACK_CMD=("$py" -m conda_pack)
      return 0
    fi
  done
  missing_conda_pack
}

resolve_prefix() {
  local base candidate
  if [ -n "$PREFIX" ]; then
    expand_path "$PREFIX"
    return 0
  fi
  if have_cmd conda; then
    base="$(conda info --base 2>/dev/null | head -n 1 | tr -d '\r' || true)"
    if [ -n "$base" ] && [ -d "$base" ]; then
      printf '%s\n' "$base"
      return 0
    fi
  fi
  for candidate in "${HOME}/miniconda3" "${HOME}/anaconda3"; do
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  die "conda prefix not found; pass --prefix"
}

do_pack() {
  local out_dir hint_name
  if [ -n "$ENV_NAME" ]; then
    validate_env_name "$ENV_NAME"
  elif [ -z "${CONDA_PREFIX:-}" ]; then
    die "no active conda environment; pass --name"
  fi
  if [ -z "$OUTPUT" ]; then
    if [ -n "$ENV_NAME" ]; then
      OUTPUT="${ENV_NAME}.tar.gz"
    else
      OUTPUT="conda-env.tar.gz"
    fi
  fi
  OUTPUT="$(expand_path "$OUTPUT")"
  case "$OUTPUT" in
    */|.)
      die "output path is a directory: ${OUTPUT}"
      ;;
  esac
  out_dir="$(dirname -- "$OUTPUT")"
  if [ ! -d "$out_dir" ]; then
    die "output directory does not exist: ${out_dir}"
  fi
  if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
    if [ "$FORCE" -ne 1 ]; then
      die "archive already exists: ${OUTPUT}"
    fi
  fi

  resolve_packer
  PACK_ARGS=("${PACK_CMD[@]}")
  if [ -n "$ENV_NAME" ]; then
    PACK_ARGS+=(-n "$ENV_NAME")
  fi
  PACK_ARGS+=(-o "$OUTPUT")
  if [ "$FORCE" -eq 1 ]; then
    PACK_ARGS+=(--force)
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Dry run:"
    print_cmd "${PACK_ARGS[@]}"
    exit 0
  fi

  info "Packing:"
  info "  -> ${OUTPUT}"
  "${PACK_ARGS[@]}"
  info "Archive ready: ${OUTPUT}"
  info "Copy it to the target machine, then unpack:"
  if [ -n "$ENV_NAME" ]; then
    hint_name="$ENV_NAME"
  elif [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
    hint_name="${CONDA_DEFAULT_ENV}"
  else
    hint_name="ENV"
  fi
  info "  ${0} --unpack --name ${hint_name} --archive ${OUTPUT} --prefix ~/miniconda3"
}

do_unpack() {
  local envs_dir
  validate_env_name "$ENV_NAME"
  ARCHIVE="$(expand_path "$ARCHIVE")"
  if [ ! -f "$ARCHIVE" ]; then
    die "archive does not exist: ${ARCHIVE}"
  fi
  PREFIX="$(resolve_prefix)"
  PREFIX="$(strip_trailing_slashes "$PREFIX")"
  if [ ! -d "$PREFIX" ]; then
    die "conda prefix does not exist: ${PREFIX}"
  fi
  case "$PREFIX" in
    /*) ;;
    *) die "conda prefix is not absolute: ${PREFIX}" ;;
  esac

  envs_dir="${PREFIX}/envs"
  DEST="${envs_dir}/${ENV_NAME}"
  case "$DEST" in
    "${envs_dir}/"*) ;;
    *) die "refusing destination: ${DEST}" ;;
  esac

  if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    if [ "$FORCE" -ne 1 ]; then
      die "environment directory already exists: ${DEST}"
    fi
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Dry run:"
    if [ -e "$DEST" ] || [ -L "$DEST" ]; then
      print_cmd rm -rf -- "$DEST"
    fi
    print_cmd mkdir -p -- "$DEST"
    print_cmd tar -xzf "$ARCHIVE" -C "$DEST"
    print_cmd "${DEST}/bin/python" "${DEST}/bin/conda-unpack"
    exit 0
  fi

  if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    rm -rf -- "$DEST"
  fi

  info "Unpacking:"
  info "  ${ARCHIVE}"
  info "  -> ${DEST}"
  mkdir -p -- "$DEST"
  tar -xzf "$ARCHIVE" -C "$DEST"
  if [ ! -x "${DEST}/bin/python" ] || [ ! -f "${DEST}/bin/conda-unpack" ]; then
    die "unpacked environment is missing bin/python or bin/conda-unpack: ${DEST}"
  fi
  "${DEST}/bin/python" "${DEST}/bin/conda-unpack"
  info "Environment ready: ${DEST}"
  info "Check it with:"
  info "  ${DEST}/bin/python -c 'import sys; print(sys.prefix)'"
  info "  conda list -p ${DEST}"
}

if [ "$DO_PACK" -eq 1 ] && [ "$DO_UNPACK" -eq 1 ]; then
  die "pass only one of --pack or --unpack (try --help)"
fi
if [ "$DO_PACK" -eq 0 ] && [ "$DO_UNPACK" -eq 0 ]; then
  usage
fi

if [ "$DO_UNPACK" -eq 1 ]; then
  if [ -n "$OUTPUT" ]; then
    die "--output is only used when packing (try --help)"
  fi
  if [ -z "$ENV_NAME" ] || [ -z "$ARCHIVE" ]; then
    usage
  fi
  do_unpack
else
  if [ -n "$ARCHIVE" ]; then
    die "--archive is only used with --unpack (try --help)"
  fi
  if [ -n "$PREFIX" ]; then
    die "--prefix is only used with --unpack (try --help)"
  fi
  do_pack
fi
