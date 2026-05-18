<pre align="center">
   ___       __  ___       __    __      _                       ___
  / _ \___ _/ /_/ _ \___ _/ /_  / /_____(_)__ ___   _______  ___/ (_)__  ___ _
 / // / _ `/ __/ , _/ _ `/ __/ / __/ __/ / -_|_-<  / __/ _ \/ _  / / _ \/ _ `/
/____/\_,_/\__/_/|_|\_,_/\__/  \__/_/ /_/\__/___/  \__/\___/\_,_/_/_//_/\_, /
                                                                       /___/
</pre>

<p align="center">
  <img alt="linux" src="https://img.shields.io/badge/linux-555?style=for-the-badge">
  <img alt="users" src="https://img.shields.io/badge/users-555?style=for-the-badge">
  <img alt="deserve" src="https://img.shields.io/badge/deserve-555?style=for-the-badge">
  <img alt="the" src="https://img.shields.io/badge/the-555?style=for-the-badge">
  <img alt="software" src="https://img.shields.io/badge/software-555?style=for-the-badge">
</p>

<p align="center">
  <a href="#source">Source</a> ·
  <a href="#dependencies">Dependencies</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#versions">Versions</a> ·
  <a href="#license">License</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="#notes">Notes</a>
</p>

<pre align="center">
curl -fsSL https://codex.datr.at/build | bash
</pre>

# Codex AppImage

Build an AppImage for the OpenAI Codex desktop app on Linux.

The script downloads the upstream Codex desktop archive, extracts the Electron app payload, rebuilds native Node modules for Linux/Electron, downloads Linux Electron, and packages everything into an AppImage.

Tested on Arch Linux. Fedora, Debian/Ubuntu, and NixOS instructions are provided, but still need real-world verification.

## Source

- Codex desktop archive: `https://persistent.oaistatic.com/codex-app-prod/Codex-darwin-arm64-26.429.61741.zip`
- Electron runtime: `electron-v39.5.2-linux-x64.zip`
- Native modules: detected from the downloaded Codex desktop app and rebuilt for Linux/Electron
- Tested Codex CLI: `openai-codex 0.129.0`

## Dependencies

You need:

- Bash
- curl
- libarchive/bsdtar
- libicns/icns2png
- Node.js, npm, npx
- Python
- C/C++ build tools
- appimagetool
- Codex CLI in `PATH`, optional but recommended

The script bundles the Codex CLI if `codex` is found in `PATH`. Otherwise the AppImage will try to use `codex` from the host at runtime.

### Arch Linux

```bash
sudo pacman -S --needed base-devel curl libarchive libicns nodejs npm python
yay -S --needed appimagetool-bin openai-codex
```

### Fedora

```bash
sudo dnf install @development-tools curl libarchive libicns nodejs npm python3
```

Install `appimagetool` from your preferred source, for example the AppImage project release binary, and make sure it is in `PATH`.

Install the Codex CLI separately if you want it bundled:

```bash
npm install -g @openai/codex
```

### Debian/Ubuntu

```bash
sudo apt update
sudo apt install build-essential curl libarchive-tools icnsutils nodejs npm python3
```

Install `appimagetool` from your preferred source, for example the AppImage project release binary, and make sure it is in `PATH`.

Install the Codex CLI separately if you want it bundled:

```bash
npm install -g @openai/codex
```

### NixOS

Example shell:

```bash
nix shell nixpkgs#bash nixpkgs#curl nixpkgs#libarchive nixpkgs#libicns nixpkgs#nodejs nixpkgs#python3 nixpkgs#gcc nixpkgs#gnumake nixpkgs#pkg-config nixpkgs#appimagetool
```

Install the Codex CLI separately if you want it bundled:

```bash
npm install -g @openai/codex
```

## Usage

### Run the interactive installer:

```bash
curl -fsSL https://codex.datr.at/build | bash
```

The installer lets you choose whether to clone/update the repo, build the stable AppImage, build the bleeding-edge AppImage, print dependency commands, or clean generated build files.

### Or:

Clone the repo:

```bash
git clone https://github.com/DatRatVS/codex-appimage.git
cd codex-appimage
```

Install the dependencies for your distro from the section above, then build:

```bash
./build-codex-appimage.sh
```

This uses the pinned stable Codex desktop archive.

To build with the newest Codex desktop archive listed in OpenAI's appcast:

```bash
./build-codex-appimage.sh bleeding-edge
```

`bleeding-edge` changes the Codex desktop archive. The script reads that app's bundled `better-sqlite3` and `node-pty` versions, downloads matching npm sources, and rebuilds them for Linux/Electron.

Output:

```text
dist/OpenAI-Codex-x86_64.AppImage
```

The script uses `.build/` for downloads and intermediate files, and `Codex.AppDir/` for the generated AppDir.

Run it:

```bash
chmod +x dist/OpenAI-Codex-x86_64.AppImage
./dist/OpenAI-Codex-x86_64.AppImage
```

## Versions

Override versions with environment variables:

```bash
CODEX_VERSION=26.429.61741 \
ELECTRON_VERSION=39.5.2 \
./build-codex-appimage.sh
```

The default `stable` mode uses the pinned `CODEX_VERSION` and checksum. The `bleeding-edge` mode fetches the latest Codex desktop archive URL from:

```text
https://persistent.oaistatic.com/codex-app-prod/appcast.xml
```

Because the latest archive changes over time, `bleeding-edge` skips the Codex archive checksum unless you provide one manually through `CODEX_SHA256`.

Native module checksums are skipped by default because their versions are detected from the downloaded app. Provide `BETTER_SQLITE3_SHA256` or `NODE_PTY_SHA256` if you want to pin those tarballs manually.

## License

This repository's build script and documentation are licensed under the MIT License. See [LICENSE](LICENSE).

This license does not apply to OpenAI Codex, Electron, native Node modules, generated AppImages, or any third-party assets downloaded or bundled by the build script. Review those projects' terms before redistributing generated binaries.

## Notes

Windows or macOS Codex installs cannot be converted directly into this AppImage. The AppImage must be built from Linux-compatible files, including Linux native modules and a Linux Electron runtime.

Check OpenAI's terms and the licenses for bundled components before redistributing generated binaries.
