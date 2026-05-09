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
  <a href="README.md">README</a> ·
  <a href="#scope">Scope</a> ·
  <a href="#development">Development</a> ·
  <a href="#pull-requests">Pull Requests</a> ·
  <a href="#licensing">Licensing</a>
</p>

# Contributing

Thanks for helping improve `codex-appimage`.

## Scope

This project builds an AppImage for the OpenAI Codex desktop app on Linux. Contributions should stay focused on:

- Improving Linux packaging reliability.
- Improving distro compatibility.
- Making the build script clearer and safer.
- Improving README/install instructions.
- Fixing reproducibility issues.

Do not commit generated output such as `Codex.AppDir/`, `.build/`, `dist/`, or `.AppImage` files.

## Development

Clone the repo:

```bash
git clone https://github.com/DatRatVS/codex-appimage.git
cd codex-appimage
```

Run a shell syntax check before opening a PR:

```bash
bash -n build-codex-appimage.sh
```

If possible, run a full build:

```bash
./build-codex-appimage.sh
```

The expected output is:

```text
dist/OpenAI-Codex-x86_64.AppImage
```

## Pull Requests

Please include:

- The distro and version you tested on.
- The exact command you ran.
- Whether the final AppImage launched successfully.
- Any relevant terminal errors or warnings.

Keep changes focused. Avoid unrelated formatting churn.

## Licensing

This repo contains build tooling. Be careful not to commit OpenAI app assets, generated AppImage contents, Electron binaries, or other third-party binary artifacts unless their redistribution terms are clear.

The repository's own script and documentation are licensed under the MIT License. See [LICENSE](LICENSE).
