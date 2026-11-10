#!/usr/bin/env bash

# @help-begin
# Open an SSH remote forward from a server to the local Clash proxy.
#
# Usage:
#   ./clash-tunnel.sh -s USER@HOST [options] [up|down|status]
#
# The server listens on 127.0.0.1 and an ephemeral port. The allocated
# port is written to the remote port file (mode 600).
# Running up again reuses that port while the forward is still listening.
#
# Env: CLASH_PORT_FILE — remote path that stores the allocated port.
#   A leading ~ is the remote user's home. Example:
#   CLASH_PORT_FILE=~/.config/clash-proxy-port ./clash-tunnel.sh -s USER@HOST
#
# Commands:
#   up                 open the tunnel, or reuse it (default)
#   down               cancel the forward and close the control connection
#   status             show the control connection, saved port, and listener
#
# If no command is passed, the default behavior is equivalent to:
#   ./clash-tunnel.sh -s USER@HOST up
#
# Defaults when omitted:
#   --local_port 7890
#   --port_file ~/.config/clash-proxy-port
# @help-end

# @help-options-begin
#   -s, --server USER@HOST  SSH destination (required)
#   -p, --local_port PORT   local Clash port (default: 7890)
#   -f, --port_file PATH    remote port file (default: ~/.config/clash-proxy-port)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

local_port="7890"
port_file="${CLASH_PORT_FILE:-~/.config/clash-proxy-port}"
server=""
command=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -s|--server)
      require_value "$@"
      server="$2"
      shift 2
      ;;
    -p|--local_port)
      require_value "$@"
      local_port="$2"
      shift 2
      ;;
    -f|--port_file)
      require_value "$@"
      port_file="$2"
      shift 2
      ;;
    up|down|status)
      if [ -n "${command}" ]; then
        die "unexpected command: $1"
      fi
      command="$1"
      shift
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

[ -n "${server}" ] || usage
[ -n "${command}" ] || command="up"

case "${server}" in
  *[[:space:]]*)
    die "server must look like USER@HOST"
    ;;
  *@*@*|*@|@*)
    die "server must look like USER@HOST"
    ;;
  *@*)
    ;;
  *)
    die "server must look like USER@HOST"
    ;;
esac

valid_port() {
  local port="${1:-}"
  local number_re='^[1-9][0-9]{0,4}$'

  [[ "${port}" =~ ${number_re} ]] || return 1
  if (( 10#${port} >= 1 && 10#${port} <= 65535 )); then
    return 0
  fi
  return 1
}

valid_port "${local_port}" || die "local port must be an integer from 1 to 65535"
case "${port_file}" in
  ""|*$'\n'*) die "port file path must be a single non-empty line" ;;
esac

[ -n "${HOME:-}" ] || die "HOME is not set"
have_cmd ssh || die "need ssh"
have_cmd cksum || die "need cksum"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

socket_sum="$(printf '%s' "${server}" | cksum)"
socket_sum="${socket_sum%% *}"
socket="${HOME}/.ssh/clash-proxy-${socket_sum}.sock"

ssh_common_opts=(
  -o ExitOnForwardFailure=yes
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ConnectTimeout=15
  -o RemoteCommand=none
  -o RequestTTY=no
)
ssh_opts=(
  "${ssh_common_opts[@]}"
  -o ControlMaster=auto
  -o ControlPersist=yes
)

ssh_mux() {
  ssh -S "${socket}" "${ssh_opts[@]}" "$@"
}

ssh_once() {
  ssh "${ssh_common_opts[@]}" \
    -o ControlMaster=no \
    -o ControlPersist=no \
    "$@"
}

master_alive() {
  ssh -S "${socket}" -O check "${server}" >/dev/null 2>&1
}

ensure_master() {
  if master_alive; then
    return 0
  fi
  rm -f "${socket}"
  ssh -M -S "${socket}" -fNT \
    "${ssh_common_opts[@]}" \
    -o ControlMaster=yes \
    -o ControlPersist=yes \
    "${server}" || die "failed to open the SSH control connection to ${server}"
}

# First stdin line is the remote port-file path. ~ and ~/ expand there.
port_file_setup='IFS= read -r port_file || exit 1
case "$port_file" in
  "~") port_file="$HOME" ;;
  "~/"*) port_file="$HOME/${port_file#"~/"}" ;;
esac
'

ssh_port_file() {
  local runner="$1"
  local remote_body="$2"
  local extra="${3-}"
  local remote_cmd="${port_file_setup}${remote_body}"

  if [ "${runner}" = "mux" ]; then
    {
      printf '%s\n' "${port_file}"
      if [ -n "${extra}" ]; then
        printf '%s\n' "${extra}"
      fi
    } | ssh_mux "${server}" "${remote_cmd}"
  else
    {
      printf '%s\n' "${port_file}"
      if [ -n "${extra}" ]; then
        printf '%s\n' "${extra}"
      fi
    } | ssh_once "${server}" "${remote_cmd}"
  fi
}

fetch_remote_port() {
  local runner="$1"
  local raw line

  raw="$(ssh_port_file "${runner}" 'cat "$port_file" 2>/dev/null || true')" || return 1
  line="${raw%%$'\n'*}"
  trim "${line}"
}

remote_listening() {
  local port="$1"
  local runner="${2:-mux}"
  local probe="bash -c 'echo >/dev/tcp/127.0.0.1/${port}'"

  if [ "${runner}" = "mux" ]; then
    ssh_mux "${server}" "${probe}" >/dev/null 2>&1
  else
    ssh_once "${server}" "${probe}" >/dev/null 2>&1
  fi
}

parse_allocated_port() {
  local raw="$1"
  local line trimmed port=""
  local digits_re='^[0-9]+$'
  local allocated_re='^Allocated port ([0-9]+) for( mux)? remote forward to .+'

  while IFS= read -r line || [ -n "${line}" ]; do
    trimmed="$(trim "${line}")"
    if [[ "${trimmed}" =~ ${digits_re} ]]; then
      port="${trimmed}"
    elif [[ "${trimmed}" =~ ${allocated_re} ]]; then
      port="${BASH_REMATCH[1]}"
    fi
  done <<< "${raw}"

  valid_port "${port}" || return 1
  printf '%s\n' "${port}"
}

write_remote_port() {
  ssh_port_file mux \
    'mkdir -p "$(dirname "$port_file")" && cat > "$port_file" && chmod 600 "$port_file"' \
    "$1" || die "failed to write the remote port file"
}

cancel_forward() {
  local port="$1"
  ssh_mux -O cancel \
    -R "127.0.0.1:${port}:127.0.0.1:${local_port}" \
    "${server}" >/dev/null 2>&1 || true
}

warn_local_listener() {
  if have_cmd nc; then
    if nc -z -G 1 127.0.0.1 "${local_port}" >/dev/null 2>&1; then
      return 0
    fi
    if nc -z -w 1 127.0.0.1 "${local_port}" >/dev/null 2>&1; then
      return 0
    fi
  elif have_cmd lsof; then
    if lsof -nP -iTCP:"${local_port}" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
  else
    return 0
  fi
  warn "nothing is listening on 127.0.0.1:${local_port}; the tunnel connects to Clash only when the server uses the remote port"
}

print_tunnel() {
  info "Clash tunnel is up."
  info "local port: ${local_port}"
  info "remote port: $1"
  info "port file: ${port_file}"
}

cmd_up() {
  local port output

  warn_local_listener
  if master_alive; then
    port="$(fetch_remote_port mux)" || die "failed to read the remote port file"
    if valid_port "${port}" && remote_listening "${port}"; then
      print_tunnel "${port}"
      return 0
    fi
    if valid_port "${port}"; then
      cancel_forward "${port}"
    fi
  else
    ensure_master
  fi

  if ! output="$(ssh_mux -O forward -R "127.0.0.1:0:127.0.0.1:${local_port}" "${server}" 2>&1)"; then
    die "remote port allocation failed: ${output:-no port in ssh output}"
  fi
  port="$(parse_allocated_port "${output}")" || die "remote port allocation failed: ${output:-no port in ssh output}"
  write_remote_port "${port}"
  print_tunnel "${port}"
}

cmd_down() {
  local port

  if master_alive; then
    port="$(fetch_remote_port mux)" || die "failed to read the remote port file"
    if valid_port "${port}"; then
      cancel_forward "${port}"
    fi
    ssh_port_file mux 'rm -f "$port_file"' \
      || die "failed to remove the remote port file"
    ssh -S "${socket}" -O exit "${server}" >/dev/null 2>&1 || true
  else
    ssh_port_file once 'rm -f "$port_file"' \
      || die "failed to remove the remote port file"
  fi
  rm -f "${socket}"
  info "Clash tunnel is down."
}

cmd_status() {
  local port listening="no" master="down" runner="once"

  if master_alive; then
    master="up"
    runner="mux"
  fi
  info "master: ${master}"
  info "server: ${server}"
  info "local port: ${local_port}"
  info "port file: ${port_file}"
  port="$(fetch_remote_port "${runner}")" || die "failed to read the remote port file"
  if valid_port "${port}"; then
    info "remote port: ${port}"
    if remote_listening "${port}" "${runner}"; then
      listening="yes"
    fi
  else
    info "remote port: none"
  fi
  info "listening: ${listening}"
}

case "${command}" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
esac
