#!/usr/bin/env bash
set -euo pipefail

#    ___       __  ___       __    __      _                       ___          
#   / _ \___ _/ /_/ _ \___ _/ /_  / /_____(_)__ ___   _______  ___/ (_)__  ___ _
#  / // / _ `/ __/ , _/ _ `/ __/ / __/ __/ / -_|_-<  / __/ _ \/ _  / / _ \/ _ `/
# /____/\_,_/\__/_/|_|\_,_/\__/  \__/_/ /_/\__/___/  \__/\___/\_,_/_/_//_/\_, / 
#                                                                        /___/  

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${ROOT}/.build"
SRC_DIR="${BUILD_ROOT}/src"
DOWNLOADS="${BUILD_ROOT}/downloads"
ELECTRON_DIR="${BUILD_ROOT}/electron"
APPDIR="${ROOT}/Codex.AppDir"
OUT="${ROOT}/dist"

CODEX_VERSION="${CODEX_VERSION:-26.429.61741}"
ELECTRON_VERSION="${ELECTRON_VERSION:-39.5.2}"
ELECTRON_REBUILD_TARGET="${ELECTRON_REBUILD_TARGET:-39.0.0}"
BETTER_SQLITE3_VERSION="${BETTER_SQLITE3_VERSION:-12.8.0}"
NODE_PTY_VERSION="${NODE_PTY_VERSION:-1.1.0}"

CODEX_ZIP="Codex-darwin-arm64-${CODEX_VERSION}.zip"
CODEX_URL="https://persistent.oaistatic.com/codex-app-prod/${CODEX_ZIP}"
CODEX_SHA256="${CODEX_SHA256:-c325741ec38a801889518d62ad756db7d6df1035d755db90a046373c96fb5198}"

BETTER_SQLITE3_TGZ="better-sqlite3-${BETTER_SQLITE3_VERSION}.tgz"
BETTER_SQLITE3_URL="https://registry.npmjs.org/better-sqlite3/-/${BETTER_SQLITE3_TGZ}"
BETTER_SQLITE3_SHA256="${BETTER_SQLITE3_SHA256:-2602a5726d0a9d8e6be407c59bc125e605110eda8e3b04e7ef8d6ddf762c9122}"

NODE_PTY_TGZ="node-pty-${NODE_PTY_VERSION}.tgz"
NODE_PTY_URL="https://registry.npmjs.org/node-pty/-/${NODE_PTY_TGZ}"
NODE_PTY_SHA256="${NODE_PTY_SHA256:-c7517f19083ddcb05f276904680eb2b11a6b5ecab778b8e4e5685a6d645b3f60}"

ELECTRON_ZIP="electron-v${ELECTRON_VERSION}-linux-x64.zip"
ELECTRON_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_ZIP}"

need() {
  command -v "$1" >/dev/null || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

download() {
  local url="$1"
  local dest="$2"
  [[ -f "${dest}" ]] && return 0
  echo "Downloading ${url}..."
  curl -L --fail --retry 3 -o "${dest}" "${url}"
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  [[ -z "${expected}" ]] && return 0
  echo "${expected}  ${file}" | sha256sum -c -
}

need bsdtar
need cp
need curl
need find
need icns2png
need node
need npm
need npx
need python
need sha256sum

rm -rf "${SRC_DIR}" "${ELECTRON_DIR}" "${APPDIR}" "${OUT}"
mkdir -p "${DOWNLOADS}" "${SRC_DIR}" "${ELECTRON_DIR}" "${OUT}"

download "${CODEX_URL}" "${DOWNLOADS}/${CODEX_ZIP}"
download "${BETTER_SQLITE3_URL}" "${DOWNLOADS}/${BETTER_SQLITE3_TGZ}"
download "${NODE_PTY_URL}" "${DOWNLOADS}/${NODE_PTY_TGZ}"
download "${ELECTRON_URL}" "${DOWNLOADS}/${ELECTRON_ZIP}"

verify_sha256 "${DOWNLOADS}/${CODEX_ZIP}" "${CODEX_SHA256}"
verify_sha256 "${DOWNLOADS}/${BETTER_SQLITE3_TGZ}" "${BETTER_SQLITE3_SHA256}"
verify_sha256 "${DOWNLOADS}/${NODE_PTY_TGZ}" "${NODE_PTY_SHA256}"

echo "Extracting Codex desktop archive..."
mkdir -p "${SRC_DIR}/dmg"
bsdtar -xf "${DOWNLOADS}/${CODEX_ZIP}" -C "${SRC_DIR}/dmg"

mac_app="$(
  find "${SRC_DIR}/dmg" -maxdepth 4 -type d -name '*.app' ! -path '*/__MACOSX/*' -print -quit
)"
[[ -n "${mac_app}" ]] || {
  echo "Could not find .app bundle in ${DOWNLOADS}/${CODEX_ZIP}" >&2
  exit 1
}

icon_icns="$(
  find "${mac_app}/Contents/Resources" -maxdepth 1 -type f -name '*.icns' ! -name '._*' -print -quit
)"
[[ -n "${icon_icns}" ]] || {
  echo "Could not find application icon in ${mac_app}/Contents/Resources" >&2
  exit 1
}

echo "Extracting app.asar..."
npx --yes asar extract \
  "${mac_app}/Contents/Resources/app.asar" \
  "${SRC_DIR}/app-extracted"

if [[ -d "${mac_app}/Contents/Resources/app.asar.unpacked" ]]; then
  cp -a "${mac_app}/Contents/Resources/app.asar.unpacked" "${SRC_DIR}/app.asar.unpacked"
fi

rm -rf "${SRC_DIR}/app-extracted/node_modules/sparkle-darwin"
find "${SRC_DIR}/app-extracted" -type f \( -name '*.dylib' -o -name 'sparkle.node' \) -delete

bs3_ver="$(node -p "require('${SRC_DIR}/app-extracted/node_modules/better-sqlite3/package.json').version")"
npty_ver="$(node -p "require('${SRC_DIR}/app-extracted/node_modules/node-pty/package.json').version")"

[[ "${bs3_ver}" == "${BETTER_SQLITE3_VERSION}" ]] || {
  echo "better-sqlite3 version mismatch: app=${bs3_ver}, script=${BETTER_SQLITE3_VERSION}" >&2
  exit 1
}
[[ "${npty_ver}" == "${NODE_PTY_VERSION}" ]] || {
  echo "node-pty version mismatch: app=${npty_ver}, script=${NODE_PTY_VERSION}" >&2
  exit 1
}

echo "Rebuilding native modules for Linux/Electron..."
mkdir -p "${SRC_DIR}/native-build"
cat >"${SRC_DIR}/native-build/package.json" <<'EOF'
{
  "name": "codex-desktop-native-rebuild",
  "private": true,
  "license": "UNLICENSED"
}
EOF

(
  cd "${SRC_DIR}/native-build"
  npm install \
    --ignore-scripts \
    --no-audit \
    --no-fund \
    "${DOWNLOADS}/${BETTER_SQLITE3_TGZ}" \
    "${DOWNLOADS}/${NODE_PTY_TGZ}"

  export npm_config_runtime=electron
  export npm_config_target="${ELECTRON_REBUILD_TARGET}"
  export npm_config_disturl="https://electronjs.org/headers"
  export npm_config_build_from_source=true

  npx --yes @electron/rebuild -v "${ELECTRON_REBUILD_TARGET}" --force
)

rm -rf "${SRC_DIR}/app-extracted/node_modules/better-sqlite3"
rm -rf "${SRC_DIR}/app-extracted/node_modules/node-pty"
cp -a "${SRC_DIR}/native-build/node_modules/better-sqlite3" "${SRC_DIR}/app-extracted/node_modules/"
cp -a "${SRC_DIR}/native-build/node_modules/node-pty" "${SRC_DIR}/app-extracted/node_modules/"

echo "Packing Linux app.asar..."
npx --yes asar pack \
  "${SRC_DIR}/app-extracted" \
  "${SRC_DIR}/app.asar" \
  --unpack "{*.node,*.so}"

echo "Extracting Linux Electron ${ELECTRON_VERSION}..."
bsdtar -xf "${DOWNLOADS}/${ELECTRON_ZIP}" -C "${ELECTRON_DIR}"
[[ -x "${ELECTRON_DIR}/electron" ]] || {
  echo "Could not find Electron executable after extracting ${DOWNLOADS}/${ELECTRON_ZIP}" >&2
  exit 1
}

mkdir -p "${SRC_DIR}/icon"
icns2png -x -o "${SRC_DIR}/icon" "${icon_icns}" >/dev/null
icon_png="$(
  find "${SRC_DIR}/icon" -maxdepth 1 -type f -name '*512x512*.png' -print -quit
)"
[[ -n "${icon_png}" ]] ||
  icon_png="$(find "${SRC_DIR}/icon" -maxdepth 1 -type f -name '*.png' -print | sort -V | tail -n1)"
[[ -n "${icon_png}" ]] || {
  echo "Could not extract an application icon" >&2
  exit 1
}

echo "Creating AppDir..."
mkdir -p \
  "${APPDIR}/usr/bin" \
  "${APPDIR}/usr/lib/electron" \
  "${APPDIR}/usr/lib/openai-codex-desktop/resources" \
  "${APPDIR}/usr/lib/openai-codex-desktop/content" \
  "${APPDIR}/usr/share/applications" \
  "${APPDIR}/usr/share/icons/hicolor/512x512/apps"

cp -a "${ELECTRON_DIR}/." "${APPDIR}/usr/lib/electron/"
cp -a "${SRC_DIR}/app.asar" "${APPDIR}/usr/lib/openai-codex-desktop/resources/app.asar"
if [[ -d "${SRC_DIR}/app.asar.unpacked" ]]; then
  cp -a "${SRC_DIR}/app.asar.unpacked" "${APPDIR}/usr/lib/openai-codex-desktop/resources/"
fi
if [[ -d "${SRC_DIR}/app-extracted/webview" ]]; then
  cp -a "${SRC_DIR}/app-extracted/webview" "${APPDIR}/usr/lib/openai-codex-desktop/content/"
fi
cp -a "${icon_png}" "${APPDIR}/usr/share/icons/hicolor/512x512/apps/openai-codex-desktop.png"

if command -v codex >/dev/null; then
  codex_path="$(command -v codex)"
  if [[ -f "${codex_path}" && -x "${codex_path}" ]]; then
    cp -L "${codex_path}" "${APPDIR}/usr/bin/codex"
  fi
fi

cat >"${APPDIR}/Codex.desktop" <<'EOF'
[Desktop Entry]
Name=OpenAI Codex
Comment=OpenAI Codex desktop app
Exec=codex-desktop %U
Icon=openai-codex-desktop
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=Codex
EOF
cp "${APPDIR}/Codex.desktop" "${APPDIR}/usr/share/applications/Codex.desktop"

cat >"${APPDIR}/usr/bin/codex-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPDIR_ROOT="$(cd "${HERE}/../.." && pwd)"
appdir="${APPDIR_ROOT}/usr/lib/openai-codex-desktop"
electron="${APPDIR_ROOT}/usr/lib/electron/electron"
webview_dir="${appdir}/content/webview"

if [[ -z "${CODEX_CLI_PATH:-}" ]]; then
  if [[ -x "${APPDIR_ROOT}/usr/bin/codex" ]]; then
    export CODEX_CLI_PATH="${APPDIR_ROOT}/usr/bin/codex"
  else
    export CODEX_CLI_PATH="$(command -v codex || true)"
  fi
fi

export BUILD_FLAVOR="${BUILD_FLAVOR:-prod}"
export NODE_ENV="${NODE_ENV:-production}"
export ELECTRON_RENDERER_URL="${ELECTRON_RENDERER_URL:-http://localhost:5175/}"

http_pid=""
electron_pid=""
tmpdir=""

cleanup() {
  [[ -n "${electron_pid}" ]] && wait "${electron_pid}" 2>/dev/null || true
  [[ -n "${http_pid}" ]] && kill "${http_pid}" 2>/dev/null || true
  [[ -n "${http_pid}" ]] && wait "${http_pid}" 2>/dev/null || true
  [[ -n "${tmpdir}" ]] && rm -rf "${tmpdir}"
}

forward_signal() {
  local sig="$1"
  if [[ -n "${electron_pid}" ]] && kill -0 "${electron_pid}" 2>/dev/null; then
    kill -"${sig}" "${electron_pid}" 2>/dev/null || true
    wait "${electron_pid}" 2>/dev/null || true
  fi
  exit 0
}

trap cleanup EXIT
trap 'forward_signal HUP' HUP
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

if [[ -d "${webview_dir}" ]] && find "${webview_dir}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  tmpdir="$(mktemp -d)"
  ready_file="${tmpdir}/ready"
  fail_file="${tmpdir}/fail"

  python - 5175 "${webview_dir}" "${ready_file}" "${fail_file}" >/dev/null 2>&1 <<'PY' &
import http.server
import os
import socketserver
import sys

port = int(sys.argv[1])
root = sys.argv[2]
ready_file = sys.argv[3]
fail_file = sys.argv[4]

os.chdir(root)

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

class TCPServer(socketserver.TCPServer):
    allow_reuse_address = True

try:
    with TCPServer(("127.0.0.1", port), Handler) as httpd:
        with open(ready_file, "w") as f:
            f.write("ok")
        httpd.serve_forever()
except Exception as e:
    with open(fail_file, "w") as f:
        f.write(str(e))
    raise
PY
  http_pid=$!

  for _ in {1..50}; do
    [[ -f "${ready_file}" ]] && break
    if [[ -f "${fail_file}" ]]; then
      echo "Failed to start local webview server on 127.0.0.1:5175" >&2
      cat "${fail_file}" >&2
      exit 1
    fi
    kill -0 "${http_pid}" 2>/dev/null || {
      echo "Local webview server exited before becoming ready" >&2
      exit 1
    }
    sleep 0.1
  done

  [[ -f "${ready_file}" ]] || {
    echo "Timed out waiting for local webview server on 127.0.0.1:5175" >&2
    exit 1
  }
fi

"${electron}" \
  --enable-sandbox \
  --ozone-platform-hint=auto \
  --class=Codex \
  "${appdir}/resources/app.asar" \
  "$@" &
electron_pid=$!
wait "${electron_pid}"
EOF
chmod +x "${APPDIR}/usr/bin/codex-desktop"

cp -a "${icon_png}" "${APPDIR}/openai-codex-desktop.png"
ln -s usr/bin/codex-desktop "${APPDIR}/AppRun"

echo "Built AppDir at ${APPDIR}"

if command -v appimagetool >/dev/null; then
  ARCH=x86_64 appimagetool "${APPDIR}" "${OUT}/OpenAI-Codex-x86_64.AppImage"
  echo "Built ${OUT}/OpenAI-Codex-x86_64.AppImage"
else
  echo "appimagetool is not installed; install it or put it on PATH, then rerun this script."
fi
