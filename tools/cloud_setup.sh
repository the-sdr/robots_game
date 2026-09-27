#!/usr/bin/env bash
# One-time setup for a Linux cloud session (Claude Code on the web / cloud sandbox).
# Installs what the level pipeline needs, then runs Godot's import pass.
#   bash tools/cloud_setup.sh
# Afterwards use:  godot --headless --path . -s <script>   (see CLAUDE.md, "Verify")
#
# Godot: the official Linux build runs headless with --headless (there is no
# separate headless download in Godot 4). If the sandbox blocks the download,
# everything except baking and the physics tests still works (design edits,
# forest_map.py, forest_build.py, forest_verify.py are pure Python).
set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_DIR="${HOME}/.local/godot"
GODOT_BIN="${GODOT_DIR}/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

cd "$(dirname "$0")/.."

echo "== Python packages (numpy, Pillow, openpyxl)"
python3 -m pip install --quiet --user numpy pillow openpyxl

if command -v godot >/dev/null 2>&1; then
    echo "== Godot already on PATH: $(godot --version)"
else
    echo "== Downloading Godot ${GODOT_VERSION} for Linux"
    mkdir -p "${GODOT_DIR}" "${HOME}/.local/bin"
    if curl -fL --retry 3 -o /tmp/godot.zip "${URL}"; then
        (cd "${GODOT_DIR}" && unzip -o -q /tmp/godot.zip)
        chmod +x "${GODOT_BIN}"
        ln -sf "${GODOT_BIN}" "${HOME}/.local/bin/godot"
        export PATH="${HOME}/.local/bin:${PATH}"
        echo "   installed: $(godot --version)"
    else
        echo "!! Could not download Godot (network blocked?). Python tools still work;"
        echo "   baking (tools/level_bake.gd) and the drive test need Godot."
        exit 0
    fi
fi

echo "== Godot import pass (first run builds the .godot cache; takes a few minutes)"
godot --headless --editor --path . --quit >/dev/null 2>&1 || true

echo "== Ready. Quick check:"
python3 tools/forest_verify.py | tail -3
