
# Clawosiris runtime overlay: seed a minimal Homebrew prefix for the node user.
USER root

ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew \
    HOMEBREW_NO_ANALYTICS=1 \
    PATH="${PATH}:/home/node/.npm-global/bin:/app/node_modules/.bin:/app/extensions/codex/node_modules/.bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"

RUN install -d -m 0755 "$HOMEBREW_PREFIX/Homebrew" && \
    git init "$HOMEBREW_PREFIX/Homebrew" && \
    git -C "$HOMEBREW_PREFIX/Homebrew" remote add origin https://github.com/Homebrew/brew.git && \
    git -C "$HOMEBREW_PREFIX/Homebrew" fetch --depth=1 origin \
      9e9f316db6990631c097d48a792caf8645a4129e \
      refs/tags/6.0.14:refs/tags/6.0.14 && \
    test "$(git -C "$HOMEBREW_PREFIX/Homebrew" rev-parse 'refs/tags/6.0.14^{commit}')" = 9e9f316db6990631c097d48a792caf8645a4129e && \
    git -C "$HOMEBREW_PREFIX/Homebrew" checkout --detach 9e9f316db6990631c097d48a792caf8645a4129e && \
    test "$(git -C "$HOMEBREW_PREFIX/Homebrew" rev-parse HEAD)" = 9e9f316db6990631c097d48a792caf8645a4129e && \
    install -d -m 0755 "$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin" && \
    ln -s ../Homebrew/bin/brew "$HOMEBREW_PREFIX/bin/brew" && \
    chown -R node:node "$HOMEBREW_PREFIX"

ARG TARGETARCH
RUN set -eu; \
    case "${TARGETARCH:-}" in \
      amd64) \
        himalaya_arch=x86_64; \
        himalaya_sha256=683a2ab8e1534f01e6bda3a69e204d564c31fbfbe20511fc7bc60b67f2e85884; \
        ;; \
      arm64) \
        himalaya_arch=aarch64; \
        himalaya_sha256=c41adab4bc220ba816cdbf865a5df8dc3b358b39ec58b4be0ed2f64e46b1d182; \
        ;; \
      *) \
        echo "ERROR: unsupported TARGETARCH for Himalaya v2.1.0: ${TARGETARCH:-<unset>} (expected amd64 or arm64)" >&2; \
        exit 1; \
        ;; \
    esac; \
    himalaya_archive="/var/tmp/himalaya.${himalaya_arch}-linux.tgz"; \
    curl -fsSL \
      "https://github.com/pimalaya/himalaya/releases/download/v2.1.0/himalaya.${himalaya_arch}-linux.tgz" \
      -o "$himalaya_archive"; \
    printf '%s  %s\n' "$himalaya_sha256" "$himalaya_archive" | sha256sum -c -; \
    tar -xzf "$himalaya_archive" -C /var/tmp himalaya; \
    install -m 0755 /var/tmp/himalaya /usr/local/bin/himalaya; \
    rm -f "$himalaya_archive" /var/tmp/himalaya

RUN set -eu; \
    case "${TARGETARCH:-}" in \
      amd64) \
        gog_sha256=5f73815950f30de4165b7b767103ca45c4950e84a1da601eda5294e9ff94f767; \
        ;; \
      arm64) \
        gog_sha256=21ca9757f67a573115b517854184561cef6b3b73c21e0f60c72229522c7198ac; \
        ;; \
      *) \
        echo "ERROR: unsupported TARGETARCH for gogcli v0.40.0: ${TARGETARCH:-<unset>} (expected amd64 or arm64)" >&2; \
        exit 1; \
        ;; \
    esac; \
    gog_archive="/var/tmp/gogcli_0.40.0_linux_${TARGETARCH}.tar.gz"; \
    gog_tmpdir=/var/tmp/gogcli-install; \
    rm -rf "$gog_tmpdir"; \
    install -d -m 0755 "$gog_tmpdir"; \
    curl -fsSL \
      "https://github.com/openclaw/gogcli/releases/download/v0.40.0/gogcli_0.40.0_linux_${TARGETARCH}.tar.gz" \
      -o "$gog_archive"; \
    printf '%s  %s\n' "$gog_sha256" "$gog_archive" | sha256sum -c -; \
    tar -xzf "$gog_archive" -C "$gog_tmpdir" \
      --no-same-owner --no-same-permissions ./gog; \
    install -m 0755 "$gog_tmpdir/gog" /usr/local/bin/gog; \
    rm -rf "$gog_archive" "$gog_tmpdir"

# Unified Matrix chunks resolve bare SDK imports from /app/node_modules, while
# selected-plugin packaging can keep them below extension-specific trees.
RUN set -eu; \
    matrix_dist=/app/dist/extensions/matrix; \
    if [ -d "$matrix_dist" ]; then \
      ensure_matrix_package() { \
        matrix_package="$1"; \
        matrix_dest="$2"; \
        if [ -L "$matrix_dest" ] && [ ! -e "$matrix_dest" ]; then \
          echo "ERROR: broken Matrix dependency link: $matrix_dest" >&2; \
          exit 1; \
        elif [ -e "$matrix_dest" ]; then \
          if [ ! -d "$matrix_dest" ] || [ ! -f "$matrix_dest/package.json" ]; then \
            echo "ERROR: existing Matrix root dependency is invalid: $matrix_dest" >&2; \
            exit 1; \
          fi; \
          return 0; \
        fi; \
        matrix_source=""; \
        matrix_relative_source=""; \
        if [ -d "$3" ] && [ -f "$3/package.json" ]; then \
          matrix_source="$3"; \
          matrix_relative_source="$4"; \
        elif [ -d "$5" ] && [ -f "$5/package.json" ]; then \
          matrix_source="$5"; \
          matrix_relative_source="$6"; \
        fi; \
        if [ -z "$matrix_source" ]; then \
          echo "ERROR: Matrix root dependency $matrix_package is absent and no valid packaged fallback exists at $3 or $5" >&2; \
          exit 1; \
        fi; \
        matrix_dest_parent="${matrix_dest%/*}"; \
        if [ -L "$matrix_dest_parent" ] && [ ! -e "$matrix_dest_parent" ]; then \
          echo "ERROR: broken Matrix dependency parent link: $matrix_dest_parent" >&2; \
          exit 1; \
        elif [ ! -e "$matrix_dest_parent" ]; then \
          install -d -m 0755 -o node -g node "$matrix_dest_parent"; \
        elif [ ! -d "$matrix_dest_parent" ]; then \
          echo "ERROR: Matrix dependency parent is not a directory: $matrix_dest_parent" >&2; \
          exit 1; \
        fi; \
        ln -s "$matrix_relative_source" "$matrix_dest"; \
        if [ ! -f "$matrix_dest/package.json" ]; then \
          echo "ERROR: Matrix dependency link does not resolve through $matrix_dest to $matrix_source" >&2; \
          exit 1; \
        fi; \
      }; \
      ensure_matrix_package \
        matrix-js-sdk \
        /app/node_modules/matrix-js-sdk \
        /app/dist/extensions/matrix/node_modules/matrix-js-sdk \
        ../dist/extensions/matrix/node_modules/matrix-js-sdk \
        /app/extensions/matrix/node_modules/matrix-js-sdk \
        ../extensions/matrix/node_modules/matrix-js-sdk; \
      ensure_matrix_package \
        @matrix-org/matrix-sdk-crypto-nodejs \
        /app/node_modules/@matrix-org/matrix-sdk-crypto-nodejs \
        /app/dist/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs \
        ../../dist/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs \
        /app/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs \
        ../../extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs; \
      ensure_matrix_package \
        @matrix-org/matrix-sdk-crypto-wasm \
        /app/node_modules/@matrix-org/matrix-sdk-crypto-wasm \
        /app/dist/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-wasm \
        ../../dist/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-wasm \
        /app/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-wasm \
        ../../extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-wasm; \
    fi

USER node
RUN set -eu; \
    if [ -d /app/dist/extensions/matrix ]; then \
      cd /app; \
      node --input-type=module -e 'await import("matrix-js-sdk/lib/matrix.js")'; \
      crypto_nodejs_dir="$(node -p 'require("node:path").dirname(require.resolve("@matrix-org/matrix-sdk-crypto-nodejs"))')"; \
      case "$(node -p 'process.arch')" in \
        x64) crypto_arch=x64 ;; \
        arm64) crypto_arch=arm64 ;; \
        *) \
          echo "ERROR: unsupported architecture for Matrix native crypto: $(node -p 'process.arch')" >&2; \
          exit 1; \
          ;; \
      esac; \
      crypto_binding="$crypto_nodejs_dir/matrix-sdk-crypto.linux-${crypto_arch}-gnu.node"; \
      if [ ! -s "$crypto_binding" ]; then \
        echo "ERROR: Matrix native crypto payload is missing or empty: $crypto_binding" >&2; \
        exit 1; \
      fi; \
      node -e 'require("@matrix-org/matrix-sdk-crypto-nodejs")'; \
      node -e 'require.resolve("@matrix-org/matrix-sdk-crypto-wasm")'; \
    fi
RUN set -eu; \
    test "$(command -v himalaya)" = /usr/local/bin/himalaya && \
    himalaya --version && \
    test "$(command -v gog)" = /usr/local/bin/gog && \
    gog --version && \
    test -f /app/skills/gog/SKILL.md && \
    awk 'NR == 1 { if ($0 != "---") exit 1; next } $0 == "---" { closed = 1; exit found ? 0 : 1 } $0 ~ /^name:[[:space:]]*gog[[:space:]]*$/ { found = 1 } END { if (!found || !closed) exit 1 }' /app/skills/gog/SKILL.md && \
    printf '%s\n' "$PATH" | tr ':' '\n' | grep -Fx /home/node/.npm-global/bin && \
    brew --version && \
    test "$(brew --prefix)" = "$HOMEBREW_PREFIX" && \
    touch "$HOMEBREW_PREFIX/.write-test" && \
    rm "$HOMEBREW_PREFIX/.write-test" && \
    test -d /app/node_modules/.bin && \
    codex_path="$(command -v codex || true)"; \
    case "$codex_path" in \
      /app/node_modules/.bin/codex|/app/extensions/codex/node_modules/.bin/codex) ;; \
      *) \
        echo "ERROR: bundled Codex executable not found in the root or extension-local pnpm bin directory (resolved: ${codex_path:-<not found>})" >&2; \
        exit 1; \
        ;; \
    esac; \
    printf 'Bundled Codex executable: %s\n' "$codex_path" && \
    codex --version
