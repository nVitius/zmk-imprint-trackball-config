#!/usr/bin/env bash
#
# build-zmk.sh – reproducible ZMK build helper
#
#  * Bash 4+
#  * west + Zephyr SDK/toolchain on PATH

set -euo pipefail

###############################################################################
# Argument parsing
###############################################################################
CFG_REPO=""
BOARD=""
SHIELD=""
OUT_DIR=""
WKSPC=""                   # optional
DO_CLEAN=false
EXTRA_CMAKE_ARGS=""

usage() {
  cat <<EOF
Usage: $0 --cfg <path> --board <board> --out <dir> [options]

Required:
  --cfg     Path to your zmk-config repo (contains 'config/' + extras)
  --board   Zephyr board (e.g. nice_nano_v2, assimilator-bt)
  --out     Directory to drop firmware into

Optional:
  --shield  Shield (imprint_left, kyria_rev2_right, ...)
  --wkspc   Workspace dir to (re)use; defaults to a new mktemp dir
  --clean   *Only when --wkspc is given*: wipe the dir before building
  --cmake   Extra CMake args in quotes
  -h|--help Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --cfg)     CFG_REPO="$(realpath "$2")"; shift 2 ;;
    --board)   BOARD="$2"; shift 2 ;;
    --shield)  SHIELD="$2"; shift 2 ;;
    --out)     OUT_DIR="$(realpath "$2")"; shift 2 ;;
    --wkspc)   WKSPC="$(realpath "$2")"; shift 2 ;;
    --clean)   DO_CLEAN=true; shift ;;
    --cmake)   EXTRA_CMAKE_ARGS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option $1"; usage; exit 1 ;;
  esac
done

[[ -d "$CFG_REPO/config" ]] || { echo "error: '$CFG_REPO/config' not found"; exit 1; }
[[ -n "$BOARD" && -n "$OUT_DIR" ]] || { usage; exit 1; }

###############################################################################
# Workspace setup
###############################################################################
if [[ -z "$WKSPC" ]]; then
  WKSPC="$(mktemp -d)"
  DO_CLEAN=true
fi

if [[ -d "$WKSPC" && "$DO_CLEAN" == true ]]; then
  echo ">>> Cleaning workspace $WKSPC"
  rm -rf "$WKSPC"
fi
mkdir -p "$WKSPC" "$OUT_DIR"

echo ">>> Workspace: $WKSPC"

# Copy (or refresh) config/ folder
rm -rf "$WKSPC/config" 2>/dev/null || true
cp -R "$CFG_REPO/config" "$WKSPC"/

###############################################################################
# West setup
###############################################################################
pushd "$WKSPC" > /dev/null

if [[ ! -d .west ]]; then
  echo ">>> west init -l config   # first-time initialisation"
  west init -l config
else
  echo ">>> west workspace already exists – skipping west init"
fi

west update
west zephyr-export

###############################################################################
# Build
###############################################################################
BUILD_DIR="$WKSPC/build"
cmake_args=(
  -DZMK_CONFIG="$WKSPC/config"
  -DZMK_EXTRA_MODULES="$CFG_REPO"
)
[[ -n "$SHIELD" ]] && shield_args=(-DSHIELD="$SHIELD")

echo ">>> Building zmk/app for $BOARD ${SHIELD:+($SHIELD)}"
west build -p -d "$BUILD_DIR" -b "$BOARD" -s zmk/app \
  -- "${shield_args[@]:-}" "${cmake_args[@]}" $EXTRA_CMAKE_ARGS

###############################################################################
# Collect firmware
###############################################################################
firmware_src=""
if [[ -f "$BUILD_DIR/zephyr/zmk.uf2" ]]; then
  firmware_src="$BUILD_DIR/zephyr/zmk.uf2"
elif [[ -f "$BUILD_DIR/zephyr/zmk.bin" ]]; then
  firmware_src="$BUILD_DIR/zephyr/zmk.bin"
fi

if [[ -n "$firmware_src" ]]; then
  ext="${firmware_src##*.}"
  if [[ -n "$SHIELD" ]]; then
    fname="${SHIELD}-${BOARD}-zmk.${ext}"
  else
    fname="${BOARD}-zmk.${ext}"
  fi
  cp "$firmware_src" "$OUT_DIR/$fname"
  echo ">>> Firmware copied to $OUT_DIR/$fname"
else
  echo ">>> Build succeeded, but no firmware produced" >&2
fi

popd > /dev/null
