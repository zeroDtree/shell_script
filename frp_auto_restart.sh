#!/bin/bash

server_port="7000"
frp_home="$HOME/.local/frp"
log_path="$frp_home/log.txt"

ARGS=$(getopt --options="i:p:f:l:r" --longoptions="server_ip:,server_port:,frp_home:,log_path:,remote_port" -- "$@")
if [ $? -ne 0 ]; then
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
        --)
            shift
            break
            ;;
        *)
            echo "unrecognized option: $1"
            exit 1
            ;;
    esac
done

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

