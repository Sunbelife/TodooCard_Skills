#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input_path=""
device_id=""
screen_orientation="normal"
rotate_right_90=false
mode="prepare"

usage() {
  cat <<'EOF'
Usage:
  prepare_and_send.sh --list
  prepare_and_send.sh --probe --device-id UUID
  prepare_and_send.sh --input photo.jpg [--screen-orientation normal|rotate-180-then-flip-horizontal] [--rotate-right-90]
  prepare_and_send.sh --input photo.jpg --device-id UUID --send [--screen-orientation normal|rotate-180-then-flip-horizontal] [--rotate-right-90]

Default behavior only prepares and validates a T3 payload. --send is required
before Bluetooth writes. --device-id is always required for a probe or send.
EOF
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) [[ $# -ge 2 ]] || usage; input_path="$2"; shift 2 ;;
    --device-id) [[ $# -ge 2 ]] || usage; device_id="$2"; shift 2 ;;
    --screen-orientation) [[ $# -ge 2 ]] || usage; screen_orientation="$2"; shift 2 ;;
    --rotate-right-90) rotate_right_90=true; shift ;;
    --list) mode="list"; shift ;;
    --probe) mode="probe"; shift ;;
    --send) mode="send"; shift ;;
    *) usage ;;
  esac
done

case "$screen_orientation" in
  normal|rotate-180-then-flip-horizontal) ;;
  *) echo "Unsupported screen orientation: $screen_orientation" >&2; exit 64 ;;
esac

for command in swiftc python3 /usr/bin/sips; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command unavailable: $command" >&2; exit 69; }
done

if [[ "$mode" == "probe" || "$mode" == "send" ]]; then
  [[ -n "$device_id" ]] || { echo "--device-id is required before contacting a device." >&2; exit 64; }
fi
if [[ "$mode" == "prepare" || "$mode" == "send" ]]; then
  [[ -n "$input_path" && -f "$input_path" ]] || { echo "Input image not found: $input_path" >&2; exit 2; }
  image_bytes="$(stat -f %z "$input_path")"
  [[ "$image_bytes" -le 100000000 ]] || { echo "Input image exceeds the 100 MB safety limit." >&2; exit 65; }
  image_width="$(/usr/bin/sips -g pixelWidth "$input_path" | awk '/pixelWidth/ {print $2}')"
  image_height="$(/usr/bin/sips -g pixelHeight "$input_path" | awk '/pixelHeight/ {print $2}')"
  [[ "$image_width" =~ ^[0-9]+$ && "$image_height" =~ ^[0-9]+$ ]] || { echo "Unable to determine input image dimensions." >&2; exit 65; }
  (( image_width * image_height <= 50000000 )) || { echo "Input image exceeds the 50-megapixel safety limit." >&2; exit 65; }
fi

run_dir="$(mktemp -d /tmp/potatocard-transfer.XXXXXX)"
mkdir -p "$run_dir/module-cache"
cp -R "$script_dir" "$run_dir/scripts"
converter="$run_dir/image-to-payload"
sender="$run_dir/mac-image-transfer"
CLANG_MODULE_CACHE_PATH="$run_dir/module-cache" "$run_dir/scripts/build_converter.sh" "$converter" >/dev/null
CLANG_MODULE_CACHE_PATH="$run_dir/module-cache" "$run_dir/scripts/build_sender.sh" "$sender" >/dev/null

if [[ "$mode" == "list" ]]; then
  "$sender" --list
  exit 0
fi
if [[ "$mode" == "probe" ]]; then
  "$sender" --probe --id "$device_id"
  exit 0
fi

input_copy="$run_dir/input-source"
cp "$input_path" "$input_copy"
normalized_image="$run_dir/input-normalized.png"
if [[ "$rotate_right_90" == true ]]; then
  TMPDIR="$run_dir" /usr/bin/sips -s format png -r 90 "$input_copy" --out "$normalized_image" >/dev/null
else
  TMPDIR="$run_dir" /usr/bin/sips -s format png "$input_copy" --out "$normalized_image" >/dev/null
fi

payload_prefix="$run_dir/image"
"$converter" --input "$normalized_image" --target t3 --orientation "$screen_orientation" --output-prefix "$payload_prefix"
python3 "$run_dir/scripts/validate_payload.py" "$payload_prefix.protocol.qlz"
echo "Prepared payload: $payload_prefix.protocol.qlz"

if [[ "$mode" == "send" ]]; then
  echo "Sending to device $device_id ..."
  "$sender" --payload "$payload_prefix.protocol.qlz" --compressed --id "$device_id"
fi
