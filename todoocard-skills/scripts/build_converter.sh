#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${1:-/tmp/potato-image-to-payload}"

swiftc \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework Foundation \
  "$script_dir/image_to_payload.swift" \
  -o "$output"

echo "$output"
