#!/usr/bin/env bash
set -euo pipefail

#    ___       __  ___       __    __      _                       ___          
#   / _ \___ _/ /_/ _ \___ _/ /_  / /_____(_)__ ___   _______  ___/ (_)__  ___ _
#  / // / _ `/ __/ , _/ _ `/ __/ / __/ __/ / -_|_-<  / __/ _ \/ _  / / _ \/ _ `/
# /____/\_,_/\__/_/|_|\_,_/\__/  \__/_/ /_/\__/___/  \__/\___/\_,_/_/_//_/\_, / 
#                                                                        /___/  

print_banner() {
  cat <<'EOF'
   ___       __  ___       __    __      _                       ___
  / _ \___ _/ /_/ _ \___ _/ /_  / /_____(_)__ ___   _______  ___/ (_)__  ___ _
 / // / _ `/ __/ , _/ _ `/ __/ / __/ __/ / -_|_-<  / __/ _ \/ _  / / _ \/ _ `/
/____/\_,_/\__/_/|_|\_,_/\__/  \__/_/ /_/\__/___/  \__/\___/\_,_/_/_//_/\_, /
                                                                       /___/
EOF
}

countdown() {
  printf '\nStarting build in '
  for n in 5 4 3 2 1; do
    printf '%s... ' "${n}"
    sleep 1
  done
  printf 'go\n\n'
}

log_step() {
  printf '\n[step] %s\n' "$*"
}

log_info() {
  printf '[info] %s\n' "$*"
}

log_ok() {
  printf '[ ok ] %s\n' "$*"
}

log_skip() {
  printf '[skip] %s\n' "$*"
}

log_warn() {
  printf '[warn] %s\n' "$*" >&2
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

print_banner
countdown

BUILD_CHANNEL="${1:-stable}"
case "${BUILD_CHANNEL}" in
  stable | bleeding-edge) ;;
  *)
    die "Unknown channel '${BUILD_CHANNEL}'. Usage: $0 [stable|bleeding-edge]"
    ;;
esac

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
BETTER_SQLITE3_VERSION="${BETTER_SQLITE3_VERSION:-}"
NODE_PTY_VERSION="${NODE_PTY_VERSION:-}"

CODEX_ZIP="Codex-darwin-arm64-${CODEX_VERSION}.zip"
CODEX_URL="https://persistent.oaistatic.com/codex-app-prod/${CODEX_ZIP}"
DEFAULT_CODEX_SHA256="c325741ec38a801889518d62ad756db7d6df1035d755db90a046373c96fb5198"
CODEX_SHA256="${CODEX_SHA256:-${DEFAULT_CODEX_SHA256}}"
CODEX_APPCAST_URL="${CODEX_APPCAST_URL:-https://persistent.oaistatic.com/codex-app-prod/appcast.xml}"

BETTER_SQLITE3_SHA256="${BETTER_SQLITE3_SHA256:-}"
NODE_PTY_SHA256="${NODE_PTY_SHA256:-}"
NIXOS_ELECTRON_LIBRARY_PATH=""

ELECTRON_ZIP="electron-v${ELECTRON_VERSION}-linux-x64.zip"
ELECTRON_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/${ELECTRON_ZIP}"

need() {
  command -v "$1" >/dev/null || {
    die "Missing required command: $1"
  }
}

is_nixos() {
  [[ -r /etc/os-release ]] && grep -q '^ID=nixos$' /etc/os-release
}

prepare_nixos_npm_prefix() {
  local npm_prefix

  is_nixos || return 0

  npm_prefix="$(npm config get prefix)"
  if [[ "${npm_prefix}" == "${HOME}"/* ]]; then
    mkdir -p "${npm_prefix}/lib"
    log_ok "Prepared NixOS npm prefix at ${npm_prefix}"
  else
    log_skip "NixOS npm prefix is outside HOME: ${npm_prefix}"
  fi
}

resolve_nixos_electron_library_path() {
  local package
  local package_path
  local lib_paths=()
  local old_ifs
  local nixos_electron_packages=(
    glib.out
    gtk3
    nss
    nspr
    at-spi2-core
    cups.lib
    dbus.lib
    expat
    libdrm
    libxkbcommon
    mesa
    libgbm
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    pango.out
    cairo
    alsa-lib
    freetype
    fontconfig.lib
    libglvnd
    libxcursor
    libxi
    libxtst
    libxscrnsaver
    libxshmfence
    libgpg-error
  )

  is_nixos || return 0

  if ! command -v nix >/dev/null; then
    log_skip "NixOS detected, but nix is not available; not embedding Electron library paths"
    return 0
  fi

  for package in "${nixos_electron_packages[@]}"; do
    package_path="$(nix eval --raw "nixpkgs#${package}" 2>/dev/null || true)"
    if [[ -n "${package_path}" && -d "${package_path}/lib" ]]; then
      lib_paths+=("${package_path}/lib")
    fi
  done

  if [[ "${#lib_paths[@]}" -eq 0 ]]; then
    log_skip "Could not resolve NixOS Electron library paths"
    return 0
  fi

  old_ifs="${IFS}"
  IFS=:
  NIXOS_ELECTRON_LIBRARY_PATH="${lib_paths[*]}"
  IFS="${old_ifs}"
  log_ok "Resolved ${#lib_paths[@]} NixOS Electron library paths"
}

codex_vendor_root_for_binary() {
  local binary="$1"
  local binary_dir
  local arch_root

  binary_dir="$(cd "$(dirname "${binary}")" && pwd)"
  arch_root="$(cd "${binary_dir}/.." && pwd)"
  if [[ "$(basename "${binary_dir}")" == "codex" && "$(basename "${arch_root}")" == "x86_64-unknown-linux-musl" ]]; then
    printf '%s\n' "${arch_root}"
  fi
}

copy_codex_cli_binary() {
  local binary="$1"
  local label="$2"
  local vendor_root="${3:-}"

  [[ -n "${vendor_root}" ]] || vendor_root="$(codex_vendor_root_for_binary "${binary}")"

  mkdir -p "${APPDIR}/usr/lib/codex-cli/path"
  cp -L "${binary}" "${APPDIR}/usr/lib/codex-cli/codex"

  if [[ -n "${vendor_root}" && -x "${vendor_root}/path/rg" ]]; then
    cp -L "${vendor_root}/path/rg" "${APPDIR}/usr/lib/codex-cli/path/rg"
  fi

  cat >"${APPDIR}/usr/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPDIR_ROOT="${APPDIR:-$(cd "${HERE}/../.." && pwd)}"
cli_dir="${APPDIR_ROOT}/usr/lib/codex-cli"

if [[ -x "${cli_dir}/path/rg" ]]; then
  export PATH="${cli_dir}/path:${PATH:-}"
fi

exec "${cli_dir}/codex" "$@"
EOF
  chmod +x "${APPDIR}/usr/bin/codex"
  log_ok "Bundled Codex CLI native binary from ${label}: ${binary}"
}

find_codex_vendor_binary_in_root() {
  local root="$1"

  [[ -d "${root}" ]] || return 0
  find "${root}" \
    \( \
      -path '*/@openai/codex/vendor/x86_64-unknown-linux-musl/codex/codex' \
      -o -path '*/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/codex/codex' \
    \) \
    -type f \
    -executable \
    -print \
    -quit
}

find_codex_npm_vendor_binary() {
  local candidate
  local npm_prefix
  local roots=()

  if npm_prefix="$(npm config get prefix 2>/dev/null)" && [[ -n "${npm_prefix}" ]]; then
    roots+=("${npm_prefix}/lib/node_modules")
  fi
  roots+=("${HOME}/.npm-global/lib/node_modules")

  if command -v npm >/dev/null && npm_root="$(npm root -g 2>/dev/null)" && [[ -n "${npm_root}" ]]; then
    roots+=("${npm_root}")
  fi

  for candidate in "${roots[@]}"; do
    find_codex_vendor_binary_in_root "${candidate}"
  done | awk 'NF && !seen[$0]++ { print; exit }'
}

is_transient_appimage_path() {
  [[ "$1" == /tmp/.mount_*/* ]]
}

bundle_codex_cli() {
  local codex_path
  local codex_real_path
  local codex_package_root
  local codex_vendor_binary
  local npm_vendor_binary

  if [[ -n "${CODEX_CLI_PATH:-}" ]]; then
    if is_transient_appimage_path "${CODEX_CLI_PATH}"; then
      log_skip "Ignoring transient AppImage CODEX_CLI_PATH: ${CODEX_CLI_PATH}"
    elif [[ -x "${CODEX_CLI_PATH}" ]]; then
      copy_codex_cli_binary "${CODEX_CLI_PATH}" "CODEX_CLI_PATH"
      return 0
    else
      log_warn "CODEX_CLI_PATH is set but not executable: ${CODEX_CLI_PATH}"
    fi
  fi

  npm_vendor_binary="$(find_codex_npm_vendor_binary)"
  if [[ -n "${npm_vendor_binary}" ]]; then
    copy_codex_cli_binary "${npm_vendor_binary}" "npm global install"
    return 0
  fi

  if command -v codex >/dev/null; then
    codex_path="$(command -v codex)"
    codex_real_path="$(readlink -f "${codex_path}")"
    codex_package_root="$(cd "$(dirname "${codex_real_path}")/.." && pwd)"
    codex_vendor_binary="$(find_codex_vendor_binary_in_root "${codex_package_root}")"

    if [[ -n "${codex_vendor_binary}" ]]; then
      copy_codex_cli_binary "${codex_vendor_binary}" "host package"
    elif [[ -f "${codex_path}" && -x "${codex_path}" ]]; then
      cp -L "${codex_path}" "${APPDIR}/usr/bin/codex"
      log_ok "Bundled Codex CLI from ${codex_path}"
    else
      log_warn "Codex CLI found at ${codex_path}, but it is not an executable file; AppImage will use host codex at runtime"
    fi
  else
    log_skip "Codex CLI not found in PATH; AppImage will use host codex at runtime"
  fi
}

download() {
  local url="$1"
  local dest="$2"
  if [[ -f "${dest}" ]]; then
    log_skip "Using cached $(basename "${dest}")"
    return 0
  fi
  log_info "Downloading ${url}"
  curl -L --fail --retry 3 -o "${dest}" "${url}"
  log_ok "Downloaded $(basename "${dest}")"
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  if [[ -z "${expected}" ]]; then
    log_skip "No checksum configured for $(basename "${file}")"
    return 0
  fi
  log_info "Verifying $(basename "${file}")"
  echo "${expected}  ${file}" | sha256sum -c --status
  log_ok "Checksum passed for $(basename "${file}")"
}

resolve_bleeding_edge_codex() {
  local appcast="${DOWNLOADS}/appcast.xml"

  log_step "Resolving bleeding-edge Codex desktop archive"
  rm -f "${appcast}"
  download "${CODEX_APPCAST_URL}" "${appcast}"

  CODEX_URL="$(
    python - "${appcast}" <<'PY'
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    raise SystemExit("missing channel in appcast")

for item in channel.findall("item"):
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue
    url = enclosure.attrib.get("url", "")
    if "Codex-darwin-arm64-" in url and url.endswith(".zip"):
        print(url)
        break
else:
    raise SystemExit("could not find Codex darwin arm64 zip in appcast")
PY
  )"
  CODEX_ZIP="$(basename "${CODEX_URL}")"
  CODEX_VERSION="${CODEX_ZIP#Codex-darwin-arm64-}"
  CODEX_VERSION="${CODEX_VERSION%.zip}"
  if [[ "${CODEX_SHA256}" == "${DEFAULT_CODEX_SHA256}" ]]; then
    CODEX_SHA256=""
  fi

  log_ok "Bleeding-edge Codex version: ${CODEX_VERSION}"
  log_info "Codex URL: ${CODEX_URL}"
}

log_step "Checking required commands"
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
log_ok "Required commands found"
prepare_nixos_npm_prefix
resolve_nixos_electron_library_path

log_step "Preparing workspace"
rm -rf "${SRC_DIR}" "${ELECTRON_DIR}" "${APPDIR}" "${OUT}"
mkdir -p "${DOWNLOADS}" "${SRC_DIR}" "${ELECTRON_DIR}" "${OUT}"
log_info "Build directory: ${BUILD_ROOT}"
log_info "Output directory: ${OUT}"
log_info "Channel: ${BUILD_CHANNEL}"

if [[ "${BUILD_CHANNEL}" == "bleeding-edge" ]]; then
  resolve_bleeding_edge_codex
fi

log_step "Downloading source archives"
download "${CODEX_URL}" "${DOWNLOADS}/${CODEX_ZIP}"
download "${ELECTRON_URL}" "${DOWNLOADS}/${ELECTRON_ZIP}"

log_step "Verifying source archives"
verify_sha256 "${DOWNLOADS}/${CODEX_ZIP}" "${CODEX_SHA256}"

log_step "Extracting Codex desktop archive"
mkdir -p "${SRC_DIR}/dmg"
bsdtar -xf "${DOWNLOADS}/${CODEX_ZIP}" -C "${SRC_DIR}/dmg"

mac_app="$(
  find "${SRC_DIR}/dmg" -maxdepth 4 -type d -name '*.app' ! -path '*/__MACOSX/*' -print -quit
)"
[[ -n "${mac_app}" ]] || {
  die "Could not find .app bundle in ${DOWNLOADS}/${CODEX_ZIP}"
}
log_ok "Found app bundle: ${mac_app}"

icon_icns="$(
  find "${mac_app}/Contents/Resources" -maxdepth 1 -type f -name '*.icns' ! -name '._*' -print -quit
)"
[[ -n "${icon_icns}" ]] || {
  die "Could not find application icon in ${mac_app}/Contents/Resources"
}
log_ok "Found icon: ${icon_icns}"

log_step "Extracting app.asar"
npx --yes asar extract \
  "${mac_app}/Contents/Resources/app.asar" \
  "${SRC_DIR}/app-extracted"
log_ok "Extracted app.asar"

if [[ -d "${mac_app}/Contents/Resources/app.asar.unpacked" ]]; then
  cp -a "${mac_app}/Contents/Resources/app.asar.unpacked" "${SRC_DIR}/app.asar.unpacked"
  log_ok "Copied app.asar.unpacked"
fi

log_step "Removing macOS-specific files"
rm -rf "${SRC_DIR}/app-extracted/node_modules/sparkle-darwin"
find "${SRC_DIR}/app-extracted" -type f \( -name '*.dylib' -o -name 'sparkle.node' \) -delete
log_ok "Removed macOS native artifacts"

app_better_sqlite3_ver="$(node -p "require('${SRC_DIR}/app-extracted/node_modules/better-sqlite3/package.json').version")"
app_node_pty_ver="$(node -p "require('${SRC_DIR}/app-extracted/node_modules/node-pty/package.json').version")"

if [[ -n "${BETTER_SQLITE3_VERSION}" && "${app_better_sqlite3_ver}" != "${BETTER_SQLITE3_VERSION}" ]]; then
  die "better-sqlite3 version mismatch: app=${app_better_sqlite3_ver}, override=${BETTER_SQLITE3_VERSION}"
fi
if [[ -n "${NODE_PTY_VERSION}" && "${app_node_pty_ver}" != "${NODE_PTY_VERSION}" ]]; then
  die "node-pty version mismatch: app=${app_node_pty_ver}, override=${NODE_PTY_VERSION}"
fi

BETTER_SQLITE3_VERSION="${app_better_sqlite3_ver}"
NODE_PTY_VERSION="${app_node_pty_ver}"
BETTER_SQLITE3_TGZ="better-sqlite3-${BETTER_SQLITE3_VERSION}.tgz"
BETTER_SQLITE3_URL="https://registry.npmjs.org/better-sqlite3/-/${BETTER_SQLITE3_TGZ}"
NODE_PTY_TGZ="node-pty-${NODE_PTY_VERSION}.tgz"
NODE_PTY_URL="https://registry.npmjs.org/node-pty/-/${NODE_PTY_TGZ}"
log_ok "Detected native module versions: better-sqlite3 ${BETTER_SQLITE3_VERSION}, node-pty ${NODE_PTY_VERSION}"

log_step "Downloading native module sources"
download "${BETTER_SQLITE3_URL}" "${DOWNLOADS}/${BETTER_SQLITE3_TGZ}"
download "${NODE_PTY_URL}" "${DOWNLOADS}/${NODE_PTY_TGZ}"

log_step "Verifying native module sources"
verify_sha256 "${DOWNLOADS}/${BETTER_SQLITE3_TGZ}" "${BETTER_SQLITE3_SHA256}"
verify_sha256 "${DOWNLOADS}/${NODE_PTY_TGZ}" "${NODE_PTY_SHA256}"

log_step "Rebuilding native modules for Linux/Electron"
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
log_ok "Rebuilt native modules"

log_step "Installing rebuilt native modules into app"
rm -rf "${SRC_DIR}/app-extracted/node_modules/better-sqlite3"
rm -rf "${SRC_DIR}/app-extracted/node_modules/node-pty"
cp -a "${SRC_DIR}/native-build/node_modules/better-sqlite3" "${SRC_DIR}/app-extracted/node_modules/"
cp -a "${SRC_DIR}/native-build/node_modules/node-pty" "${SRC_DIR}/app-extracted/node_modules/"
log_ok "Installed rebuilt native modules"

log_step "Packing Linux app.asar"
npx --yes asar pack \
  "${SRC_DIR}/app-extracted" \
  "${SRC_DIR}/app.asar" \
  --unpack "{*.node,*.so}"
log_ok "Packed Linux app.asar"

log_step "Extracting Linux Electron ${ELECTRON_VERSION}"
bsdtar -xf "${DOWNLOADS}/${ELECTRON_ZIP}" -C "${ELECTRON_DIR}"
[[ -x "${ELECTRON_DIR}/electron" ]] || {
  die "Could not find Electron executable after extracting ${DOWNLOADS}/${ELECTRON_ZIP}"
}
log_ok "Extracted Linux Electron"

log_step "Extracting application icon"
mkdir -p "${SRC_DIR}/icon"
icns2png -x -o "${SRC_DIR}/icon" "${icon_icns}" >/dev/null
icon_png="$(
  find "${SRC_DIR}/icon" -maxdepth 1 -type f -name '*512x512*.png' -print -quit
)"
[[ -n "${icon_png}" ]] ||
  icon_png="$(find "${SRC_DIR}/icon" -maxdepth 1 -type f -name '*.png' -print | sort -V | tail -n1)"
[[ -n "${icon_png}" ]] || {
  die "Could not extract an application icon"
}
log_ok "Using icon: ${icon_png}"

log_step "Creating AppDir"
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

bundle_codex_cli

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

APPDIR_ROOT="${APPDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
appdir="${APPDIR_ROOT}/usr/lib/openai-codex-desktop"
electron="${APPDIR_ROOT}/usr/lib/electron/electron"
webview_dir="${appdir}/content/webview"
nixos_electron_library_path="__NIXOS_ELECTRON_LIBRARY_PATH__"

if [[ -n "${nixos_electron_library_path}" ]]; then
  export LD_LIBRARY_PATH="${nixos_electron_library_path}:${LD_LIBRARY_PATH:-}"
fi

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
python - "${APPDIR}/usr/bin/codex-desktop" "${NIXOS_ELECTRON_LIBRARY_PATH}" <<'PY'
import sys

path = sys.argv[1]
library_path = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("__NIXOS_ELECTRON_LIBRARY_PATH__", library_path)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PY
chmod +x "${APPDIR}/usr/bin/codex-desktop"

cp -a "${icon_png}" "${APPDIR}/openai-codex-desktop.png"
cat >"${APPDIR}/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export APPDIR="${APPDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
exec "${APPDIR}/usr/bin/codex-desktop" "$@"
EOF
chmod +x "${APPDIR}/AppRun"

log_ok "Built AppDir at ${APPDIR}"

if command -v appimagetool >/dev/null; then
  log_step "Packaging AppImage"
  ARCH=x86_64 appimagetool "${APPDIR}" "${OUT}/OpenAI-Codex-x86_64.AppImage"
  log_ok "Built ${OUT}/OpenAI-Codex-x86_64.AppImage"
else
  log_skip "appimagetool is not installed; install it or put it on PATH, then rerun this script."
fi
