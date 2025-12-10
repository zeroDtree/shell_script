progress() {
    local current=$1
    local total=$2
    local width=50
    local percent=$((current * 100 / total))
    local filled=$((percent * width / 100))
    local bar=$(printf "%${filled}s" | tr ' ' '#')
    local space=$(printf "%$((width - filled))s")
    printf "\r[${bar}${space}] %3d%%" $percent
}

total=100
for ((i=1; i<=total; i++)); do
    progress $i $total
    sleep 0.05
done
echo
