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
- `OPENCLAW_EXTENSIONS="acpx,active-memory,arcee,brave,browser,codex,document-extract,file-transfer,memory-core,signal,whatsapp"`

The default Debian packages provide native coverage for:

- agent and CLI tools: GitHub CLI, `jq`, `pipx`, ripgrep, `rsync`, `time`, and `tmux`, plus the existing build, SSH, Android, USB, and privilege-management tools
- media and OCR: FFmpeg, fontconfig, ImageMagick, and Tesseract OCR
- documents and TeX: Ghostscript, Pandoc, `texlive-latex-base`, WeasyPrint, and `xsltproc`

Debian Bookworm's ImageMagick 6 provides `convert`-style tools, but it is not a drop-in replacement for Homebrew ImageMagick 7's `magick` command. Likewise, `texlive-latex-base` provides basic LaTeX capability rather than parity with the full 4.8 GB Homebrew TeX Live installation.

The following tools are intentionally not treated as native-equivalent in Bookworm: Go (Bookworm 1.19 is materially older than the current toolchain), `yt-dlp` (the Bookworm package is from 2023), `himalaya`, `gog`, `summarize`, `gifgrep`, `tectonic`, `uv`, Deno, and `signal-cli`.

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
