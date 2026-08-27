#!/usr/bin/env bash

# @help-begin
# Check the frpc connection to the FRP server and restart frpc if needed.
#
# Usage:
#   ./frp_auto_restart.sh -i SERVER_IP [options]
#
# Defaults when omitted:
#   --server_port 7000
#   --frp_home ~/.local/frp
#   --log_path $frp_home/log.txt
# @help-end

# @help-options-begin
#   -i, --server_ip IP      FRP server IP (required)
#   -p, --server_port PORT  FRP server port (default: 7000)
#   -f, --frp_home PATH     frpc home directory (default: ~/.local/frp)
#   -l, --log_path PATH     restart log file (default: $frp_home/log.txt)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

server_port="7000"
frp_home="${HOME}/.local/frp"
log_path=""
server_ip=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -i|--server_ip)
      require_value "$@"
      server_ip="$2"
      shift 2
      ;;
    -p|--server_port)
      require_value "$@"
      server_port="$2"
      shift 2
      ;;
    -f|--frp_home)
      require_value "$@"
      frp_home="$2"
      shift 2
      ;;
    -l|--log_path)
      require_value "$@"
      log_path="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unrecognized option: $1"
      ;;
    *)
      die "Unexpected arguments: $*"
      ;;
  esac
done

if [ "$#" -gt 0 ]; then
  die "Unexpected arguments: $*"
fi

[ -n "$server_ip" ] || usage

frp_home="$(expand_path "${frp_home}")"
if [ -z "${log_path}" ]; then
  log_path="${frp_home}/log.txt"
else
  log_path="$(expand_path "${log_path}")"
fi

[ -x "${frp_home}/frpc" ] || die "frpc not found: ${frp_home}/frpc"
[ -f "${frp_home}/frpc.toml" ] || die "config not found: ${frp_home}/frpc.toml"

echo "server_ip=$server_ip"
echo "server_port=$server_port"
echo "frp_home=$frp_home"
echo "log_path=$log_path"

check_connection() {
  if have_cmd ss; then
    ss -tn 2>/dev/null | grep ESTAB | grep -q "${server_ip}:${server_port}" && return 0
    return 1
  fi
  if have_cmd nc; then
    nc -z -w 2 "${server_ip}" "${server_port}" >/dev/null 2>&1 && return 0
    return 1
  fi
  die "need ss or nc to check the FRP connection"
}

check_process() {
  pgrep -x frpc >/dev/null 2>&1
}

restart_frpc() {
  local log_dir
  log_dir="$(dirname "${log_path}")"
  mkdir -p "${log_dir}"
  (
    cd "${frp_home}" || exit 1
    nohup ./frpc -c ./frpc.toml >> "${log_path}" 2>&1 &
  )
  echo "Restarted frpc at $(date)" >> "${log_path}"
}

if check_connection; then
  echo "Connection is alive."
  exit 0
fi

echo "No established connection, restarting frpc..."
if check_process; then
  pkill -x frpc || true
  sleep 1
fi
restart_frpc
