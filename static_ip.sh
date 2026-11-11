#!/usr/bin/env bash

# Set a NetworkManager IPv4 profile to a static address.
# An empty connection entry uses the active wired or Wi-Fi connection UUID.

set -euo pipefail

DEFAULT_UUID=""
DEFAULT_NAME=""
DEFAULT_DEVICE=""
CONN_UUID=""

# read -p hides its prompt unless stdin is a terminal. Print it ourselves.
prompt_read() {
  local __reply=""
  printf '%s' "$1" >&2
  if ! IFS= read -r __reply; then
    echo "[-] Aborted." >&2
    return 1
  fi
  printf '%s\n' "$__reply"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

valid_ipv4() {
  local ip="$1"
  local octet
  local o1 o2 o3 o4

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<< "$ip"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    if ((10#$octet > 255)); then
      return 1
    fi
  done
}

valid_cidr() {
  local value="$1"
  local address="${value%/*}"
  local prefix="${value#*/}"

  [[ "$value" == */* && "$prefix" != "$value" ]] || return 1
  [[ "$prefix" =~ ^([0-9]|[1-2][0-9]|3[0-2])$ ]] || return 1
  valid_ipv4 "$address"
}

# A /24 host gets x.x.x.1 unless that address is the host itself.
default_slash24_gateway() {
  local value="$1"
  local address="${value%/*}"
  local prefix="${value#*/}"
  local o1 o2 o3 o4

  [[ "$prefix" == "24" ]] || return 1
  IFS=. read -r o1 o2 o3 o4 <<< "$address"
  if ((10#$o4 == 1)); then
    return 1
  fi
  printf '%s\n' "${o1}.${o2}.${o3}.1"
}

valid_dns_list() {
  local dns="$1"
  local server
  local -a servers=()

  [[ -n "$dns" ]] || return 0
  read -r -a servers <<< "$dns"
  if ((${#servers[@]} == 0)); then
    return 1
  fi
  for server in "${servers[@]}"; do
    valid_ipv4 "$server" || return 1
  done
}

is_wired_or_wifi() {
  case "$1" in
    802-3-ethernet|ethernet|802-11-wireless|wifi) return 0 ;;
    *) return 1 ;;
  esac
}

# Active wired/Wi-Fi only. One match wins. Several matches use the device
# that carries the IPv4 default route. VPN, bridge, and docker are ignored.
detect_default_connection() {
  local default_dev=""
  local uuid=""
  local type=""
  local device=""
  local chosen=-1
  local i
  local -a uuids=()
  local -a devices=()

  DEFAULT_UUID=""
  DEFAULT_NAME=""
  DEFAULT_DEVICE=""

  # Read the whole route table. Exiting awk early can SIGPIPE ip and, with
  # pipefail, hide a device name that was already printed.
  default_dev="$(ip -4 route show default 2>/dev/null | awk 'NR == 1 { print $5 }')" || true

  while IFS=: read -r uuid type device _; do
    [[ -n "$uuid" && -n "$device" && "$device" != "--" ]] || continue
    is_wired_or_wifi "$type" || continue
    uuids+=("$uuid")
    devices+=("$device")
  done < <(nmcli -t -f UUID,TYPE,DEVICE connection show --active)

  if ((${#uuids[@]} == 1)); then
    chosen=0
  elif ((${#uuids[@]} > 1)); then
    if [[ -n "$default_dev" ]]; then
      for i in "${!uuids[@]}"; do
        if [[ "${devices[$i]}" == "$default_dev" ]]; then
          chosen=$i
          break
        fi
      done
    fi
    if ((chosen < 0)); then
      echo "[-] Several wired or Wi-Fi connections are active, and none carries the IPv4 default route."
      return 0
    fi
  else
    echo "[-] No active wired or Wi-Fi connection was found."
    return 0
  fi

  DEFAULT_UUID="${uuids[$chosen]}"
  DEFAULT_DEVICE="${devices[$chosen]}"
  DEFAULT_NAME="$(nmcli -g connection.id connection show "$DEFAULT_UUID")"
}

lookup_uuid_by_device() {
  local want="$1"
  local uuid=""
  local device=""
  local iface=""

  while IFS=: read -r uuid device _; do
    if [[ -n "$uuid" && "$device" == "$want" ]]; then
      printf '%s\n' "$uuid"
      return 0
    fi
  done < <(nmcli -t -f UUID,DEVICE connection show --active)

  while IFS= read -r uuid; do
    [[ -n "$uuid" ]] || continue
    iface="$(nmcli -g connection.interface-name connection show "$uuid" 2>/dev/null || true)"
    if [[ "$iface" == "$want" ]]; then
      printf '%s\n' "$uuid"
      return 0
    fi
  done < <(nmcli -t -f UUID connection show)

  return 1
}

# Accept a connection UUID, a connection name, or a device name.
resolve_connection() {
  local input="$1"
  local uuid=""

  if uuid="$(nmcli -g connection.uuid connection show "$input" 2>/dev/null)" && [[ -n "$uuid" ]]; then
    # More than one line means the name matched multiple profiles.
    if [[ "$uuid" == *$'\n'* ]]; then
      return 1
    fi
    printf '%s\n' "$uuid"
    return 0
  fi

  if uuid="$(lookup_uuid_by_device "$input")"; then
    printf '%s\n' "$uuid"
    return 0
  fi

  return 1
}

connection_name() {
  local name=""
  name="$(nmcli -g connection.id connection show "$1")"
  printf '%s\n' "${name%%$'\n'*}"
}

connection_device() {
  local device=""
  device="$(nmcli -g GENERAL.DEVICES connection show "$1" 2>/dev/null || true)"
  device="${device%%$'\n'*}"
  if [[ -z "$device" || "$device" == "--" ]]; then
    device="$(nmcli -g connection.interface-name connection show "$1" 2>/dev/null || true)"
    device="${device%%$'\n'*}"
  fi
  if [[ -z "$device" || "$device" == "--" ]]; then
    return 1
  fi
  printf '%s\n' "$device"
}

apply_ipv4() {
  local uuid="$1"
  local address="$2"
  local gateway="$3"
  local dns="$4"

  if [[ -n "$dns" ]]; then
    nmcli connection modify "$uuid" \
      ipv4.method manual \
      ipv4.addresses "$address" \
      ipv4.gateway "$gateway" \
      ipv4.dns "$dns" || return 1
  else
    nmcli connection modify "$uuid" \
      ipv4.method manual \
      ipv4.addresses "$address" \
      ipv4.gateway "$gateway" || return 1
  fi

  nmcli connection up "$uuid"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[-] Please run this script using sudo or root privileges!"
    exit 1
  fi
}

require_commands() {
  local missing=0
  local cmd
  for cmd in nmcli ip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[-] Required command not found: ${cmd}"
      missing=1
    fi
  done
  if ((missing != 0)); then
    exit 1
  fi
}

# Empty input uses DEFAULT_UUID when one was detected.
select_connection() {
  local raw_input=""
  local input=""
  local uuid=""

  if [[ -n "${DEFAULT_UUID}" ]]; then
    echo "[+] Active wired/Wi-Fi connection:"
    echo "  - Name:   ${DEFAULT_NAME}"
    echo "  - Device: ${DEFAULT_DEVICE}"
    echo "  - UUID:   ${DEFAULT_UUID}"
    echo
    if ! raw_input="$(prompt_read "Connection UUID (press Enter to skip and use ${DEFAULT_UUID}): ")"; then
      return 1
    fi
  else
    if ! raw_input="$(prompt_read "Enter connection UUID, name, or device: ")"; then
      return 1
    fi
  fi

  input="$(trim "$raw_input")"
  if [[ -z "$input" ]]; then
    if [[ -z "${DEFAULT_UUID}" ]]; then
      echo "[-] Connection cannot be empty. Exiting."
      return 1
    fi
    CONN_UUID="${DEFAULT_UUID}"
    return 0
  fi

  if ! uuid="$(resolve_connection "$input")"; then
    echo "[-] Unknown connection or device: ${input}"
    return 1
  fi
  CONN_UUID="$uuid"
}

run_interactive() {
  local ip_addr=""
  local gateway=""
  local dns_servers=""
  local confirm=""
  local conn_name=""
  local conn_device=""
  local refreshed=""
  local default_gateway=""

  echo "=========================================="
  echo "      Linux NetworkManager Static IP Tool   "
  echo "=========================================="
  echo "[+] Currently available network connections:"
  if ! nmcli connection show; then
    echo "[-] Failed to list NetworkManager connections."
    exit 1
  fi
  echo

  detect_default_connection
  select_connection || exit 1

  conn_name="$(connection_name "$CONN_UUID")"
  if conn_device="$(connection_device "$CONN_UUID")"; then
    :
  else
    conn_device=""
  fi

  ip_addr="$(prompt_read "Enter static IP address and CIDR subnet mask (e.g., 192.168.1.100/24): ")"
  ip_addr="$(trim "$ip_addr")"
  if ! valid_cidr "$ip_addr"; then
    echo "[-] IP address must look like 192.168.1.100/24. Exiting."
    exit 1
  fi

  if default_gateway="$(default_slash24_gateway "$ip_addr")"; then
    gateway="$(prompt_read "Enter gateway address (press Enter to skip and use ${default_gateway}): ")"
  else
    gateway="$(prompt_read "Enter gateway address (e.g., 192.168.1.1): ")"
  fi
  dns_servers="$(prompt_read "Enter DNS servers (separate multiple with spaces, e.g., 8.8.8.8 1.1.1.1): ")"

  gateway="$(trim "$gateway")"
  dns_servers="$(trim "$dns_servers")"
  if [[ -z "$gateway" && -n "$default_gateway" ]]; then
    gateway="$default_gateway"
  fi

  if ! valid_ipv4 "$gateway"; then
    echo "[-] Gateway must be an IPv4 address. Exiting."
    exit 1
  fi
  if ! valid_dns_list "$dns_servers"; then
    echo "[-] DNS servers must be IPv4 addresses separated by spaces. Exiting."
    exit 1
  fi

  echo
  echo "------------------------------------------"
  echo "Applying the following configuration to connection [${conn_name}] (${CONN_UUID}):"
  if [[ -n "$conn_device" ]]; then
    echo "  - Device:      ${conn_device}"
  fi
  echo "  - IP Address:  ${ip_addr}"
  echo "  - Gateway:     ${gateway}"
  if [[ -n "$dns_servers" ]]; then
    echo "  - DNS:         ${dns_servers}"
  else
    echo "  - DNS:         (unchanged)"
  fi
  echo "------------------------------------------"
  confirm="$(prompt_read "Confirm and apply? (y/n): ")"

  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "[-] Operation cancelled."
    exit 0
  fi

  echo "[*] Modifying configuration..."
  if ! apply_ipv4 "$CONN_UUID" "$ip_addr" "$gateway" "$dns_servers"; then
    echo "[-] Failed to apply the connection. Check the UUID and parameters and try again."
    exit 1
  fi

  refreshed="$(connection_device "$CONN_UUID" 2>/dev/null || true)"
  if [[ -n "$refreshed" ]]; then
    conn_device="$refreshed"
  fi

  echo "[+] Network configuration applied successfully!"
  if [[ -n "$conn_device" ]]; then
    echo "[*] Current IPv4 address on ${conn_device}:"
    ip -4 addr show dev "$conn_device"
  else
    echo "[*] Current IPv4 addresses:"
    ip -4 addr
  fi
}

main() {
  require_root
  require_commands
  run_interactive
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
