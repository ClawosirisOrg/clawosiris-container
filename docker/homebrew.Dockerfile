
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

USER node
RUN set -eu; \
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
