---
name: todoocard-skills
description: Prepare, validate, probe, and explicitly send photos to compatible TodooCard/T3 528x792 six-color BLE e-paper cards from macOS. Use when a user asks to transfer JPG, PNG, or HEIC images to a TodooCard, PotatoCard, PICKSMART, NEMR, or T3 screen, inspect nearby compatible BLE cards, or diagnose image orientation and color rendering.
---

# TodooCard Skills

Use this skill only on macOS with `swiftc`, `python3`, `/usr/bin/sips`, Bluetooth permission, and physical proximity to the device. This is a local BLE workflow; it makes no network calls.

## Safety-first workflow

1. Build and list nearby devices without writing:

   ```bash
   scripts/prepare_and_send.sh --list
   ```

2. Ask the user to select the exact UUID. Probe it before sending:

   ```bash
   scripts/prepare_and_send.sh --probe --device-id UUID
   ```

3. Prepare and validate the image first. This does not contact a device:

   ```bash
   scripts/prepare_and_send.sh --input /path/image.heic
   ```

4. State the exact target UUID and request confirmation immediately before the irreversible display update. Only after confirmation, send:

   ```bash
   scripts/prepare_and_send.sh --input /path/image.heic --device-id UUID --send
   ```

The script normalizes images to PNG, uses six-color Floyd-Steinberg dithering, creates a compressed T3 payload, and validates its size and QuickLZ wrapper before Bluetooth transfer. It defaults to a normally mounted screen.

## Orientation

For a physically inverted screen, add:

```bash
--screen-orientation rotate-180-then-flip-horizontal
```

For an individual source image that is sideways, add:

```bash
--rotate-right-90
```

Do not make either correction the global default without testing that physical screen. The screen controller transform is already handled internally; do not add another controller rotation.

## Guardrails

- Require an exact device UUID for probe or send. Do not select a device by name alone.
- Keep `--send` opt-in. A successful transfer permanently changes the screen until another image is sent.
- Do not send arbitrary `.bin` or `.protocol.qlz` files. Always generate and validate them with the bundled converter.
- Treat local images and generated payloads as private. The script keeps transient copies under `/tmp`; do not upload them or log their paths externally.
- The input-size limit is 100 MB and 50 megapixels. Refuse larger inputs rather than exhausting memory.
- If the final device acknowledgement is absent, report failure; do not claim the display refreshed.
