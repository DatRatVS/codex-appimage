#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/DatRatVS/codex-appimage.git}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/share/codex-appimage}"

print_header() {
  cat <<'EOF'
   ___       __  ___       __    __      _                       ___
  / _ \___ _/ /_/ _ \___ _/ /_  / /_____(_)__ ___   _______  ___/ (_)__  ___ _
 / // / _ `/ __/ , _/ _ `/ __/ / __/ __/ / -_|_-<  / __/ _ \/ _  / / _ \/ _ `/
/____/\_,_/\__/_/|_|\_,_/\__/  \__/_/ /_/\__/___/  \__/\___/\_,_/_/_//_/\_, /
                                                                       /___/
EOF
}

info() {
  printf '[info] %s\n' "$*"
}

ok() {
  printf '[ ok ] %s\n' "$*"
}

warn() {
  printf '[warn] %s\n' "$*" >&2
}

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

open_tty() {
  if [[ -r /dev/tty ]]; then
    exec 3</dev/tty
  else
    die "This installer needs an interactive terminal. Try: bash -c \"\$(curl -fsSL https://codex.datr.at/build)\""
  fi
}

need() {
  command -v "$1" >/dev/null || die "Missing required command: $1"
}

repo_ready() {
  [[ -d "${INSTALL_DIR}/.git" ]]
}

sync_repo() {
  need git

  if repo_ready; then
    info "Updating ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" pull --ff-only
  else
    info "Cloning ${REPO_URL}"
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi

  ok "Repo ready at ${INSTALL_DIR}"
}

show_dependencies() {
  cat <<'EOF'

Install the dependencies for your distro, then run this installer again.

Arch Linux:
  sudo pacman -S --needed base-devel curl libarchive libicns nodejs npm python
  yay -S --needed appimagetool-bin openai-codex

Fedora:
  sudo dnf install @development-tools curl libarchive libicns nodejs npm python3
  npm install -g @openai/codex

Debian/Ubuntu:
  sudo apt update
  sudo apt install build-essential curl libarchive-tools icnsutils nodejs npm python3
  npm install -g @openai/codex

NixOS:
  nix shell nixpkgs#bash nixpkgs#curl nixpkgs#libarchive nixpkgs#libicns nixpkgs#nodejs nixpkgs#python3 nixpkgs#gcc nixpkgs#gnumake nixpkgs#pkg-config nixpkgs#appimagetool
  npm install -g @openai/codex

appimagetool must be installed and available in PATH.
EOF
}

run_build() {
  local channel="$1"

  sync_repo

  [[ -x "${INSTALL_DIR}/build-codex-appimage.sh" ]] ||
    chmod +x "${INSTALL_DIR}/build-codex-appimage.sh"

  info "Starting ${channel} build"
  if [[ "${channel}" == "stable" ]]; then
    "${INSTALL_DIR}/build-codex-appimage.sh"
  else
    "${INSTALL_DIR}/build-codex-appimage.sh" bleeding-edge
  fi
}

cleanup_build_files() {
  local removed=0
  local target

  if [[ ! -d "${INSTALL_DIR}" ]]; then
    warn "Install directory does not exist: ${INSTALL_DIR}"
    return 0
  fi

  for target in "${INSTALL_DIR}/.build" "${INSTALL_DIR}/Codex.AppDir"; do
    if [[ -e "${target}" ]]; then
      info "Removing ${target}"
      rm -rf "${target}"
      removed=1
    fi
  done

  if [[ "${removed}" -eq 1 ]]; then
    ok "Cleanup complete. Built AppImages in ${INSTALL_DIR}/dist were kept."
  else
    ok "Nothing to clean."
  fi
}

show_menu() {
  printf '\n'
  printf 'Install directory: %s\n\n' "${INSTALL_DIR}"
  printf '1) Clone/update repo only\n'
  printf '2) Build stable AppImage\n'
  printf '3) Build bleeding-edge AppImage\n'
  printf '4) Show dependency commands\n'
  printf '5) Cleanup build files\n'
  printf '6) Quit\n'
  printf '\n'
}

main() {
  print_header
  open_tty

  while true; do
    show_menu
    read -r -u 3 -p 'Choose an option [1-6]: ' choice

    case "${choice}" in
      1)
        sync_repo
        ;;
      2)
        run_build stable
        ;;
      3)
        run_build bleeding-edge
        ;;
      4)
        show_dependencies
        ;;
      5)
        cleanup_build_files
        ;;
      6 | q | Q)
        ok "Bye"
        exit 0
        ;;
      *)
        warn "Unknown option: ${choice}"
        ;;
    esac
  done
}

main "$@"
