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
- `OPENCLAW_DOCKER_APT_PACKAGES="android-tools-adb build-essential ffmpeg fontconfig gh ghostscript imagemagick jq pandoc pipx podman ripgrep rsync ssh sudo tesseract-ocr texlive-latex-base time tmux usbutils weasyprint xsltproc"`
- `OPENCLAW_EXTENSIONS="acpx,active-memory,arcee,brave,browser,codex,document-extract,file-transfer,llama-cpp,matrix,memory-core,signal,whatsapp"`

The default Debian packages provide native coverage for:

- agent and CLI tools: GitHub CLI, `jq`, `pipx`, Podman's remote client mode (`podman --remote`), ripgrep, `rsync`, `time`, and `tmux`, plus the existing build, SSH, Android, USB, and privilege-management tools
- media and OCR: FFmpeg, fontconfig, ImageMagick, and Tesseract OCR
- documents and TeX: Ghostscript, Pandoc, `texlive-latex-base`, WeasyPrint, and `xsltproc`

Debian Bookworm's ImageMagick 6 provides `convert`-style tools, but it is not a drop-in replacement for Homebrew ImageMagick 7's `magick` command. Likewise, `texlive-latex-base` provides basic LaTeX capability rather than parity with the full 4.8 GB Homebrew TeX Live installation.

The following tools are intentionally not treated as native-equivalent in Bookworm: Go (Bookworm 1.19 is materially older than the current toolchain), `yt-dlp` (the Bookworm package is from 2023), `summarize`, `gifgrep`, `tectonic`, `uv`, Deno, and `signal-cli`. Himalaya and gog are installed separately from their upstream releases.

## Sandbox images

Independent of the OpenClaw application image, docker/sandbox.Dockerfile builds:

| Target | GHCR multi-arch tag (1.0.0 example) | Contents |
| --- | --- | --- |
| sandbox-base | ghcr.io/clawosirisorg/sandbox:base-bookworm-1.0.0 | Debian Bookworm, gh, git, openssh-client, jq, CA roots, curl |
| sandbox-node24 | ghcr.io/clawosirisorg/sandbox:node24-bookworm-1.0.0 | Base plus Node 24.19.0 and pnpm 12.5.0 |

Release also produces tags with -amd64 and -arm64 suffixes. Base and Node source use pinned multi-architecture image-index digests; Debian packages resolve from signed 20261001T000000Z Bookworm snapshots (including security and updates); pnpm release archives are checked with architecture-specific SHA-256. Bump pins deliberately for security updates. The manual sandbox-release.yml accepts MAJOR.MINOR.PATCH and an optional lowercase prerelease suffix; it builds and smokes both native architectures before pushing them and assembling manifests. sandbox-validate.yml runs the same smoke on PRs and main. Neither workflow changes the existing OpenClaw image path.

Build and test locally:

    podman build -f docker/sandbox.Dockerfile --target sandbox-base -t localhost/sandbox-base:test .
    podman build -f docker/sandbox.Dockerfile --target sandbox-node24 -t localhost/sandbox-node24:test .
    sh scripts/smoke-sandbox.sh localhost/sandbox-base:test base
    sh scripts/smoke-sandbox.sh localhost/sandbox-node24:test node24
    # Optional live egress test (public GitHub availability required):
    SANDBOX_LIVE_GITHUB=1 sh scripts/smoke-sandbox.sh localhost/sandbox-base:test base

The image and smoke default to the deployed OpenClaw UID/GID `1556100503`, with a matching passwd/group entry for NSS-dependent clients. For another runtime UID, build both targets with `--build-arg SANDBOX_UID=<uid>` and run the smoke with `SANDBOX_TEST_UID=<uid>`. On this rootless Podman host, local smoke uses `SANDBOX_TEST_UID=65532` because its subordinate-ID mapping cannot run the configured UID; CI Docker runners test the actual configured UID.

At runtime, the caller must enforce the security boundary: the configured unprivileged UID, read-only root filesystem, dropped capabilities, no-new-privileges, narrow tmpfs and only explicitly mounted workspaces. Use --network none by default. The smoke script checks versions, writable `/workspace`, root write denial and attempted egress at the configured UID with network none, then checks named-bridge container DNS without external dependencies. It disables Corepack network fetches; CLI availability does not imply a populated offline dependency store. Opt-in read-only git ls-remote checks GitHub egress; it is not a CI gate because public service availability is not deterministic. The image itself is **not** a security boundary; engine isolation and mount/network choices are. A bridge grants network access and should be explicitly authorized.

Example locked-down shell:

    podman run --rm -it --user 1556100503:1556100503 --read-only --network none \
      --cap-drop=ALL --security-opt=no-new-privileges \
      --tmpfs /tmp:rw,nosuid,nodev,size=64m,mode=1777 -e HOME=/tmp \
      ghcr.io/clawosirisorg/sandbox:node24-bookworm-1.0.0 /bin/sh

No credentials, tokens, SSH private keys or account configuration are copied into either image or passed by the smoke script. For Git writes, use a dedicated repository-scoped SSH identity; for GitHub API actions, use a broker outside the sandbox. Do not inject a shared `GITHUB_TOKEN`, mount the host home, container socket or SSH agent into an untrusted sandbox. These images contain tools, not OpenClaw itself.

## Homebrew layer

The image includes only the Homebrew package manager, installed at the standard Linux prefix `/home/linuxbrew/.linuxbrew`. The build pins Homebrew to commit `9e9f316db6990631c097d48a792caf8645a4129e` (Homebrew 6.0.14), disables analytics, and leaves the entire prefix writable by the runtime `node` user. No formulae are preinstalled.

The runtime `node` user's global Node package binary directory, the app-root and Codex extension-local pnpm binary directories, and Homebrew's `bin` and `sbin` directories are appended to `PATH`, in that order. Debian and `/usr/local` executables therefore keep precedence. User-global apps in `/home/node/.npm-global/bin` take precedence over bundled production-dependency executables, while Homebrew-installed commands fill remaining gaps in the native tool set.

Himalaya v2.1.0 is installed from its checksum-verified upstream release asset at `/usr/local/bin/himalaya` for amd64 and arm64 images. Because `/usr/local/bin` precedes the appended Homebrew paths, the image-owned binary takes precedence over any same-named Homebrew formula. Himalaya account credentials and account configuration are runtime-only and are not included in the image.

## Google access

The image installs the official `openclaw/gogcli` v0.40.0 release binary at `/usr/local/bin/gog`. The build selects the published Linux amd64 or arm64 archive from `TARGETARCH` and verifies its pinned SHA-256 checksum before installation. Because `/usr/local/bin` precedes the appended Homebrew paths, the image-owned `gog` binary takes precedence over any same-named Homebrew formula.

OpenClaw's bundled gog skill remains at `/app/skills/gog/SKILL.md`; this repository does not copy or maintain a second version. The build checks both the binary and the bundled skill so that the selected upstream OpenClaw ref must provide a compatible runtime layout.

Google OAuth client credentials, access tokens, refresh tokens, and account configuration are runtime-only state. They are not included in the image, and the container build performs no login or OAuth flow.

Both workflows run `scripts/prepare-dockerfile.sh` after checking out OpenClaw. The script appends the tracked `docker/homebrew.Dockerfile` layer to the selected upstream Dockerfile and writes `openclaw/Dockerfile.clawosiris`, which is the file passed to Buildx.

## Codex CLI

The selected OpenClaw Codex extension already includes its lockfile-pinned `@openai/codex` package. The runtime overlay uses the app-root pnpm binary directory at `/app/node_modules/.bin` first, with `/app/extensions/codex/node_modules/.bin` as a compatibility fallback for upstream layouts that keep the CLI extension-local; it does not install or pin a second Codex copy. User-global apps installed in `/home/node/.npm-global/bin` appear earlier on `PATH`, so a user-global Codex installation overrides that bundled fallback. Otherwise, the CLI version follows the Codex extension and OpenClaw lockfile whenever the image is rebuilt. The image build fails with a diagnostic if neither bundled executable is present.

Codex authentication remains runtime state. Credentials, API keys, access tokens, and login automation are not included in the image.

## Matrix runtime dependencies

When the selected upstream OpenClaw build includes Matrix, its production dependencies can remain under the packaged `/app/dist/extensions/matrix/node_modules` tree or the workspace-style `/app/extensions/matrix/node_modules` tree. Some unified chunks under `/app/dist` import the Matrix SDK packages by bare name, so Node resolves them from `/app/node_modules` instead. The runtime overlay bridges that packaging boundary with relative links for `matrix-js-sdk`, `@matrix-org/matrix-sdk-crypto-nodejs`, and `@matrix-org/matrix-sdk-crypto-wasm`. It uses only the lockfile-installed packages already present in the image and never runs an additional package-manager install.

The compatibility layer is conditional: builds that omit the packaged Matrix dist create no links. Each valid package already exposed at the root is preserved before the overlay considers either fallback tree. If a root package is absent, the overlay prefers the packaged dist tree and then the workspace-style tree; the build fails clearly when neither contains a valid package or when an existing root path or compatibility link is invalid.

Matrix-enabled builds also smoke-test the resulting root resolution from `/app`: the JavaScript SDK must import, the WASM package must resolve, and the native crypto package must contain a non-empty payload for the build architecture and load successfully. Matrix homeserver credentials, access tokens, passwords, device state, encryption keys, and recovery material remain runtime-only state and are never included in the image.

## Rootless Quadlet drop-ins

The files under `quadlet/` extend an existing rootless `openclaw.container` unit; they do not provide a complete deployment-specific container definition. Install and operate them as the same host user that owns the existing unit. That user needs a working rootless Podman and systemd user manager with Quadlet support. The base unit must already be installed at `~/.config/containers/systemd/openclaw.container` and configured so the container process can write the bind-mounted state directories.

Each capability is installed explicitly. The normal state and Homebrew drop-ins are under `quadlet/openclaw.container.d/`. The privileged Podman socket drop-in is physically separate under `quadlet/optional-podman-socket/`, so none of the normal installation commands grant socket access.

### State and cache paths

Install the normal state-path drop-in and create its host directories before restarting OpenClaw:

```sh
install -d "$HOME/.config/containers/systemd/openclaw.container.d"
install -d "$HOME/.openclaw" "$HOME/.openclaw/.npm" "$HOME/.cache"
install -m 0644 quadlet/openclaw.container.d/20-state-path.conf \
  "$HOME/.config/containers/systemd/openclaw.container.d/"
systemctl --user daemon-reload
systemctl --user restart openclaw.service
systemctl --user status openclaw.service --no-pager
```

The drop-in uses systemd user-manager specifiers rather than a deployment-specific account: `%h` expands to that user's home directory. It bind-mounts `%h/.openclaw` and `%h/.cache` at the same paths inside the container, sets `HOME=%h`, and places npm's cache at `%h/.openclaw/.npm`. State and cache paths therefore remain stable across container recreation without baking a host user name into the repository.

Changing `HOME` also changes where applications look for `.cache`. The writable `%h/.cache` bind is required alongside the `HOME` override: without it, the container may repeatedly fail to create or write its cache beneath the new home and `openclaw.service` can enter a startup/restart loop. If that happens, confirm all three host directories exist and are writable by the container's configured user mapping, then inspect the logs:

```sh
journalctl --user -u openclaw.service -n 100 --no-pager
```

Both directory mounts end in `:Z`. On SELinux systems, Podman privately relabels those host paths for this container. Do not use these private paths as shared storage for another confined container; the most recent private relabel can remove the earlier container's access. The relabel changes labels on the host directories, so review local SELinux and backup policy before installation.

To update the drop-in, copy the new version over the installed file, run `systemctl --user daemon-reload`, and restart the service. Removing the installed drop-in and reloading/restarting stops the binds and restores the base unit's `HOME`; it does not delete the host's `.openclaw`, npm cache, or `.cache` contents.

### Persistent Homebrew volume

Homebrew persistence remains a separate optional capability. Install its named volume and drop-in for the user that runs OpenClaw:

```sh
install -d "$HOME/.config/containers/systemd/openclaw.container.d"
install -m 0644 quadlet/openclaw-homebrew.volume \
  "$HOME/.config/containers/systemd/"
install -m 0644 quadlet/openclaw.container.d/10-homebrew-volume.conf \
  "$HOME/.config/containers/systemd/openclaw.container.d/"
systemctl --user daemon-reload
systemctl --user restart openclaw.service
```

The drop-in references `openclaw-homebrew.volume` directly, so Quadlet creates the named volume and orders the generated services correctly. It mounts the volume at `/home/linuxbrew/.linuxbrew`. The mount deliberately does not use `nocopy`: on its first use, Podman's default copy-up seeds an empty volume with the pinned Homebrew installation and ownership from the image. Formulae installed later with `brew install` remain in that volume across container recreation and image upgrades.

An existing volume also keeps its current Homebrew checkout and installed formulae when the image changes. Himalaya and gog are installed outside this mount at `/usr/local/bin/himalaya` and `/usr/local/bin/gog`, so persistent Homebrew volumes neither contain nor control either image-owned binary. The bundled gog skill is also outside the mount at `/app/skills/gog/SKILL.md`. Upgrade the persistent Homebrew installation explicitly with `brew update` and `brew upgrade` when desired; the container does not run those commands at startup. To adopt a newer Homebrew image seed instead, stop `openclaw.service`, run `podman volume rm openclaw-homebrew`, and start the service again. Removing the volume permanently removes every formula and other on-demand change in it; the next first mount reseeds only the pinned Homebrew package manager from the image.

### Optional rootless Podman socket

Socket access is optional and highly privileged. It effectively grants the OpenClaw workload control over every container, image, volume, and mounted data available to the host user running `podman.socket`. It is not a sandbox or a safe privilege boundary and is inappropriate for untrusted agents, prompts, tools, or workloads. Do not install this drop-in unless that trust decision is acceptable.

The image contains Podman's remote client, but the host user socket is not enabled or mounted automatically. Enable the rootless socket for the same user that owns `openclaw.container`, then verify it is listening:

```sh
systemctl --user enable --now podman.socket
systemctl --user status podman.socket --no-pager
```

Install only the explicitly optional socket drop-in:

```sh
install -d "$HOME/.config/containers/systemd/openclaw.container.d"
install -m 0644 \
  quadlet/optional-podman-socket/openclaw.container.d/30-podman-socket.conf \
  "$HOME/.config/containers/systemd/openclaw.container.d/"
systemctl --user daemon-reload
systemctl --user restart openclaw.service
systemctl --user status openclaw.service --no-pager
journalctl --user -u openclaw.service -n 100 --no-pager
```

The generated service requires and starts after `podman.socket`. The drop-in mounts the rootless socket from `%t/podman/podman.sock` to `/run/podman/podman.sock` read/write and sets both `CONTAINER_HOST` and `DOCKER_HOST` to `unix:///run/podman/podman.sock`. `%t` is the user manager's runtime directory, normally `/run/user/<uid>`; no fixed UID is required.

The socket mount deliberately sets `SecurityLabelDisable=true`, disabling SELinux separation for the entire OpenClaw container. This is an explicit part of the privileged integration, not a substitute for the `:Z` state-directory labels and not a security boundary.

After restart, list the rootless containers, select the generated OpenClaw container name, and verify the remote client from inside it:

```sh
podman ps --format '{{.Names}}'
OPENCLAW_CONTAINER=systemd-openclaw
podman exec "$OPENCLAW_CONTAINER" podman --remote info
```

Replace `systemd-openclaw` if the base Quadlet sets a different container name. The final command must report the host user's Podman service rather than a local in-container engine.

To revoke access, remove `30-podman-socket.conf` from the installed drop-in directory, run `systemctl --user daemon-reload`, and restart `openclaw.service`. Disable `podman.socket` with `systemctl --user disable --now podman.socket` only if no other user services or tools depend on it.

Validate every tracked Quadlet snippet locally with no project-specific runtime dependencies:

```sh
sh scripts/validate-quadlet.sh
```

## Workflows

- `quadlet-validate.yml`
  Validates Quadlet units and drop-ins on relevant pull requests and pushes to `main`.

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
