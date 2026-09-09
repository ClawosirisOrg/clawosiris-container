# clawosiris-container

Container build orchestration for OpenClaw images.

This repository owns GitHub Actions workflows that:

- validate OpenClaw container builds in pull requests
- build from a specific `ClawosirisOrg/openclaw` ref
- publish images to GHCR

## Default image

Published images target:

`ghcr.io/clawosirisorg/openclaw`

## Default build arguments

- `OPENCLAW_INSTALL_BROWSER=true`
- `OPENCLAW_DOCKER_APT_PACKAGES="android-tools-adb build-essential ffmpeg fontconfig gh ghostscript imagemagick jq pandoc pipx ripgrep rsync ssh sudo tesseract-ocr texlive-latex-base time tmux usbutils weasyprint xsltproc"`
- `OPENCLAW_EXTENSIONS="acpx,active-memory,arcee,brave,browser,codex,document-extract,file-transfer,llama-cpp,matrix,memory-core,signal,whatsapp"`

The default Debian packages provide native coverage for:

- agent and CLI tools: GitHub CLI, `jq`, `pipx`, ripgrep, `rsync`, `time`, and `tmux`, plus the existing build, SSH, Android, USB, and privilege-management tools
- media and OCR: FFmpeg, fontconfig, ImageMagick, and Tesseract OCR
- documents and TeX: Ghostscript, Pandoc, `texlive-latex-base`, WeasyPrint, and `xsltproc`

Debian Bookworm's ImageMagick 6 provides `convert`-style tools, but it is not a drop-in replacement for Homebrew ImageMagick 7's `magick` command. Likewise, `texlive-latex-base` provides basic LaTeX capability rather than parity with the full 4.8 GB Homebrew TeX Live installation.

The following tools are intentionally not treated as native-equivalent in Bookworm: Go (Bookworm 1.19 is materially older than the current toolchain), `yt-dlp` (the Bookworm package is from 2023), `himalaya`, `gog`, `summarize`, `gifgrep`, `tectonic`, `uv`, Deno, and `signal-cli`.

## Homebrew layer

The image includes only the Homebrew package manager, installed at the standard Linux prefix `/home/linuxbrew/.linuxbrew`. The build pins Homebrew to commit `9e9f316db6990631c097d48a792caf8645a4129e` (Homebrew 6.0.14), disables analytics, and leaves the entire prefix writable by the runtime `node` user. No formulae are preinstalled.

The app-local pnpm binary directory and Homebrew's `bin` and `sbin` directories are appended to `PATH`, in that order. Debian and `/usr/local` executables therefore keep precedence, pnpm-installed apps from `/app/node_modules/.bin` are available to the runtime `node` user, and Homebrew-installed commands fill remaining gaps in the native tool set.

Both workflows run `scripts/prepare-dockerfile.sh` after checking out OpenClaw. The script appends the tracked `docker/homebrew.Dockerfile` layer to the selected upstream Dockerfile and writes `openclaw/Dockerfile.clawosiris`, which is the file passed to Buildx.

## Codex CLI

The selected OpenClaw Codex extension already includes its lockfile-pinned `@openai/codex` package. The runtime overlay exposes its CLI, along with other executables from the production pnpm install, through `/app/node_modules/.bin` on `PATH`; it does not install or pin a second Codex copy. Consequently, the CLI version follows the Codex extension and OpenClaw lockfile whenever the image is rebuilt.

Codex authentication remains runtime state. Credentials, API keys, access tokens, and login automation are not included in the image.

## Persistent Homebrew Quadlet volume

The files under `quadlet/` extend an existing rootless `openclaw.container` unit without replacing it. Install them for the user that runs OpenClaw:

```sh
mkdir -p ~/.config/containers/systemd/openclaw.container.d
cp quadlet/openclaw-homebrew.volume ~/.config/containers/systemd/
cp quadlet/openclaw.container.d/10-homebrew-volume.conf \
  ~/.config/containers/systemd/openclaw.container.d/
systemctl --user daemon-reload
systemctl --user restart openclaw.service
```

The drop-in references `openclaw-homebrew.volume` directly, so Quadlet creates the named volume and orders the generated services correctly. It mounts the volume at `/home/linuxbrew/.linuxbrew`. The mount deliberately does not use `nocopy`: on its first use, Podman's default copy-up seeds an empty volume with the pinned Homebrew installation and ownership from the image. Formulae installed later with `brew install` remain in that volume across container recreation and image upgrades.

An existing volume also keeps its current Homebrew checkout when the image changes. Upgrade that persistent installation explicitly with `brew update` and upgrade formulae when desired with `brew upgrade`; the container does not run either command at startup. To adopt a newer image seed instead, stop `openclaw.service`, run `podman volume rm openclaw-homebrew`, and start the service again. Removing the volume permanently removes every formula and other on-demand change in it; the next first mount reseeds only the Homebrew package manager from the image.

## Workflows

- `validate.yml`
  Runs a build-only validation job on pull requests and pushes to `main`.

- `release.yml`
  Manual workflow for building from a selected OpenClaw ref and publishing versioned tags to GHCR.

## Manual release

Run the `Release OpenClaw Container` workflow with:

- `openclaw_ref`
- `version_tag`
- optional overrides for browser install, apt packages, extensions, and `latest`

When publishing to an existing package not connected to this workflow repository, add a package-capable PAT as the `GHCR_TOKEN` repository secret. The workflow prefers `GHCR_TOKEN` and falls back to `GITHUB_TOKEN` when it is absent.

The workflow always produces a version tag and a commit-SHA tag. If `latest=true`, it also publishes `:latest`.
