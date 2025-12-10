
# Add paths only if not already in PATH
add_to_path() {
    for dir in "$@"; do
        case ":$PATH:" in
            *":$dir:"*) ;;  # already exists
            *) export PATH="$dir:$PATH" ;;
        esac
    done
}

add_to_path_config() {
    for dir in "$@"; do
        export PATH="$dir:$PATH"
        echo "add_to_path $dir" >> ~/.bashrc
    done
}

add_pwd_to_path_config() {
    export PATH="$(pwd):$PATH"
    echo "add_to_path $(pwd)" >> ~/.bashrc
}

export LANG="en_US.UTF-8"

proxy_port=7890
proxy_ip=127.0.0.1

proxy_on() {
    for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY; do
        export $var="http://$proxy_ip:$proxy_port"
        echo "set -gx $var http://$proxy_ip:$proxy_port"
    done
    export no_proxy="127.0.0.1,localhost"
    export NO_PROXY="127.0.0.1,localhost"
    echo -e "\033[32m[√] Proxy enabled\033[0m"
}

proxy_off() {
    for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY; do
        unset $var
        echo "unset $var"
    done
    echo -e "\033[31m[×] Proxy disabled\033[0m"
}

cuda() {
    devs="$1"
    shift
    cmd="CUDA_VISIBLE_DEVICES=$devs $*"
    echo "$cmd"
    CUDA_VISIBLE_DEVICES="$devs" "$@"
}

hfmon() {
    export HF_ENDPOINT="https://hf-mirror.com"
}

hfmoff() {
    unset HF_ENDPOINT
}

# CA bundle off + backup
ca_off() {
    export __CURL_CA_BUNDLE_BACKUP="$CURL_CA_BUNDLE"
    export __REQUESTS_CA_BUNDLE_BACKUP="$REQUESTS_CA_BUNDLE"

    export CURL_CA_BUNDLE=""
    export REQUESTS_CA_BUNDLE=""

    echo "CA bundle environment variables disabled and backed up."
}

ca_on() {
    if [[ -n "$__CURL_CA_BUNDLE_BACKUP" ]]; then
        export CURL_CA_BUNDLE="$__CURL_CA_BUNDLE_BACKUP"
    else
        unset CURL_CA_BUNDLE
    fi

    if [[ -n "$__REQUESTS_CA_BUNDLE_BACKUP" ]]; then
        export REQUESTS_CA_BUNDLE="$__REQUESTS_CA_BUNDLE_BACKUP"
    else
        unset REQUESTS_CA_BUNDLE
    fi

    echo "CA bundle environment variables restored."
    echo "CURL_CA_BUNDLE=$CURL_CA_BUNDLE"
    echo "REQUESTS_CA_BUNDLE=$REQUESTS_CA_BUNDLE"
}

# tmux session manager
zls() {
    name="zls$1"
    if tmux has-session -t "$name" 2>/dev/null; then
        echo "tmux attach-session -t $name"
        tmux attach-session -t "$name"
    else
        tmux new-session -s "$name"
    fi
}

start_if_not_running() {
    process_name="$1"
    shift
    if ! pgrep -f "$process_name" >/dev/null; then
        echo "Starting $process_name..."
        "$@" &
        sleep 2
        echo "$process_name has been started successfully"
    else
        echo "$process_name is already running"
    fi
}

# ============================
# CUDA Environment
# ============================

export CUDA_DIR="$HOME/software/cuda"
export CUDA_HOME="$CUDA_DIR/cuda-12.4"
export CUDA_PATH="$CUDA_HOME"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
export PATH="$CUDA_HOME/bin:$PATH"

use_cuda() {
    CUDA_HOME_128="$CUDA_DIR/cuda-12.8"
    CUDA_HOME_121="$CUDA_DIR/cuda-12.1"
    CUDA_HOME_124="$CUDA_DIR/cuda-12.4"
    CUDA_HOME_118="$CUDA_DIR/cuda-11.8"

    version_to_use="$1"

    if [[ -z "$version_to_use" ]]; then
        echo "Please specify CUDA version (11.8, 12.1, 12.4, 12.8)"
        return 1
    fi

    case "$version_to_use" in
        11.8) export CUDA_HOME="$CUDA_HOME_118" ;;
        12.1) export CUDA_HOME="$CUDA_HOME_121" ;;
        12.4) export CUDA_HOME="$CUDA_HOME_124" ;;
        12.8) export CUDA_HOME="$CUDA_HOME_128" ;;
        *)
            echo "Unsupported CUDA version: $version_to_use"
            echo "Supported versions: 11.8, 12.1, 12.4, 12.8"
            return 1 ;;
    esac

    export PATH="$CUDA_HOME/bin:$PATH"
    export CUDA_PATH="$CUDA_HOME"
    export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"

    echo "Switched to CUDA $version_to_use"
    echo "CUDA_HOME = $CUDA_HOME"
}

# Aliases
alias g++='g++ -finput-charset=UTF-8 -fexec-charset=UTF-8'
alias c++='c++ -finput-charset=UTF-8 -fexec-charset=UTF-8'
alias ls='ls --color'

