#!/usr/bin/env bash

recording="${1:-Unknown}"
editing="${2:-Unknown}"

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

# Acumular almacenamiento por tipo
declare -A storage_by_type

while read -r name size rota; do
    if [[ $name == nvme* ]]; then
        type="NVMe SSD"
    elif [[ $rota -eq 0 ]]; then
        type="SATA SSD"
    else
        type="HDD"
    fi

    # Acumular tamaño por tipo
    storage_by_type[$type]=$(( ${storage_by_type[$type]:-0} + size ))
done < <(lsblk -bdno NAME,SIZE,ROTA)

# Construir salida con valores en GB (decimal)
storage=$'\n'
for type in "NVMe SSD" "SATA SSD" "HDD"; do
    if [[ -n "${storage_by_type[$type]}" ]]; then
        # Convertir a GB (decimal, no binario)
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