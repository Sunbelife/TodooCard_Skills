#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${1:-/tmp/mac-image-transfer}"

swiftc \
  -framework CoreBluetooth \
  -framework Foundation \
  "$script_dir/mac_image_transfer.swift" \
  -o "$output"

echo "$output"
