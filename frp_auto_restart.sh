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
#   --log_path ~/.local/frp/log.txt
# @help-end

# @help-options-begin
#   -i, --server_ip IP      FRP server IP (required)
#   -p, --server_port PORT  FRP server port (default: 7000)
#   -f, --frp_home PATH     frpc home directory (default: ~/.local/frp)
#   -l, --log_path PATH     restart log file (default: $frp_home/log.txt)
#   -h, --help              show help
# @help-options-end

set -euo pipefail

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' '#' 'Options:' '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "$0"
  exit 0
}

server_port="7000"
frp_home="$HOME/.local/frp"
log_path="$frp_home/log.txt"
server_ip=""

case "${1:-}" in
  -h|--help) usage ;;
esac

if ! ARGS=$(getopt --options="i:p:f:l:h" --longoptions="server_ip:,server_port:,frp_home:,log_path:,help" -- "$@"); then
    echo "Failed to parse arguments." >&2
    exit 1
fi

eval set -- "${ARGS}"
while true; do
    case "$1" in
        -i|--server_ip)
            server_ip="$2"
            shift 2
            ;;
        -p|--server_port)
            server_port="$2"
            shift 2
            ;;
        -f|--frp_home)
            frp_home="$2"
            shift 2
            ;;
        -l|--log_path)
            log_path="$2"
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
            echo "unrecognized option: $1" >&2
            exit 1
            ;;
    esac
done

[[ -n "$server_ip" ]] || usage

echo "server_ip=$server_ip"
echo "server_port=$server_port"
echo "frp_home=$frp_home"
echo "log_path=$log_path"

check_connection() {
    netstat -an | grep "${server_ip}:${server_port}" | grep "ESTABLISHED" > /dev/null
    return $?
}

check_process() {
    pgrep -f "frpc" > /dev/null
    return $?
}

restart_frpc() {
    cd "$frp_home" || exit 1
    ./frpc -c ./frpc.toml >> "$log_path" 2>&1 &
    echo "Restarted frpc at $(date)" >> "$log_path"
}

if ! check_connection; then
    echo "No established connection, restarting frpc..."
    restart_frpc
else
    echo "Connection is alive."
fi
