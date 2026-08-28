#!/usr/bin/env bash

# @help-begin
# Clash proxy-group switcher with auto API setup.
#
# Usage:
#   ./clash_switch.sh [options] <command>
#
# Commands:
#   setup              ensure Clash API is enabled in config (no auto-restart)
#   gen|generate       fetch proxy group members into nodes file
#   apply|put          switch to the uncommented node in nodes file
#   help               show this help
#
# Without a command, an interactive menu is shown.
#
# Defaults when omitted:
#   --group Ghelper
#   --file nodes.txt
#
# Env: python3, curl — required for YAML edits and the Clash HTTP API.
# @help-end

# @help-options-begin
#   -c, --config PATH       Clash YAML config path
#   -g, --group NAME        proxy group name (default: Ghelper)
#   -f, --file PATH         nodes list file (default: nodes.txt)
#   -h, --help              show help
# @help-options-end

set -Eeuo pipefail

_LIB="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
[ -f "${_LIB}" ] || { echo "error: missing ${_LIB} (keep this script in the repo tree)" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "${_LIB}"

# Clash-specific progress prefix (overrides lib info).
info() {
    printf -- '--> %s\n' "$*"
}

readonly DEFAULT_CONTROLLER="127.0.0.1:9090"
readonly DEFAULT_GROUP="Ghelper"
readonly DEFAULT_FILE="nodes.txt"
readonly CURL_CONNECT_TIMEOUT=3
readonly CURL_MAX_TIME=15

GROUP="${DEFAULT_GROUP}"
FILE="${DEFAULT_FILE}"
CONFIG_PATH=""
API_BASE=""
API_SECRET=""
NEED_RESTART=0
CURL_HTTP_CODE=""
API_BODY=""

candidate_configs() {
    local -a paths=(
        "${HOME}/.config/clash/config.yaml"
        "${HOME}/.config/clash/config.yml"
        "${HOME}/clash/config.yaml"
    )
    local p
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] && printf '%s\n' "$p"
    done
}

resolve_config() {
    if [[ -n "$CONFIG_PATH" ]]; then
        [[ -f "$CONFIG_PATH" ]] || die "config not found: $CONFIG_PATH"
        return 0
    fi

    local -a found=()
    local line
    while IFS= read -r line; do
        found+=("$line")
    done < <(candidate_configs | awk '!seen[$0]++')

    case "${#found[@]}" in
        0) die "no Clash config found; pass --config <path>" ;;
        1)
            CONFIG_PATH="${found[0]}"
            info "Using config: $CONFIG_PATH"
            ;;
        *)
            printf '%s\n' "error: multiple configs found; pass --config <path>" >&2
            printf -- '  %s\n' "${found[@]}" >&2
            exit 1
            ;;
    esac
}

# Read/update top-level external-controller and secret.
# Preserves comments for simple scalars; refuses complex YAML forms.
yaml_manage() {
    local mode="$1"
    CONFIG_PATH="$CONFIG_PATH" WANTED_CONTROLLER="$DEFAULT_CONTROLLER" MODE="$mode" python3 - <<'PY'
import os
import re
import shutil
from datetime import datetime
from pathlib import Path

path = Path(os.environ["CONFIG_PATH"])
mode = os.environ["MODE"]
wanted = os.environ["WANTED_CONTROLLER"]

ctrl_re = re.compile(r"^external-controller\s*:\s*(.*)$")
secret_re = re.compile(r"^secret\s*:\s*(.*)$")
top_key_re = re.compile(r"^[^\s#]")

def parse_scalar(raw: str):
    raw = raw.strip()
    if not raw:
        return "", "ok"
    if raw.startswith(("|", ">", "[", "{", "&", "*")):
        return None, "complex"
    if raw[0] in "\"'":
        q = raw[0]
        end = 1
        while end < len(raw):
            if raw[end] == "\\" and end + 1 < len(raw):
                end += 2
                continue
            if raw[end] == q:
                break
            end += 1
        else:
            return None, "unclosed"
        inner = raw[1:end]
        if q == '"':
            value = inner.replace(r"\\", "\0").replace(r'\"', '"').replace("\0", "\\")
        else:
            value = inner
        rest = raw[end + 1 :].strip()
        if rest and not rest.startswith("#"):
            return None, "trailing"
        return value, "ok"
    if "#" in raw:
        raw = raw.split("#", 1)[0].rstrip()
    if not raw:
        return "", "ok"
    if any(c in raw for c in "[]{}"):
        return None, "complex"
    return raw, "ok"

def indented_continuation(lines, i):
    j = i + 1
    while j < len(lines):
        s = lines[j]
        if s.strip() == "" or s.lstrip().startswith("#"):
            j += 1
            continue
        return s[:1] in " \t"
    return False

def scan(lines):
    ctrl_idxs, secret_idxs = [], []
    ctrl_val, secret_val = None, ""
    for i, line in enumerate(lines):
        if not top_key_re.match(line):
            continue
        m = ctrl_re.match(line)
        if m:
            raw = m.group(1)
            if not raw.strip() and indented_continuation(lines, i):
                raise SystemExit(f"unsupported external-controller form at line {i+1}")
            val, st = parse_scalar(raw)
            if st != "ok":
                raise SystemExit(f"unsupported external-controller form at line {i+1}")
            ctrl_idxs.append(i)
            ctrl_val = val
            continue
        m = secret_re.match(line)
        if m:
            raw = m.group(1)
            if not raw.strip() and indented_continuation(lines, i):
                raise SystemExit(f"unsupported secret form at line {i+1}")
            val, st = parse_scalar(raw)
            if st != "ok":
                raise SystemExit(f"unsupported secret form at line {i+1}")
            secret_idxs.append(i)
            secret_val = val if val is not None else ""
    if len(ctrl_idxs) > 1:
        raise SystemExit("duplicate top-level external-controller keys")
    if len(secret_idxs) > 1:
        raise SystemExit("duplicate top-level secret keys")
    return ctrl_idxs, secret_idxs, ctrl_val, secret_val

text = path.read_text(encoding="utf-8")
plain = text.splitlines()
had_trailing_nl = text.endswith("\n")
ctrl_idxs, secret_idxs, ctrl_val, secret_val = scan(plain)

changed = False
if mode == "ensure":
    if not ctrl_idxs:
        insert_at = 0
        while insert_at < len(plain) and (
            plain[insert_at].strip() == "" or plain[insert_at].lstrip().startswith("#")
        ):
            insert_at += 1
        plain.insert(insert_at, f"external-controller: {wanted}")
        changed = True
        ctrl_val = wanted
    elif not (ctrl_val or "").strip():
        plain[ctrl_idxs[0]] = f"external-controller: {wanted}"
        changed = True
        ctrl_val = wanted

    if changed:
        if not os.access(path, os.W_OK) or not os.access(path.parent, os.W_OK):
            raise SystemExit(f"config is not writable: {path}")
        backup = path.with_name(path.name + ".bak." + datetime.now().strftime("%Y%m%d%H%M%S"))
        shutil.copy2(path, backup)
        tmp = path.with_name(path.name + ".tmp")
        body = "\n".join(plain)
        if had_trailing_nl or body:
            body += "\n"
        tmp.write_text(body, encoding="utf-8")
        tmp.replace(path)
        text = path.read_text(encoding="utf-8")
        _, _, ctrl_val, secret_val = scan(text.splitlines())
        if ctrl_val != wanted:
            raise SystemExit("failed to verify external-controller after write")
        print(f"CHANGED\t{backup}")
    else:
        print("UNCHANGED")
    print(f"CONTROLLER\t{ctrl_val if ctrl_val is not None else ''}")
    print(f"SECRET\t{secret_val}")
elif mode == "read":
    print(f"CONTROLLER\t{ctrl_val if ctrl_val is not None else ''}")
    print(f"SECRET\t{secret_val}")
else:
    raise SystemExit(f"unknown mode: {mode}")
PY
}

ensure_api_config() {
    resolve_config

    local out
    out="$(yaml_manage ensure)" || die "failed to manage config: $CONFIG_PATH"

    local status controller secret backup=""
    status="$(printf '%s\n' "$out" | awk '/^(CHANGED|UNCHANGED)/{print $1; exit}')"
    controller="$(printf '%s\n' "$out" | awk -F'\t' '/^CONTROLLER\t/{print substr($0,12); exit}')"
    secret="$(printf '%s\n' "$out" | awk -F'\t' '/^SECRET\t/{print substr($0,8); exit}')"

    if [[ "$status" == "CHANGED" ]]; then
        backup="$(printf '%s\n' "$out" | awk -F'\t' '/^CHANGED\t/{print substr($0,9); exit}')"
        info "Updated external-controller to ${DEFAULT_CONTROLLER}"
        info "Backup saved: $backup"
        NEED_RESTART=1
        printf -- 'Please restart Clash to apply config changes.\n' >&2
    else
        info "external-controller already set to ${controller:-"(missing)"}"
    fi

    [[ -n "$controller" ]] || die "external-controller missing after ensure"

    if [[ "$controller" == http://* || "$controller" == https://* ]]; then
        API_BASE="${controller%/}"
    else
        API_BASE="http://${controller}"
    fi
    API_SECRET="$secret"
}

urlencode() {
    python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

# Sets CURL_HTTP_CODE and API_BODY in the current shell (do not call via $()).
api_curl() {
    local method="$1"
    local url="$2"
    shift 2
    local tmp
    tmp="$(mktemp)"
    local -a args=(
        --silent --show-error
        --connect-timeout "$CURL_CONNECT_TIMEOUT"
        --max-time "$CURL_MAX_TIME"
        -X "$method"
        -w "%{http_code}"
        -o "$tmp"
    )
    if [[ -n "${API_SECRET}" ]]; then
        args+=(-H "Authorization: Bearer ${API_SECRET}")
    fi
    args+=("$@")
    args+=("$url")

    local code="" rc=0
    set +e
    code="$(curl "${args[@]}")"
    rc=$?
    set -e
    CURL_HTTP_CODE="${code:-000}"
    API_BODY=""
    if [[ -f "$tmp" ]]; then
        API_BODY="$(cat "$tmp")"
        rm -f "$tmp"
    fi
    return "$rc"
}

probe_api() {
    local rc=0
    set +e
    api_curl GET "${API_BASE}/"
    rc=$?
    set -e

    if ((rc != 0)); then
        if ((NEED_RESTART)); then
            die "API unreachable at ${API_BASE} (config changed; restart Clash first)"
        fi
        die "API unreachable at ${API_BASE} (is Clash running?)"
    fi

    case "$CURL_HTTP_CODE" in
        200|204) return 0 ;;
        401|403) die "API authentication failed (check secret in config)" ;;
    esac

    set +e
    api_curl GET "${API_BASE}/version"
    rc=$?
    set -e
    if ((rc == 0)) && [[ "$CURL_HTTP_CODE" == "200" ]]; then
        return 0
    fi
    if [[ "$CURL_HTTP_CODE" == "401" || "$CURL_HTTP_CODE" == "403" ]]; then
        die "API authentication failed (check secret in config)"
    fi
    if ((NEED_RESTART)); then
        die "API not ready at ${API_BASE} (HTTP ${CURL_HTTP_CODE}; restart Clash first)"
    fi
    die "unexpected API response from ${API_BASE}: HTTP ${CURL_HTTP_CODE}"
}

prepare_api() {
    ensure_api_config
    probe_api
}

generate_list() {
    prepare_api
    local group_enc rc=0
    group_enc="$(urlencode "$GROUP")"
    info "Fetching node list from Clash group [${GROUP}]..."

    set +e
    api_curl GET "${API_BASE}/proxies/${group_enc}"
    rc=$?
    set -e

    ((rc == 0)) || die "failed to fetch proxies (curl exit ${rc})"
    if [[ "$CURL_HTTP_CODE" != "200" ]]; then
        if [[ "$CURL_HTTP_CODE" == "401" || "$CURL_HTTP_CODE" == "403" ]]; then
            die "API authentication failed (check secret in config)"
        fi
        die "failed to fetch proxies: HTTP ${CURL_HTTP_CODE}"
    fi

    FILE="$FILE" python3 -c '
import json, os, sys, tempfile
from pathlib import Path

path = Path(os.environ["FILE"])
data = json.load(sys.stdin)
nodes = data.get("all", [])
now = data.get("now", "")
parent = path.parent if str(path.parent) else Path(".")

fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("# ==========================================\n")
        f.write(f"# Currently Active Node: {now}\n")
        f.write("# Usage: Remove the leading \"#\" from the node you want to select.\n")
        f.write("# (Please ensure only ONE node is uncommented)\n")
        f.write("# ==========================================\n\n")
        for n in nodes:
            # Keep the full node name on one line; never append inline comments
            # (node names may themselves contain '#').
            if n == now:
                f.write(f"{n}\n")
            else:
                f.write(f"# {n}\n")
    os.replace(tmp_name, path)
except Exception:
    try:
        os.unlink(tmp_name)
    except OSError:
        pass
    raise
print("--> List successfully generated!")
' <<<"$API_BODY"

    info "Saved to ${FILE}. Edit it, then run: $(basename "$0") apply"
}

read_selected_node() {
    [[ -f "$FILE" ]] || die "${FILE} does not exist; run generate first"

    local line selected=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Entire uncommented line is the node name (may contain '#').
        selected="${line#"${line%%[![:space:]]*}"}"
        selected="${selected%"${selected##*[![:space:]]}"}"
        break
    done <"$FILE"

    [[ -n "$selected" ]] || die "no valid (uncommented) node selection found in ${FILE}"
    printf '%s\n' "$selected"
}

apply_switch() {
    prepare_api
    local target payload group_enc rc=0
    target="$(read_selected_node)"
    info "Submitting node switch to: [${target}]"

    payload="$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1]}))' "$target")"
    group_enc="$(urlencode "$GROUP")"

    set +e
    api_curl PUT "${API_BASE}/proxies/${group_enc}" \
        -H "Content-Type: application/json" \
        --data-binary "$payload"
    rc=$?
    set -e

    ((rc == 0)) || die "switch request failed (curl exit ${rc})"
    case "$CURL_HTTP_CODE" in
        200|204) info "Switch successful: ${target}" ;;
        401|403) die "API authentication failed (check secret in config)" ;;
        *) die "switch failed: HTTP ${CURL_HTTP_CODE}" ;;
    esac
}

cmd_setup() {
    ensure_api_config
    if ((NEED_RESTART)); then
        info "Setup done. Restart Clash, then use generate/apply."
        return 0
    fi

    local rc=0
    set +e
    api_curl GET "${API_BASE}/version"
    rc=$?
    set -e
    if ((rc == 0)) && [[ "$CURL_HTTP_CODE" == "200" ]]; then
        info "API is reachable at ${API_BASE}"
        return 0
    fi
    if [[ "$CURL_HTTP_CODE" == "401" || "$CURL_HTTP_CODE" == "403" ]]; then
        die "API authentication failed (check secret in config)"
    fi
    info "Config looks ready, but API is not reachable at ${API_BASE} yet"
    info "Start or restart Clash, then retry"
}

interactive_menu() {
    cat <<EOF
==========================================
 Clash Node Switcher
==========================================
1) Setup / check Clash API config
2) Generate/Refresh ${FILE}
3) Apply selected node from ${FILE}
4) Exit
==========================================
EOF
    local choice
    read -r -p "Select an option [1-4]: " choice
    case "$choice" in
        1) cmd_setup ;;
        2) generate_list ;;
        3) apply_switch ;;
        4) exit 0 ;;
        *) die "invalid option" ;;
    esac
}

main() {
    local -a positional=()
    while (($#)); do
        case "$1" in
            -c|--config)
                require_value "$@"
                CONFIG_PATH="$2"
                shift 2
                ;;
            -g|--group)
                require_value "$@"
                GROUP="$2"
                shift 2
                ;;
            -f|--file)
                require_value "$@"
                FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            --)
                shift
                positional+=("$@")
                break
                ;;
            -*)
                die "unrecognized option: $1"
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    FILE="$(expand_path "${FILE}")"
    if [[ -n "$CONFIG_PATH" ]]; then
        CONFIG_PATH="$(expand_path "$CONFIG_PATH")"
    fi

    have_cmd python3 || die "python3 is required"
    have_cmd curl || die "curl is required"

    local cmd="${positional[0]:-}"
    case "$cmd" in
        "") interactive_menu ;;
        setup) cmd_setup ;;
        gen|generate) generate_list ;;
        apply|put) apply_switch ;;
        help) usage ;;
        *) die "unknown command: $cmd (try --help)" ;;
    esac
}

main "$@"
