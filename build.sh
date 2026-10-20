#!/usr/bin/env bash
# Build distributables from src/. Version comes from v.txt.
#
# Usage:
#   ./build.sh [--dev] [target ...]
#
# Targets (default: all):
#   linux    fused AppImage, repackaged        dist/<game>-<ver>-linux.AppImage
#   windows  fused .exe + DLLs, zipped         dist/<game>-<ver>-windows.zip
#   mac      fused .app bundle, zipped         dist/<game>-<ver>-mac.zip
#   web      love.js HTML5 build, zipped       dist/<game>-<ver>-web.zip
#
# --dev appends -dev to the version (v1.2.3 -> v1.2.3-dev).
# Dev builds ONLY produce the plain .love file (no platform targets).
# Runtimes come from dist/binaries (love-11.5-win64, love.app, love.js).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

GAME="$(basename "$ROOT")"
BIN="dist/binaries"

DEV=0
TARGETS=()

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --dev) DEV=1 ;;
        -h|--help) usage; exit 0 ;;
        linux|windows|mac|web) TARGETS+=("$arg") ;;
        *) echo "error: unknown argument '$arg'" >&2; usage >&2; exit 1 ;;
    esac
done
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=(linux windows mac web)

command -v zip >/dev/null 2>&1 || { echo "error: 'zip' not found" >&2; exit 1; }
[[ -d src ]] || { echo "error: src/ directory missing" >&2; exit 1; }
[[ -f v.txt ]] || { echo "error: v.txt missing" >&2; exit 1; }

VER="$(tr -d '[:space:]' < v.txt)"
[[ -n "$VER" ]] || { echo "error: v.txt is empty" >&2; exit 1; }
if [[ $DEV -eq 1 && "$VER" != *-dev ]]; then
    VER="${VER}-dev"
fi

mkdir -p dist
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Dev builds: plain .love only, straight into dist/.
if [[ $DEV -eq 1 ]]; then
    OUT="dist/${GAME}-${VER}.love"
    rm -f "$OUT"
    (cd src && zip -qr -9 "$ROOT/$OUT" .)
    echo "built $OUT (dev)"
    unzip -l "$OUT"
    exit 0
fi

FAILED=()
fail_target() { echo "!! target '$1' failed: $2" >&2; FAILED+=("$1"); }

echo "== $GAME $VER =="

# Base .love from the whole src/ tree (no per-file checks).
BASE="$WORK/$GAME.love"
(cd src && zip -qr -9 "$BASE" .)
echo "-- base game.love: $(du -h "$BASE" | cut -f1)"

# Locate appimagetool: PATH first, then a cached copy in dist/binaries,
# then download the upstream continuous build (needs network).
get_appimagetool() {
    if command -v appimagetool >/dev/null 2>&1; then
        command -v appimagetool
        return 0
    fi
    local cached="$BIN/appimagetool-x86_64.AppImage"
    if [[ -x "$cached" ]]; then
        echo "$ROOT/$cached"
        return 0
    fi
    [[ "$(uname -m)" == "x86_64" ]] || return 1
    local url="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --max-time 180 -o "$cached" "$url" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$cached" "$url" || return 1
    else
        return 1
    fi
    chmod +x "$cached"
    echo "$ROOT/$cached"
}

build_linux() {
    # Fused AppImage distribution (wiki "Official AppImage", repackage path):
    # extract runtime, fuse the game onto bin/love, retitle the desktop
    # entry, and repack everything into a new AppImage with appimagetool.
    local appimage="$BIN/love-11.5-x86_64.AppImage"
    [[ -f "$appimage" ]] || { fail_target linux "missing $appimage"; return 0; }
    local out="dist/${GAME}-${VER}-linux.AppImage"
    rm -f "$out"
    local stage="$WORK/linux"
    rm -rf "$stage"; mkdir -p "$stage"
    chmod +x "$appimage"
    (cd "$stage" && "$ROOT/$appimage" --appimage-extract >/dev/null) \
        || { fail_target linux "--appimage-extract failed"; return 0; }
    local root="$stage/squashfs-root"
    [[ -f "$root/bin/love" ]] || { fail_target linux "unexpected AppImage layout (no bin/love)"; return 0; }
    local lbsz gmsz
    lbsz=$(stat -c%s "$root/bin/love")
    gmsz=$(stat -c%s "$BASE")
    cat "$root/bin/love" "$BASE" > "$root/bin/$GAME"
    chmod +x "$root/bin/$GAME"
    [[ "$(head -c 4 "$root/bin/$GAME")" == "$(printf '\177ELF')" ]] \
        || { fail_target linux "fused binary lost ELF magic"; return 0; }
    [[ "$(stat -c%s "$root/bin/$GAME")" -eq "$((lbsz + gmsz))" ]] \
        || { fail_target linux "fused size mismatch"; return 0; }
    rm -f "$root/bin/love"
    # AppRun still execs bin/love: repoint it at the fused binary
    sed -i "s|exec \"\$APPDIR/bin/love\" \"\$@\"|exec \"\$APPDIR/bin/${GAME}\" \"\$@\"|" "$root/AppRun"
    grep -q "exec \"\$APPDIR/bin/${GAME}\" \"\$@\"" "$root/AppRun" \
        || { fail_target linux "AppRun repoint failed"; return 0; }
    # retitle the desktop entry for the game (icon stays: love.svg ships)
    local title
    title="$(tr '-' ' ' <<<"$GAME" | awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)} 1')"
    sed -i -e "s/^Name=.*/Name=${title}/" \
           -e "s/^Exec=.*/Exec=${GAME} %f/" \
           -e "s/^Comment=.*/Comment=${title}/" \
           -e "/^NoDisplay=/d" "$root/love.desktop"
    grep -q "^Exec=${GAME} %f" "$root/love.desktop" \
        || { fail_target linux "desktop retitle failed"; return 0; }
    local tool
    tool="$(get_appimagetool)" \
        || { fail_target linux "appimagetool not found (install it or allow the download)"; return 0; }
    ARCH=x86_64 VERSION="$VER" "$tool" "$root" "$ROOT/$out" >/dev/null \
        || { fail_target linux "appimagetool repack failed"; return 0; }
    chmod +x "$ROOT/$out"
    [[ -f "$ROOT/$out" ]] || { fail_target linux "no AppImage produced"; return 0; }
    echo "built $out"
}

build_windows() {
    local runtime="$BIN/love-11.5-win64"
    [[ -f "$runtime/love.exe" ]] || { fail_target windows "missing $runtime/love.exe"; return 0; }
    local out="dist/${GAME}-${VER}-windows.zip"
    rm -f "$out"
    local stage="$WORK/windows"
    rm -rf "$stage"; mkdir -p "$stage"
    # fused executable: runtime + game appended
    cat "$runtime/love.exe" "$BASE" > "$stage/${GAME}.exe"
    cp "$runtime"/*.dll "$stage"/
    (cd "$stage" && zip -qr -9 "$ROOT/$out" .)
    echo "built $out"
}

build_mac() {
    local app="$BIN/love.app"
    [[ -x "$app/Contents/MacOS/love" ]] || { fail_target mac "missing $app/Contents/MacOS/love"; return 0; }
    local out="dist/${GAME}-${VER}-mac.zip"
    rm -f "$out"
    local stage="$WORK/mac"
    rm -rf "$stage"; mkdir -p "$stage"
    cp -r "$app" "$stage/${GAME}.app"
    cp "$BASE" "$stage/${GAME}.app/Contents/Resources/${GAME}.love"
    # -y keeps framework symlinks intact inside the bundle
    (cd "$stage" && zip -qr -9 -y "$ROOT/$out" "${GAME}.app")
    echo "built $out"
}

build_web() {
    command -v node >/dev/null 2>&1 || { fail_target web "node not found"; return 0; }
    local out="dist/${GAME}-${VER}-web.zip"
    rm -f "$out"
    local stagedir="$WORK/web"
    rm -rf "$stagedir"
    if [[ -x "$BIN/love.js/index.js" && -d "$BIN/love.js/node_modules" ]]; then
        node "$BIN/love.js/index.js" -t "$GAME" "$BASE" "$stagedir" \
            || { fail_target web "bundled love.js build failed"; return 0; }
    else
        npx --yes love.js -t "$GAME" "$BASE" "$stagedir" \
            || { fail_target web "npx love.js failed (needs network)"; return 0; }
    fi
    (cd "$WORK" && zip -qr -9 "$ROOT/$out" web)
    echo "built $out"
}

for t in "${TARGETS[@]}"; do
    "build_$t"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "failed targets: ${FAILED[*]}" >&2
    exit 1
fi
echo "done."
