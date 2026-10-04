# Independent sandbox images; never append to the OpenClaw runtime overlay.
# Digests pin multi-platform indexes. Apt uses a dated Bookworm snapshot.
FROM docker.io/library/debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251 AS sandbox-base

ARG DEBIAN_SNAPSHOT=20261001T000000Z
RUN set -eu; \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ bookworm main\n' "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list; \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ bookworm-updates main\n' "$DEBIAN_SNAPSHOT" >> /etc/apt/sources.list; \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/%s/ bookworm-security main\n' "$DEBIAN_SNAPSHOT" >> /etc/apt/sources.list; \
    rm -f /etc/apt/sources.list.d/debian.sources; \
    apt-get update -o APT::Update::Error-Mode=any; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl gh git openssh-client jq; \
    rm -rf /var/lib/apt/lists/*

# Caller supplies arbitrary unprivileged UID, writable tmpfs and workspace.
ENV HOME=/tmp GIT_CONFIG_NOSYSTEM=1
WORKDIR /tmp
USER 65532:65532
CMD ["/bin/sh"]

FROM docker.io/library/node:24.19.0-bookworm-slim@sha256:a9f5f7c91a432850b2a8a7797adf5eadb6c733ceed61167806cee7ea7fbc29df AS node-source
FROM sandbox-base AS sandbox-node24
USER root
COPY --from=node-source /usr/local/ /usr/local/
ARG TARGETARCH
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) pnpm_arch=x64; pnpm_sha256=746979ad910f6eba9187c47080e1edfb73129ce2b8d39cc44cb1f6bc72cd571e ;; \
      arm64) pnpm_arch=arm64; pnpm_sha256=60f0b186348a4f740e41269c79351b4d957c28af57b010a336fc7458e4e33134 ;; \
      *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fLsS --retry 3 "https://github.com/pnpm/pnpm/releases/download/v12.5.0/pnpm-linux-$pnpm_arch.tar.gz" -o /tmp/pnpm.tar.gz; \
    printf '%s  /tmp/pnpm.tar.gz\n' "$pnpm_sha256" | sha256sum -c -; \
    mkdir /tmp/pnpm-extract; \
    tar -xzf /tmp/pnpm.tar.gz -C /tmp/pnpm-extract --no-same-owner --no-same-permissions; \
    install -m 0755 /tmp/pnpm-extract/pnpm /usr/local/bin/pnpm; \
    rm -rf /tmp/pnpm.tar.gz /tmp/pnpm-extract; \
    test "$(node --version)" = v24.19.0; \
    test "$(pnpm --version)" = 12.5.0
USER 65532:65532
