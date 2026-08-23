# clawosiris-container

Container build orchestration for OpenClaw images.

This repository owns GitHub Actions workflows that:

- validate OpenClaw container builds in pull requests
- build from a specific `clawosiris/openclaw` ref
- publish images to GHCR

## Default image

Published images target:

`ghcr.io/clawosiris/openclaw`

## Default build arguments

- `OPENCLAW_INSTALL_BROWSER=true`
- `OPENCLAW_DOCKER_APT_PACKAGES="android-tools-adb usbutils ssh build-essential sudo gh"`
- `OPENCLAW_EXTENSIONS="acpx,active-memory,arcee,brave,browser,codex,document-extract,file-transfer,media-understanding-core,memory-core,signal,thread-ownership,whatsapp"`

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
