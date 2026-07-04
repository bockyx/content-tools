#!/usr/bin/env bash

# Default values
recording="Unknown"
editing="Unknown"

# Parse options with getopt
OPTS=$(getopt -o r:e:h --long recording:,editing:,help -n "$0" -- "$@")
if [ $? != 0 ]; then
    echo "Error parsing options" >&2
    exit 1
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -r|--recording)
            recording="$2"
            shift 2
            ;;
        -e|--editing)
            editing="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -r, --recording SOFTWARE   Recording software used"
            echo "  -e, --editing SOFTWARE     Editing software used"
            echo "  -h, --help                 Show this help message"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Internal error!" >&2
            exit 1
            ;;
    esac
done

fastfetch=$(fastfetch --format json --structure CPU:GPU:Memory:OS:Kernel:DE:Disk)

cpu=$(jq -r '.[] | select(.type=="CPU") | .result.cpu + " (" + (.result.cores.logical | tostring) + ")"' <<< "$fastfetch")
freq=$(jq -r '.[] | select(.type=="CPU") | (.result.frequency.max / 1000 * 100 + 0.5 | floor) / 100' <<< "$fastfetch")
gpu=$(jq -r '.[] | select(.type=="GPU") | .result[0].name' <<< "$fastfetch")

# RAM
# Bytes to GB
ram=$(jq -r '.[] | select(.type=="Memory") | (.result.total / 1024 / 1024 / 1024 + 2 | ceil)' <<< "$fastfetch")
ram="${ram:-Unknown}GB"
# VRAM
vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null |
    awk '{printf "%.0f", $1/1024}')

vram="${vram:-Unknown}GB"

# Accumulate storage by type
declare -A storage_by_type

while read -r name size rota; do
    if [[ $name == nvme* ]]; then
        type="NVMe SSD"
    elif [[ $rota -eq 0 ]]; then
        type="SATA SSD"
    else
        type="HDD"
    fi

    # Accumulate size by type
    storage_by_type[$type]=$(( ${storage_by_type[$type]:-0} + size ))
done < <(lsblk -bdno NAME,SIZE,ROTA)

# Build output with GB values (decimal)
storage=$'\n'
for type in "NVMe SSD" "SATA SSD" "HDD"; do
    if [[ -n "${storage_by_type[$type]}" ]]; then
        # Convert to GB (decimal, not binary)
        gb=$(( storage_by_type[$type] / 1000000000 ))
        tb=$(( gb / 1000 ))
        if [[ $tb -gt 0 ]]; then
            gb=$(( gb % 1000 ))
            if [[ $gb -eq 0 ]]; then
                storage+="- $type ${tb}TB"$'\n'
                continue
            fi
            storage+="- $type ${tb}TB+${gb}GB"$'\n'
        else
            storage+="- $type ${gb}GB"$'\n'
        fi
    fi
done

storage="${storage%$'\n'}"

os=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
kernel=$(uname -r)
desktop="${XDG_CURRENT_DESKTOP:-Unknown}"

cat <<EOF
## Setup

### 🖥️ Hardware

CPU: $(LC_NUMERIC=C printf "%s @ %.2fGHz\n" "$cpu" "$freq")
GPU: $gpu
RAM: $ram
VRAM: $vram
Storage: $storage

### 🐧 Software

OS: $os
Kernel: Linux $kernel
Desktop: $desktop
Recording: $recording
Editing: $editing
EOF